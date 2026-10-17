import SwiftUI

/// The countdown to the couple's next event on the Home tab. Countdown is not a tab of
/// its own. It lives here as a derived value computed from when the couple started
/// (`couples.started_on`).
///
/// The tile is one object, one number and one line: a desk calendar with the day count
/// drawn on its page (`CountdownCalendarView`), and under it what the number counts to,
/// such as "days until 500 days together". The event and its day count come from
/// `CoupleDateTimeline`, so a new couple counts down to their first month, a couple of
/// years counts down to their next anniversary or round day count, and a countdown the
/// couple added or a birthday takes the tile when it comes first. How long the couple has
/// been together and the event's date live in `RelationshipTimelineView`.
///
/// Tapping the tile opens `RelationshipTimelineView` (days together, the milestones
/// ahead, and the date editor). On the event's day the page says "Today" and the heart
/// burst plays on its own, once, with a haptic and a sound, when the tile scrolls into
/// view. Without a start date the tile still counts down to a birthday or countdown the
/// couple added. With no date at all the page shows a question mark and the tile opens
/// the date editor.
struct MilestoneCountdownCard: View {
    /// The couple's start date as an `yyyy-MM-dd` string (`couples.started_on`).
    let startedOn: String?
    let isSaving: Bool
    let onSave: (Date) async -> Bool
    /// The couple's countdowns and birthdays. Nil shows milestones only.
    let coupleDates: CoupleDatesViewModel?
    let names: CoupleDateNames

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isEditorPresented = false
    @State private var isTimelinePresented = false
    @State private var selectedDate = Date()
    @State private var celebrationID = 0
    @State private var isCelebrating = false
    /// The milestone date last celebrated automatically, so re-renders on the
    /// milestone day don't replay the burst.
    @State private var celebratedMilestoneDate: Date?
    @State private var isOnScreen = false
    /// The instant the countdown is measured from. Refreshed when the calendar day
    /// changes so the card moves to "Today" without needing a reopen.
    @State private var now = Date()
    /// Whether the number has counted up from a lower value yet. Starts true after the first
    /// tile of an app launch, so a tab switch does not replay it.
    @State private var hasCountedUp = CountUpGate.hasPlayed

    init(
        startedOn: String?,
        isSaving: Bool = false,
        onSave: @escaping (Date) async -> Bool = { _ in false },
        coupleDates: CoupleDatesViewModel? = nil,
        names: CoupleDateNames = CoupleDateNames()
    ) {
        self.startedOn = startedOn
        self.isSaving = isSaving
        self.onSave = onSave
        self.coupleDates = coupleDates
        self.names = names
    }

    /// The soonest event. Nil only when the couple has no date to count down to.
    private var milestone: CoupleDateEvent? {
        // Built per read so it reflects the current calendar/time zone.
        return CoupleDateTimeline().next(startedOn: startedOn, dates: coupleDates?.dates ?? CoupleDates(), now: now)
    }

    var body: some View {
        Group {
            if let milestone {
                card(for: milestone)
            } else {
                setupCard
            }
        }
        .onCalendarDayChange { now = Date() }
        .sheet(isPresented: $isEditorPresented) {
            RelationshipDateEditorView(
                selectedDate: $selectedDate,
                isEditing: startedOn != nil,
                isSaving: isSaving,
                onSave: onSave
            )
            .analyticsScreen("start_date_editor")
        }
        .sheet(isPresented: $isTimelinePresented) {
            RelationshipTimelineView(
                startedOn: startedOn,
                isSaving: isSaving,
                onSave: onSave,
                coupleDates: coupleDates,
                names: names
            )
            .analyticsScreen("relationship_timeline")
        }
    }

    private func card(for milestone: CoupleDateEvent) -> some View {
        let title = milestone.title(names: names)
        let isToday = milestone.daysRemaining == 0
        return Button(action: { isTimelinePresented = true }) {
            tile(
                face: isToday ? .today : .days(shownDays(milestone.daysRemaining)),
                burstID: isCelebrating ? celebrationID : nil,
                // On the day itself the page says "Today", so the line is just the event.
                line: isToday ? Text(verbatim: title) : Text(untilLine(for: milestone, title: title))
            )
        }
        .buttonStyle(.paeoniaPressableCard)
        .accessibilityLabel(accessibilityLabel(for: milestone, title: title))
        .accessibilityHint(Text(.homeMilestoneTimelineAccessibilityHint))
        // Home builds every card up front, so `onAppear` fires while the tile is still
        // below the fold. Wait until it is actually on screen.
        .onScrollVisibilityChange(threshold: 0.8) { isVisible in
            isOnScreen = isVisible
            guard isVisible else { return }
            countUpOnce()
            celebrateIfMilestoneDay(milestone)
        }
        .onChange(of: milestone) { _, milestone in
            if isOnScreen {
                celebrateIfMilestoneDay(milestone)
            }
        }
    }

