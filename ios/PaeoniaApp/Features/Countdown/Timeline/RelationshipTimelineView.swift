import SwiftUI

/// Sheet opened from the Us-tab milestone card: the couple's milestone history and
/// what's ahead, laid out like a lyrics screen. "Together for X days" is the focal
/// line; past milestones sit above it and upcoming ones below, each blurring and
/// fading a step further the more milestones it is away from "now" — anchored to
/// the content, not the viewport, so the focal line is sharp wherever it lands.
/// The blur is an opening veil: the first scroll dissolves it so every row is
/// readable while exploring, the way Apple Music clears lyric blur on scrub.
///
/// Owns its whole presentation (navigation bar, detent, background) like
/// `RelationshipDateEditorView`, so callers only need
/// `.sheet { RelationshipTimelineView(...) }`.
struct RelationshipTimelineView: View {
    /// The couple's start date as an `yyyy-MM-dd` string (`couples.started_on`).
    let startedOn: String
    let isSaving: Bool
    let onSave: (Date) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isEditorPresented = false
    @State private var selectedDate = Date()
    /// Once the user scrolls, the veil dissolves for the rest of the presentation —
    /// re-blurring rows someone is trying to read would fight them.
    @State private var isVeilLifted = false

    private static let pastLimit = 4
    private static let upcomingLimit = 8
    /// Where the focal line sits in the viewport on open — a little above center,
    /// with any history peeking out blurred above it.
    private static let focalAnchor: CGFloat = 0.3
    private static let heroID = "timeline.hero"

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    timelineContent
                }
                .onAppear {
                    proxy.scrollTo(Self.heroID, anchor: UnitPoint(x: 0, y: Self.focalAnchor))
                }
                .onScrollPhaseChange { _, newPhase in
                    // Only the user's own touch lifts the veil — the programmatic
                    // scroll that positions the focal line on open must not.
                    guard newPhase == .tracking || newPhase == .interacting, !isVeilLifted else { return }
                    withAnimation(reduceMotion ? nil : PaeoniaMotion.meaningfulMoment) {
                        isVeilLifted = true
                    }
                }
            }
            .background(.paeoniaSurfacePrimary)
            .navigationTitle(Text(.homeMilestoneTimelineTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: presentEditor) {
                        Image(systemName: "pencil")
                            .accessibilityLabel(Text(.homeMilestoneEditAction))
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(action: { dismiss() }) {
                        Text(.commonDone)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(.paeoniaSurfacePrimary)
        .sheet(isPresented: $isEditorPresented) {
            RelationshipDateEditorView(
                selectedDate: $selectedDate,
                isEditing: true,
                isSaving: isSaving,
                onSave: onSave
            )
        }
    }

    private var timelineContent: some View {
        let past = pastMilestones
        let upcoming = upcomingMilestones
        return VStack(alignment: .leading, spacing: PaeoniaSpacing.space32) {
            ForEach(Array(past.enumerated()), id: \.element.date) { index, milestone in
                milestoneRow(for: milestone, isPast: true)
                    .modifier(veil(distance: past.count - index))
            }

            hero
                .id(Self.heroID)
                .modifier(veil(distance: 0))

            ForEach(Array(upcoming.enumerated()), id: \.element.date) { index, milestone in
                milestoneRow(for: milestone, isPast: false)
                    .modifier(veil(distance: index + 1))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.top, PaeoniaSpacing.screenTopSpacing)
        .padding(.bottom, PaeoniaSpacing.space40)
    }

    private func veil(distance: Int) -> TimelineVeilEffect {
        TimelineVeilEffect(distance: distance, isLifted: isVeilLifted || reduceTransparency)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
            Text(.homeMilestoneTimelineTogetherFor(daysTogetherText))
                .font(PaeoniaTypography.display)
                .foregroundStyle(.paeoniaTextPrimary)

            if let startDate {
                Text(.homeMilestoneTimelineSince(
                    startDate.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
                ))
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private func milestoneRow(for milestone: RelationshipMilestone, isPast: Bool) -> some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
            Text(milestone.kind.displayName)
                .font(PaeoniaTypography.heroTitle)
                .foregroundStyle(isPast ? .paeoniaTextSecondary : .paeoniaTextPrimary)

            caption(for: milestone)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(isPast ? .paeoniaTextTertiary : .paeoniaAccentPrimary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private func caption(for milestone: RelationshipMilestone) -> Text {
        if milestone.daysRemaining == 0 {
            return Text(.homeMilestoneToday)
        }
        let date = milestone.date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        if milestone.daysRemaining < 0 {
            return Text(verbatim: date)
        }
        return Text(verbatim: "\(date) · \(Self.daysText(milestone.daysRemaining))")
    }

    // MARK: - Derived values

    /// Recomputed per render so the list refreshes after the date is edited while
    /// the sheet stays open. The math is a handful of bounded calendar additions.
    private var pastMilestones: [RelationshipMilestone] {
        RelationshipMilestoneCalculator().pastMilestones(startedOn: startedOn, limit: Self.pastLimit)
    }

    private var upcomingMilestones: [RelationshipMilestone] {
        RelationshipMilestoneCalculator().upcomingMilestones(startedOn: startedOn, limit: Self.upcomingLimit)
    }

    private var startDate: Date? {
        (try? PairingStartDate(rawValue: startedOn))?.date()
    }

    /// The elapsed time as a localized "186 days" string. The day count comes from
    /// the calculator so it matches the milestone schedule (100 days together lands
    /// exactly on the 100-days milestone).
    private var daysTogetherText: String {
        Self.daysText(RelationshipMilestoneCalculator().daysTogether(startedOn: startedOn) ?? 0)
    }

    /// Formats a whole-day count as "9 days" / "9 dager". Two plain catalog keys
    /// stand in for pluralization, matching the countdown card's until/until.one
    /// pattern. (Foundation's day-unit styles say "døgn" in Norwegian, which is the
    /// wrong word for this copy.)
    private static func daysText(_ days: Int) -> String {
        days == 1
            ? String(localized: .homeMilestoneTimelineDaysOne)
            : String(localized: .homeMilestoneTimelineDays(days.formatted()))
    }

    private func presentEditor() {
        selectedDate = startDate ?? Date()
        isEditorPresented = true
    }
}

/// The lyrics-screen treatment: each row softens a step further per milestone of
/// distance from the "Together for X days" line, so "now" is always sharp no
/// matter where it sits — even when there's no history above it. Content-anchored,
/// not viewport-anchored, and fully lifted once the user starts exploring.
private struct TimelineVeilEffect: ViewModifier {
    /// How many milestones this row is away from "now"; 0 is the focal line.
    let distance: Int
    let isLifted: Bool

    func body(content: Content) -> some View {
        // Three steps out reaches full softness.
        let softness = isLifted ? 0 : min(Double(distance) / 3, 1)
        content
            .blur(radius: softness * 5)
            .opacity(1 - 0.6 * softness)
    }
}

#if DEBUG
#Preview {
    Color.paeoniaBackgroundPrimary
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            RelationshipTimelineView(
                startedOn: "2026-01-08",
                isSaving: false,
                onSave: { _ in true }
            )
        }
        .preferredColorScheme(.dark)
}
#endif
