import SwiftUI

/// Sheet opened from the Home tab milestone card: the couple's milestone history and
/// what's ahead, laid out like a lyrics screen. The couple's own countdowns and both
/// birthdays sit between the milestones by date. Tapping one edits it, and the plus
/// menu adds them. "Together for X days" is the focal
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
    /// The couple's countdowns and birthdays. Nil shows milestones only (previews).
    var coupleDates: CoupleDatesViewModel?
    var names = CoupleDateNames()

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isEditorPresented = false
    @State private var selectedDate = Date()
    @State private var dateEditor: CoupleDateEditor?
    /// Once the user scrolls, the veil dissolves for the rest of the presentation —
    /// re-blurring rows someone is trying to read would fight them.
    @State private var isVeilLifted = false
    /// The instant every day count is measured from. Refreshed when the calendar
    /// day changes so a sheet left open overnight moves to the new day.
    @State private var now = Date()

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
            .toolbar { toolbar }
        }
        .presentationDetents([.large])
        .presentationBackground(.paeoniaSurfacePrimary)
        .onCalendarDayChange { now = Date() }
        .sheet(isPresented: $isEditorPresented) {
            RelationshipDateEditorView(
                selectedDate: $selectedDate,
                isEditing: true,
                isSaving: isSaving,
                onSave: onSave
            )
        }
        .sheet(item: $dateEditor) { editor in
            if let coupleDates {
                CoupleDateEditorSheet(editor: editor, coupleDates: coupleDates, names: names)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(action: presentEditor) {
                Image(systemName: "pencil")
                    .accessibilityLabel(Text(.homeMilestoneEditAction))
            }
        }

        if coupleDates != nil {
            ToolbarItem(placement: .primaryAction) {
                addMenu
            }
        }

        ToolbarItem(placement: .confirmationAction) {
            Button(action: { dismiss() }) {
                Text(.commonDone)
            }
        }
    }

    private var timelineContent: some View {
        let past = pastEvents
        let upcoming = upcomingEvents
        return VStack(alignment: .leading, spacing: PaeoniaSpacing.space32) {
            ForEach(Array(past.enumerated()), id: \.element.id) { index, event in
                eventRow(for: event, isPast: true)
                    .modifier(veil(distance: past.count - index))
            }

            hero
                .id(Self.heroID)
                .modifier(veil(distance: 0))

            ForEach(Array(upcoming.enumerated()), id: \.element.id) { index, event in
                eventRow(for: event, isPast: false)
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
            heroTitle
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

    /// "Together for 6 months and 3 days", or a first-day line while the count is still 0.
    private var heroTitle: Text {
        daysTogether == 0
            ? Text(.homeMilestoneTimelineFirstDay)
            : Text(.homeMilestoneTimelineTogetherFor(Self.togetherText(startedOn: startedOn, now: now)))
    }

    @ViewBuilder
    private func eventRow(for event: CoupleDateEvent, isPast: Bool) -> some View {
        if let editor = CoupleDateEditor(event), coupleDates != nil {
            // The couple's own dates open their editor. Milestones come from the start
            // date, which the pencil edits.
            Button { dateEditor = editor } label: {
                eventLabel(for: event, isPast: isPast)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text(.homeMilestoneTimelineEditHint))
        } else {
            eventLabel(for: event, isPast: isPast)
        }
    }

    private func eventLabel(for event: CoupleDateEvent, isPast: Bool) -> some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
            Text(verbatim: event.title(names: names))
                .font(PaeoniaTypography.heroTitle)
                .foregroundStyle(isPast ? .paeoniaTextSecondary : .paeoniaTextPrimary)

            caption(for: event)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(isPast ? .paeoniaTextTertiary : .paeoniaAccentPrimary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private func caption(for event: CoupleDateEvent) -> Text {
        if event.daysRemaining == 0 {
            return Text(.homeMilestoneToday)
        }
        let date = event.date.formatted(dateFormat(for: event.date))
        if event.daysRemaining < 0 {
            return Text(verbatim: date)
        }
        return Text(verbatim: "\(date) · \(Self.daysText(event.daysRemaining))")
    }

    /// Adds a countdown, or a birthday that isn't set yet.
    private var addMenu: some View {
        Menu {
            Button { dateEditor = .newCountdown } label: {
                Label { Text(.homeMilestoneCountdownNewAction) } icon: { Image(systemName: "calendar.badge.plus") }
            }
            ForEach(missingBirthdays, id: \.self) { userID in
                Button { dateEditor = .birthday(userID) } label: {
                    Label {
                        Text(userID == names.currentUserID
                            ? .homeMilestoneBirthdayAddOwn
                            : .homeMilestoneBirthdayAddPartner(names.partnerName))
                    } icon: {
                        Image(systemName: "gift")
                    }
                }
            }
        } label: {
            Image(systemName: "plus")
                .accessibilityLabel(Text(.homeMilestoneTimelineAddAction))
        }
    }

    // MARK: - Derived values

    private var dates: CoupleDates {
        coupleDates?.dates ?? CoupleDates()
    }

    /// The couple's members whose birthday isn't set, the signed-in person first.
    private var missingBirthdays: [UUID] {
        [names.currentUserID, names.partnerUserID]
            .compactMap { $0 }
            .filter { dates.birthdays[$0] == nil }
    }

    /// Recomputed per render so the list refreshes after an edit while the sheet stays
    /// open. The math is a handful of bounded calendar additions.
    private var pastEvents: [CoupleDateEvent] {
        CoupleDateTimeline().past(startedOn: startedOn, dates: dates, now: now, limit: Self.pastLimit)
    }

    private var upcomingEvents: [CoupleDateEvent] {
        CoupleDateTimeline().upcoming(startedOn: startedOn, dates: dates, now: now, milestoneLimit: Self.upcomingLimit)
    }

    /// Weekday, day and month, plus the year when the date is not in the current
    /// year. Past rows from earlier years and upcoming rows more than a year out
    /// would otherwise read as the wrong year.
    private func dateFormat(for date: Date) -> Date.FormatStyle {
        let format = Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide)
        return Calendar.current.isDate(date, equalTo: now, toGranularity: .year) ? format : format.year()
    }

    private var startDate: Date? {
        (try? PairingStartDate(rawValue: startedOn))?.date()
    }

    /// The elapsed whole days. The count comes from the calculator so it matches the
    /// milestone schedule (100 days together lands exactly on the 100-days
    /// milestone). It is never negative: a partner who set the start date from a
    /// time zone that is already on the next day would otherwise produce -1.
    private var daysTogether: Int {
        max(0, RelationshipMilestoneCalculator().daysTogether(startedOn: startedOn, now: now) ?? 0)
    }

    /// Formats a whole-day count as "9 days" / "9 dager". Two plain catalog keys
    /// stand in for pluralization, matching the countdown card's until/until.one
    /// pattern. (Foundation's day-unit styles say "døgn" in Norwegian, which is the
    /// wrong word for this copy.)
    static func daysText(_ days: Int) -> String {
        days == 1
            ? String(localized: .homeMilestoneTimelineDaysOne)
            : String(localized: .homeMilestoneTimelineDays(days.formatted()))
    }

    /// The time since the start date as "7 years, 1 month and 2 days" /
    /// "7 år, 1 måned og 2 dager". Units that are 0 are left out.
    static func togetherText(startedOn: String, now: Date) -> String {
        let time = RelationshipMilestoneCalculator().timeTogether(startedOn: startedOn, now: now)
        var parts: [String] = []
        if let years = time?.year, years > 0 {
            parts.append(years == 1
                ? String(localized: .homeMilestoneTimelineYearsOne)
                : String(localized: .homeMilestoneTimelineYears(years.formatted())))
        }
        if let months = time?.month, months > 0 {
            parts.append(months == 1
                ? String(localized: .homeMilestoneTimelineMonthsOne)
                : String(localized: .homeMilestoneTimelineMonths(months.formatted())))
        }
        if let days = time?.day, days > 0 {
            parts.append(daysText(days))
        }
        return parts.formatted(.list(type: .and))
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
