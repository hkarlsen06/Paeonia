import SwiftUI

/// The countdown to the couple's next milestone on the Us tab. Countdown is not a
/// tab of its own — it lives here as a derived value computed from when the couple
/// started (`couples.started_on`).
///
/// The card reads as one sentence the number leads: "25 days until · your first
/// month together", with the date underneath. Leading with the day count makes the
/// countdown the hero (instead of competing with the milestone name) and folds the
/// "counting down to" framing into the same line, so there's no separate overline.
/// The milestone, its day count, and its date all come from
/// `RelationshipMilestoneCalculator`, so it stays current: a new couple counts down
/// to their first month, while a couple of years counts down to their next
/// anniversary or their next round day count.
///
/// Tapping the card opens `RelationshipTimelineView` (days together, the milestones
/// ahead, and the date editor). The heart burst is reserved for the milestone day
/// itself and plays on its own when the card shows "Today".
struct MilestoneCountdownCard: View {
    /// The couple's start date as an `yyyy-MM-dd` string (`couples.started_on`).
    let startedOn: String?
    let isSaving: Bool
    let onSave: (Date) async -> Bool

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

    init(
        startedOn: String?,
        isSaving: Bool = false,
        onSave: @escaping (Date) async -> Bool = { _ in false }
    ) {
        self.startedOn = startedOn
        self.isSaving = isSaving
        self.onSave = onSave
    }

    private var milestone: RelationshipMilestone? {
        guard let startedOn else { return nil }
        // Built per read so it reflects the current calendar/time zone, and so the
        // day count refreshes whenever the card re-renders.
        return RelationshipMilestoneCalculator().nextMilestone(startedOn: startedOn)
    }

    var body: some View {
        Group {
            if let milestone {
                card(for: milestone)
            } else {
                setupCard
            }
        }
        .sheet(isPresented: $isEditorPresented) {
            RelationshipDateEditorView(
                selectedDate: $selectedDate,
                isEditing: milestone != nil,
                isSaving: isSaving,
                onSave: onSave
            )
        }
        .sheet(isPresented: $isTimelinePresented) {
            if let startedOn {
                RelationshipTimelineView(
                    startedOn: startedOn,
                    isSaving: isSaving,
                    onSave: onSave
                )
            }
        }
    }

    private func card(for milestone: RelationshipMilestone) -> some View {
        Button(action: { isTimelinePresented = true }) {
            VStack(alignment: .center, spacing: PaeoniaSpacing.space12) {
                VStack(alignment: .center, spacing: PaeoniaSpacing.space4) {
                    countdown(for: milestone)

                    // The target date sits right under the count, so "25 days until"
                    // and "Saturday 25 July" read together as the countdown.
                    Text(milestone.date, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextTertiary)
                        .multilineTextAlignment(.center)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                        .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.8)
                }

                // The milestone name follows as part of the same group.
                Text(milestone.kind.displayName)
                    .font(PaeoniaTypography.sectionTitle)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .milestoneTileChrome()
            .overlay {
                if isCelebrating {
                    milestoneCelebration
                        .id(celebrationID)
                        .transition(.opacity)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text(.homeMilestoneTimelineAccessibilityHint))
        .onAppear { celebrateIfMilestoneDay(milestone) }
        .onChange(of: milestone) { _, milestone in
            celebrateIfMilestoneDay(milestone)
        }
    }

    private var setupCard: some View {
        Button(action: presentEditor) {
            VStack(alignment: .center, spacing: PaeoniaSpacing.space12) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.paeoniaAccentPrimary)
                    .accessibilityHidden(true)

                VStack(alignment: .center, spacing: PaeoniaSpacing.space4) {
                    Text(.homeMilestoneSetupTitle)
                        .font(PaeoniaTypography.sectionTitle)
                        .foregroundStyle(.paeoniaTextPrimary)
                        .multilineTextAlignment(.center)

                    Text(.homeMilestoneSetupMessage)
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                }
            }
            .milestoneTileChrome()
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text(.homeMilestoneSetupAccessibilityHint))
    }

