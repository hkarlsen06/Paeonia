import SwiftUI

/// The Us tab card about the next time the partners meet. With a visit planned it counts the
/// days and names the place. Without one it asks when they meet next, and the person can hide
/// that question for 30 days. Tapping the card opens the visit screen with the shared list.
struct HomeVisitCard: View {
    let visits: VisitsViewModel

    /// Until when the "When do you meet next?" card stays hidden, as seconds since 1970.
    @AppStorage("home.visitPrompt.hiddenUntil") private var promptHiddenUntil: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sheet: Sheet?
    /// Refreshed at midnight so the count moves on while the app stays open.
    @State private var now = Date()

    private static let promptHiddenDays = 30

    private enum Sheet: Identifiable {
        case detail
        case newVisit

        var id: Self { self }
    }

    var body: some View {
        content
            .onCalendarDayChange { now = Date() }
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .detail:
                    VisitDetailView(visits: visits)
                        .analyticsScreen("visit_detail")
                case .newVisit:
                    VisitEditorView(visit: nil, visits: visits)
                        .analyticsScreen("visit_editor")
                }
            }
            .preference(key: HomeIsCoveredKey.self, value: sheet != nil)
    }

    @ViewBuilder
    private var content: some View {
        // Nothing until this person's cached visits are read, so the question never flashes
        // over a planned visit.
        if visits.hasLoaded {
            let today = LockScreenCalendarDate(containing: now, in: .current)
            if let visit = visits.state.currentOrNext(on: today), let headline = visit.phase(on: today).headline {
                Button { sheet = .detail } label: {
                    visitCard(visit, headline: headline)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.visit.card")
                .transition(.opacity)
            } else if now.timeIntervalSince1970 >= promptHiddenUntil {
                promptCard
                    .transition(.opacity)
            }
        }
    }

    private func visitCard(_ visit: Visit, headline: String) -> some View {
        PaeoniaCard {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
                PaeoniaCardEyebrow(.homeVisitLabel)
                Text(headline)
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
                    if let place = visit.place {
                        Label {
                            Text(place.nameAndCity)
                        } icon: {
                            Image(systemName: "mappin.and.ellipse")
                        }
                        .font(PaeoniaTypography.bodyEmphasis)
                        .foregroundStyle(.paeoniaAccentPrimary)
                    }
                    Text(visit.dateRangeText())
                        .font(PaeoniaTypography.body)
                        .foregroundStyle(.paeoniaTextSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var promptCard: some View {
        PaeoniaCard {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
                HStack(alignment: .top, spacing: PaeoniaSpacing.space8) {
                    promptText
                    hideButton
                }

                Button { sheet = .newVisit } label: {
                    Text(.homeVisitPlanAction)
                }
                .buttonStyle(PaeoniaSecondaryButtonStyle())
                .accessibilityIdentifier("home.visit.plan")
            }
        }
    }

    private var promptText: some View {
        Button { sheet = .detail } label: {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                Text(.homeVisitPromptTitle)
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)
                Text(.homeVisitPromptMessage)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.visit.prompt")
    }

    private var hideButton: some View {
        Button(action: hidePrompt) {
            Image(systemName: "xmark")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.paeoniaTextSecondary)
                .frame(width: PaeoniaSpacing.compactButtonHeight, height: PaeoniaSpacing.compactButtonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(.homeVisitPromptHide))
        .accessibilityIdentifier("home.visit.hide")
    }

    private func hidePrompt() {
        let until = Calendar.current.date(byAdding: .day, value: Self.promptHiddenDays, to: Date()) ?? Date()
        withAnimation(reduceMotion ? nil : PaeoniaMotion.homeLayoutChange) {
            promptHiddenUntil = until.timeIntervalSince1970
        }
    }
}