    private var setupCard: some View {
        Button(action: presentEditor) {
            tile(face: .empty, burstID: nil, line: Text(.homeMilestoneSetupTitle))
        }
        .buttonStyle(.paeoniaPressableCard)
        .accessibilityHint(Text(.homeMilestoneSetupAccessibilityHint))
    }

    /// The calendar with its one line underneath. The calendar takes the space the line
    /// leaves, so the tile stays square and the number is the biggest thing in it.
    private func tile(face: CountdownCalendarView.Face, burstID: Int?, line: Text) -> some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            CountdownCalendarView(face: face, burstID: burstID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            line
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.paeoniaTextPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.85)
                .fixedSize(horizontal: false, vertical: true)
        }
        .milestoneTileChrome()
    }

    /// "days until 500 days together". The number sits on the calendar page above it.
    private func untilLine(for milestone: CoupleDateEvent, title: String) -> LocalizedStringResource {
        milestone.daysRemaining == 1 ? .homeMilestoneUntilEventOne(title) : .homeMilestoneUntilEvent(title)
    }

    /// One sentence for VoiceOver, such as "104 days until 500 days together".
    private func accessibilityLabel(for milestone: CoupleDateEvent, title: String) -> Text {
        if milestone.daysRemaining == 0 {
            return Text(verbatim: "\(String(localized: .homeMilestoneToday)), \(title)")
        }
        let line = String(localized: untilLine(for: milestone, title: title))
        return Text(verbatim: "\(milestone.daysRemaining.formatted()) \(line)")
    }

    /// The number on the page. On the first showing after launch it starts lower, then
    /// counts up to the real value. Reduce Motion shows the real value at once.
    private func shownDays(_ days: Int) -> Int {
        hasCountedUp || reduceMotion ? days : days / 2
    }

    private func countUpOnce() {
        CountUpGate.hasPlayed = true
        hasCountedUp = true
    }

    /// Plays the heart burst once when the card is showing "Today". The moment is
    /// earned by reaching the milestone, not by tapping. Tapping opens the timeline.
    private func celebrateIfMilestoneDay(_ milestone: CoupleDateEvent) {
        guard milestone.daysRemaining == 0, celebratedMilestoneDate != milestone.date else { return }
        celebratedMilestoneDate = milestone.date
        celebrate()
    }

    private func celebrate() {
        celebrationID += 1
        PaeoniaHaptics.milestoneReached()
        GameSound.win.play()
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : PaeoniaMotion.celebrationReveal) {
            isCelebrating = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 500 : 1_400))
            withAnimation(.easeOut(duration: 0.2)) {
                isCelebrating = false
            }
        }
    }

    private func presentEditor() {
        selectedDate = startedOn
            .flatMap { try? PairingStartDate(rawValue: $0) }
            .flatMap { $0.date() }
            ?? Date()
        isEditorPresented = true
    }
}

/// Remembers that the tile has counted up once since the app launched, so switching tabs
/// and coming back does not replay it.
@MainActor
private enum CountUpGate {
    static var hasPlayed = false
}

private extension View {
    /// The tile's square footprint, the same size as the drawing card next to it in the
    /// row. There is no card around it: the calendar is an object of its own and stands
    /// on the page's background. The whole square takes the tap.
    func milestoneTileChrome() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.vertical, PaeoniaSpacing.space8)
            .aspectRatio(1, contentMode: .fit)
            .contentShape(Rectangle())
    }
}

#if DEBUG
#Preview {
    HStack(alignment: .top, spacing: PaeoniaSpacing.space16) {
        MilestoneCountdownCard(startedOn: "2026-01-08")
        Color.clear
    }
    .padding(PaeoniaSpacing.screenHorizontalPadding)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}
#endif
