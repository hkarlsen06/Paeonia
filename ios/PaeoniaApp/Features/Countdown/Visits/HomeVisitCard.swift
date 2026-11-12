import SwiftUI

/// The Us tab card about the next time the partners meet. While they are together it says until
/// when, or that they are together today when only their phones showed it, and that the streak
/// rests on the days it does. With a visit planned it counts the days and names the place and
/// dates. Without one it asks when they meet next, and the person can move the question under
/// the other cards for 30 days. Each is a short row that opens the visit screen with the shared list.
struct HomeVisitCard: View {
    let visits: VisitsViewModel
    let streak: StreakPillState
    /// The card under the other cards, which shows only the question the person moved there.
    let isBelow: Bool

    private static let iconSize: CGFloat = 32

    @State private var isDetailPresented = false
    /// Refreshed at midnight so the count moves on, and a hidden question comes back, while the app
    /// stays open, and when the streak starts or stops resting.
    @State private var now = Date()

    var body: some View {
        content
            .onCalendarDayChange { now = Date() }
            .task(id: streak.changeDates) {
                for date in streak.changeDates where date > Date() {
                    try? await Task.sleep(for: .seconds(date.timeIntervalSinceNow))
                    guard !Task.isCancelled else { return }
                    now = Date()
                }
            }
            .sheet(isPresented: $isDetailPresented) {
                VisitDetailView(visits: visits)
                    .analyticsScreen("visit_detail")
            }
            .preference(key: HomeIsCoveredKey.self, value: isDetailPresented)
    }

    @ViewBuilder
    private var content: some View {
        let card = visits.homeCard(at: now, streak: streak)
        if isBelow {
            if card == .movedPrompt {
                promptRow(canMoveDown: false)
                    .transition(.opacity)
            }
        } else {
            topCard(card)
        }
    }

    @ViewBuilder
    private func topCard(_ card: HomeVisitCardState) -> some View {
        let today = LockScreenCalendarDate(containing: now, in: .current)
        switch card {
        case .hidden, .movedPrompt:
            EmptyView()
        case let .visit(visit):
            cardButton {
                visitCard(
                    headline: visit.phase(on: today).headline ?? "",
                    details: [visit.place?.nameAndCity, visit.dateRangeText()]
                )
            }
        case let .together(until, place):
            cardButton {
                visitCard(
                    headline: until.map { Visit.togetherUntilTitle($0) } ?? String(localized: .homeVisitTogetherToday),
                    details: [
                        place?.nameAndCity,
                        streak.resolved(at: now).restsWhileTogether ? String(localized: .streakTogetherResting) : nil,
                    ]
                )
            }
        case .prompt:
            promptRow(canMoveDown: true)
                .transition(.opacity)
        }
    }

    private func cardButton(@ViewBuilder _ card: () -> some View) -> some View {
        Button { isDetailPresented = true } label: { card() }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.visit.card")
            .transition(.opacity)
    }

    /// The headline with one line under it, two lines in all, so the tiles under it stay on the
    /// first screen.
    private func visitCard(headline: String, details: [String?]) -> some View {
        let detail = details.compactMap(\.self).joined(separator: " · ")
        return PaeoniaCard(padding: PaeoniaSpacing.space12) {
            HStack(spacing: PaeoniaSpacing.space12) {
                icon
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
                    Text(headline)
                        .font(PaeoniaTypography.title)
                        .foregroundStyle(.paeoniaTextPrimary)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.paeoniaTextSecondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                chevron
            }
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var icon: some View {
        Image(systemName: "airplane")
            .font(PaeoniaTypography.caption.weight(.semibold))
            .foregroundStyle(.paeoniaAccentPrimary)
            .frame(width: Self.iconSize, height: Self.iconSize)
            .background(.paeoniaSurfaceSecondary, in: Circle())
            .accessibilityHidden(true)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(PaeoniaTypography.caption.weight(.semibold))
            .foregroundStyle(.paeoniaTextTertiary)
            .accessibilityHidden(true)
    }

    /// As tall as a locked answer row, so the cards under it stay on the first screen.
    private func promptRow(canMoveDown: Bool) -> some View {
        PaeoniaCard(padding: PaeoniaSpacing.space12) {
            HStack(spacing: PaeoniaSpacing.space8) {
                Button { isDetailPresented = true } label: {
                    HStack(spacing: PaeoniaSpacing.space12) {
                        icon
                        Text(.homeVisitPromptTitle)
                            .font(PaeoniaTypography.bodyEmphasis)
                            .foregroundStyle(.paeoniaTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        chevron
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.visit.prompt")

                if canMoveDown { moveDownButton }
            }
        }
    }

    private var moveDownButton: some View {
        Button {
            Task { await visits.movePromptDown() }
        } label: {
            Image(systemName: "xmark")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.paeoniaTextSecondary)
                .frame(width: PaeoniaSpacing.compactButtonHeight, height: PaeoniaSpacing.compactButtonHeight)
                .contentShape(Rectangle())
                // The whole square stays tappable, but the row keeps the icon's height.
                .padding(.vertical, (Self.iconSize - PaeoniaSpacing.compactButtonHeight) / 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(.homeVisitPromptMoveDown))
        .accessibilityIdentifier("home.visit.moveDown")
    }
}
