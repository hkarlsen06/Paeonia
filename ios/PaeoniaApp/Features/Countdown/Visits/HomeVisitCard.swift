import SwiftUI

/// The Us tab card about the next time the partners meet. While they are together it says until
/// when, or that they are together today when only their phones showed it, and that the streak
/// rests on the days it does. With a visit planned it counts the days and names the place and
/// dates. Without one it asks when they meet next, and the person can hide it for 30 days. Each
/// is a short row that opens the visit screen with the shared list.
struct HomeVisitCard: View {
    let visits: VisitsViewModel
    let streak: StreakPillState

    private static let iconSize: CGFloat = 32

    @State private var isDetailPresented = false
    /// Refreshed at midnight so the count moves on, and a hidden question comes back, while the app stays open.
    @State private var now = Date()

    var body: some View {
        content
            .onCalendarDayChange { now = Date() }
            .sheet(isPresented: $isDetailPresented) {
                VisitDetailView(visits: visits)
                    .analyticsScreen("visit_detail")
            }
            .preference(key: HomeIsCoveredKey.self, value: isDetailPresented)
    }

    @ViewBuilder
    private var content: some View {
        let today = LockScreenCalendarDate(containing: now, in: .current)
        switch visits.homeCard(on: today, streak: streak) {
        case .hidden:
            EmptyView()
        case let .visit(visit):
            cardButton {
                visitCard(
                    headline: visit.phase(on: today).headline ?? "",
                    detail: [visit.place?.nameAndCity, visit.dateRangeText()].compactMap(\.self).joined(separator: " · ")
                )
            }
        case let .together(until, place):
            cardButton {
                visitCard(
                    headline: until.map { Visit.togetherUntilTitle($0) } ?? String(localized: .homeVisitTogetherToday),
                    detail: [
                        place?.nameAndCity,
                        streak.restsWhileTogether(on: today) ? String(localized: .streakTogetherResting) : nil,
                    ].compactMap(\.self).joined(separator: " · ")
                )
            }
        case .prompt:
            promptRow
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
    private func visitCard(headline: String, detail: String) -> some View {
        PaeoniaCard(padding: PaeoniaSpacing.space12) {
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
    private var promptRow: some View {
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

                hideButton
            }
        }
    }

    private var hideButton: some View {
        Button {
            Task { await visits.hidePrompt() }
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
        .accessibilityLabel(Text(.homeVisitPromptHide))
        .accessibilityIdentifier("home.visit.hide")
    }
}
