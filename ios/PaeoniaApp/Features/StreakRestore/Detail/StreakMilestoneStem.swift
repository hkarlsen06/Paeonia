import SwiftUI

/// The streak sheet's milestone block: how many days are left to the next
/// milestone, and a stem with a flower for each milestone around it. The stem grows
/// as far as the current streak, and a mark shows the couple's record when it is
/// longer. Tapping a flower the streak reached showers petals.
struct StreakMilestoneStem: View {
    let currentCount: Int
    let longestCount: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.petalShower) private var petalShower
    /// How far the stem has grown toward the current streak since the sheet appeared, 0 to 1.
    @State private var grown: Double = 0

    var body: some View {
        let stem = StreakMilestones.stem(currentCount: currentCount, longestCount: longestCount)
        VStack(spacing: PaeoniaSpacing.space8) {
            Text(.streakDetailDaysToMilestone(
                days: stem.daysToNext,
                String(localized: StreakMilestones.name(for: stem.next).label)
            ))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.paeoniaTextPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: PaeoniaSpacing.space2) {
                if let record = stem.record {
                    StemPositionLayout(position: record.position) {
                        Text(.streakDetailRecord(record.days))
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.paeoniaTextSecondary)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 0) {
                    ForEach(stem.nodes) { node in
                        column(node)
                    }
                }
                .background(alignment: .top) {
                    StreakStemDrawing(stem: stem, grown: grown)
                        .frame(height: StreakPeony.size)
                        .accessibilityHidden(true)
                }
            }
        }
        .onAppear(perform: grow)
    }

    /// A flower the streak reached is a button that showers petals.
    @ViewBuilder
    private func column(_ node: StreakStem.Node) -> some View {
        if node.state == .bloomed {
            Button { celebrate(node) } label: { columnContent(node) }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel(node))
        } else {
            columnContent(node)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel(node))
        }
    }

    /// Room for the flower the stem draws behind it, and the milestone's name.
    private func columnContent(_ node: StreakStem.Node) -> some View {
        VStack(spacing: PaeoniaSpacing.space2) {
            Color.clear
                .frame(height: StreakPeony.size)
            // Six columns can't hold the names at accessibility sizes. VoiceOver still reads each flower.
            if !dynamicTypeSize.isAccessibilitySize {
                Text(StreakMilestones.name(for: node.days).label)
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(labelColor(node.state))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.compactButtonHeight, alignment: .top)
        .contentShape(.rect)
    }

    private func accessibilityLabel(_ node: StreakStem.Node) -> Text {
        switch node.state {
        case .bloomed, .bloomedBefore: Text(.streakDetailMilestoneReachedAccessibility(node.days))
        case .opening, .bud: Text(.streakDetailMilestoneNotReachedAccessibility(node.days))
        }
    }

    private func labelColor(_ state: StreakStem.Node.State) -> Color {
        switch state {
        case .bloomed: .paeoniaTextPrimary
        case .opening: .paeoniaAccentPrimary
        case .bloomedBefore: .paeoniaTextSecondary
        case .bud: .paeoniaTextTertiary
        }
    }

    private func celebrate(_ node: StreakStem.Node) {
        petalShower(seed: "streak.milestone.\(node.days)")
    }

    private func grow() {
        guard grown < 1 else { return }
        if reduceMotion {
            grown = 1
        } else {
            withAnimation(PaeoniaMotion.stemGrowth) { grown = 1 }
        }
    }
}

extension StreakMilestoneName {
    var label: LocalizedStringResource {
        switch self {
        case .days(let days): .streakDetailNextMilestoneDays(days)
        case .weeks(let weeks): .streakDetailMilestoneWeeks(weeks)
        case .month: .streakDetailMilestoneMonth
        case .years(let years): .streakDetailMilestoneYears(years)
        }
    }
}

/// Places its one subview centred at `position` across the width, moved in where
/// it would stick out past either edge.
private struct StemPositionLayout: Layout {
    let position: Double

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews.first?.sizeThatFits(.unspecified) ?? .zero
        return CGSize(width: proposal.width ?? size.width, height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let subview = subviews.first else { return }
        let size = subview.sizeThatFits(.unspecified)
        let half = min(size.width, bounds.width) / 2
        let x = min(max(bounds.minX + bounds.width * position, bounds.minX + half), bounds.maxX - half)
        subview.place(at: CGPoint(x: x, y: bounds.minY), anchor: .top, proposal: ProposedViewSize(size))
    }
}

#if DEBUG
#Preview("With a record") {
    StreakMilestoneStem(currentCount: 12, longestCount: 42)
        .padding()
        .background(.paeoniaSurfacePrimary)
        .preferredColorScheme(.dark)
}

#Preview("At their best") {
    StreakMilestoneStem(currentCount: 30, longestCount: 30)
        .padding()
        .background(.paeoniaSurfacePrimary)
        .preferredColorScheme(.dark)
}
#endif