    private var milestoneCelebration: some View {
        ZStack {
            if reduceMotion {
                Image(systemName: "heart.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.paeoniaAccentPrimary)
            } else {
                Circle()
                    .fill(.paeoniaAccentPrimary.opacity(0.16))
                    .frame(width: 92, height: 92)
                    .blur(radius: 8)

                Image(systemName: "heart.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.paeoniaAccentPrimary)
                    .symbolEffect(.bounce, value: celebrationID)

                ForEach(0..<8, id: \.self) { index in
                    Image(systemName: index.isMultiple(of: 2) ? "heart.fill" : "sparkle")
                        .font(.system(size: index.isMultiple(of: 2) ? 12 : 15, weight: .semibold))
                        .foregroundStyle(index.isMultiple(of: 3) ? .paeoniaAccentSecondary : .paeoniaAccentPrimary)
                        .offset(
                            x: cos(Double(index) * .pi / 4) * 58,
                            y: sin(Double(index) * .pi / 4) * 58
                        )
                }
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    /// Plays the heart burst once when the card is showing "Today" — the moment is
    /// earned by reaching the milestone, not by tapping. Tapping opens the timeline.
    private func celebrateIfMilestoneDay(_ milestone: RelationshipMilestone) {
        guard milestone.daysRemaining == 0, celebratedMilestoneDate != milestone.date else { return }
        celebratedMilestoneDate = milestone.date
        celebrate()
    }

    private func celebrate() {
        celebrationID += 1
        PaeoniaHaptics.milestoneReached()
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

    @ViewBuilder
    private func countdown(for milestone: RelationshipMilestone) -> some View {
        if milestone.daysRemaining == 0 {
            // On the day itself there's nothing to count down — say so instead of "0".
            Text(.homeMilestoneToday)
                .font(PaeoniaTypography.countdownNumber)
                .foregroundStyle(.paeoniaAccentPrimary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.7)
        } else {
            // Number leads as the hero; "days until" carries into the subject line.
            ViewThatFits(in: .horizontal) {
                countdownLine(for: milestone)

                VStack(alignment: .center, spacing: PaeoniaSpacing.space2) {
                    Text(milestone.daysRemaining, format: .number)
                        .font(PaeoniaTypography.countdownNumber)
                        .foregroundStyle(.paeoniaAccentPrimary)

                    Text(milestone.daysRemaining == 1 ? .homeMilestoneUntilOne : .homeMilestoneUntil)
                        .font(PaeoniaTypography.sectionTitle)
                        .foregroundStyle(.paeoniaTextPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.7)
        }
    }

    private func countdownLine(for milestone: RelationshipMilestone) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: PaeoniaSpacing.space4) {
            Text(milestone.daysRemaining, format: .number)
                .font(PaeoniaTypography.countdownNumber)
                .foregroundStyle(.paeoniaAccentPrimary)

            // Same size and colour as the subject line below so "… days until
            // <milestone>" reads as one sentence, leaving the number as the only
            // large element.
            Text(milestone.daysRemaining == 1 ? .homeMilestoneUntilOne : .homeMilestoneUntil)
                .font(PaeoniaTypography.sectionTitle)
                .foregroundStyle(.paeoniaTextPrimary)
        }
        .lineLimit(1)
    }
}

private extension View {
    /// The Us-tab tile treatment shared with the widget drawing card in the same
    /// row: square footprint, tile fill, rounded corners, hairline stroke, and
    /// lift. Content is centred both ways so it reads as one group with even
    /// space around it.
    func milestoneTileChrome() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(PaeoniaSpacing.space16)
            .aspectRatio(1, contentMode: .fit)
            .background(.paeoniaBackgroundPrimary)
            .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous)
                    .stroke(.paeoniaSurfacePressed, lineWidth: PaeoniaRadius.strokeDefault)
            }
            .shadow(color: .black.opacity(0.25), radius: 18, x: 0, y: 10)
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
