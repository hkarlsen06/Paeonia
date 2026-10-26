import SwiftUI

/// True while a sheet or cover that Home presents itself is up, such as the countdown
/// timeline or the story composer. A view under a sheet gets no `onDisappear`, so
/// `HomeFirstStepsCard` reads this to keep its finish moment from playing out of sight.
struct HomeIsCoveredKey: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension EnvironmentValues {
    /// Home's scroll view. The finish moment scrolls the card to the middle of the screen,
    /// so the check and the petals are not left under the tab bar.
    @Entry var homeScrollProxy: ScrollViewProxy?
}

/// The Home card after the first day with a few things to try together. Each row opens
/// its feature and ticks itself off once the thing is done. Once every row is done and
/// the person sees the card, the list clears, a big check lands with a burst of petals,
/// and the card closes itself (`playFinish`). The person can also close it at any time.
struct HomeFirstStepsCard: View {
    let steps: HomeFirstSteps
    let partnerName: String
    /// A sheet that Home presents covers the card (`HomeIsCoveredKey`).
    var isCovered = false
    var onOpen: (HomeFirstStep) -> Void = { _ in }
    var onClose: () -> Void = {}
    /// The finish moment is over, or the card left while it played. Closes the card for good.
    var onFinished: () -> Void = {}

    private enum FinishPhase: Equatable {
        /// Rows are left to do.
        case idle
        /// Every row is done. The card waits until it is in sight with nothing over it.
        case waiting
        /// The list shrinks away.
        case clearing
        /// The check is in, and the petals burst from it at `bloomStart`.
        case checked(bloomStart: Date)
        /// `onFinished` ran. The check stays while Home takes the card away.
        case finished
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dailyFlowIsPresented) private var flowIsPresented
    @Environment(\.homeScrollProxy) private var scrollProxy
    @ScaledMetric(relativeTo: .largeTitle) private var checkSize: CGFloat = 72
    @State private var phase = FinishPhase.idle
    @State private var isAppeared = false
    @State private var momentTask: Task<Void, Never>?

    /// The petals need room around the check. They draw outside the card without taking
    /// layout space.
    private static let bloomSize: CGFloat = 380
    private static let scrollID = "home.firstSteps"

    var body: some View {
        PaeoniaCard {
            list
        }
        // Over the card's own frame, so the card keeps its height until Home removes it.
        .overlay { finishedMark }
        .id(Self.scrollID)
        .onChange(of: steps.isComplete, initial: true) { _, isComplete in
            guard isComplete, phase == .idle else { return }
            phase = .waiting
            scheduleFinishIfSeen()
        }
        .onChange(of: isCovered) { scheduleFinishIfSeen() }
        .onChange(of: flowIsPresented) { scheduleFinishIfSeen() }
        .onChange(of: scenePhase) { scheduleFinishIfSeen() }
        .onAppear {
            isAppeared = true
            scheduleFinishIfSeen()
        }
        .onDisappear {
            isAppeared = false
            // A moment that already started finishes at once, so it never replays half
            // done. One still waiting keeps waiting for the card to come back.
            switch phase {
            case .clearing, .checked:
                finish()
            case .idle, .waiting, .finished:
                momentTask?.cancel()
            }
        }
    }

    private var isListCleared: Bool {
        switch phase {
        case .idle, .waiting: false
        case .clearing, .checked, .finished: true
        }
    }

    private var isChecked: Bool {
        switch phase {
        case .checked, .finished: true
        case .idle, .waiting, .clearing: false
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            header
                .opacity(isListCleared ? 0 : 1)
                .animation(clearing(order: 0), value: isListCleared)
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                ForEach(Array(HomeFirstStep.allCases.enumerated()), id: \.element) { index, step in
                    Button {
                        onOpen(step)
                    } label: {
                        row(step)
                    }
                    .buttonStyle(.paeoniaPressableRow)
                    .accessibilityValue(Text(steps.isDone(step) ? .homeFirstStepsDone : .homeFirstStepsNotDone))
                    .accessibilityIdentifier("home.firstSteps.\(step.rawValue)")
                    .opacity(isListCleared ? 0 : 1)
                    .animation(clearing(order: index + 1), value: isListCleared)
                }
            }
        }
        .scaleEffect(isListCleared && !reduceMotion ? 0.86 : 1)
        .allowsHitTesting(!isListCleared)
        .accessibilityHidden(isListCleared)
    }

    /// Each part of the list fades a beat after the one above it.
    private func clearing(order: Int) -> Animation {
        PaeoniaMotion.standardCurve(duration: PaeoniaMotion.motionDefault)
            .delay(reduceMotion ? 0 : Double(order) * 0.04)
    }

    private var finishedMark: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: checkSize))
                .foregroundStyle(.paeoniaAccentPrimary)
                .symbolEffect(.bounce, value: isChecked && !reduceMotion)
                .background { petals }
                .accessibilityHidden(true)
            Text(.homeFirstStepsFinished)
                .font(PaeoniaTypography.title)
                .foregroundStyle(.paeoniaTextPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(PaeoniaSpacing.cardContentPadding)
        .scaleEffect(isChecked || reduceMotion ? 1 : 0.4)
        .opacity(isChecked ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityHidden(!isChecked)
    }

    /// A burst from the check, and a smaller one a moment later.
    @ViewBuilder
    private var petals: some View {
        if case let .checked(bloomStart) = phase {
            ZStack {
                GamePetalBloom(start: bloomStart, seed: "homeFirstSteps")
                GamePetalBloom(
                    start: bloomStart.addingTimeInterval(0.25),
                    seed: "homeFirstSteps.second",
                    intensity: 0.6
                )
            }
            .frame(width: Self.bloomSize, height: Self.bloomSize)
            // The petals start at once instead of fading in with the check.
            .transition(.identity)
        }
    }

    // MARK: Finish moment

    /// Starts a waiting moment once Home shows the card, with no sheet or answer flow
    /// over it and the app in front. Otherwise it holds off, and a later change tries again.
    private func scheduleFinishIfSeen() {
        guard phase == .waiting else { return }
        momentTask?.cancel()
        guard isAppeared, !isCovered, !flowIsPresented, scenePhase == .active else { return }
        momentTask = Task { await playFinish() }
    }

    /// Waits for the tab switch or the sheet closing to land on the card, and scrolls the
    /// card to the middle of the screen, since Home may have it below the fold. Then the list
    /// shrinks away, the check springs in with a tap and a burst of petals, and it holds
    /// long enough to read before the card closes for good. With Reduce Motion the list
    /// crossfades to the check, with no petals.
    private func playFinish() async {
        try? await Task.sleep(for: .milliseconds(550))
        guard !Task.isCancelled else { return }
        withAnimation(reduceMotion ? nil : PaeoniaMotion.heroMorph) {
            scrollProxy?.scrollTo(Self.scrollID, anchor: .center)
        }
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 150 : 450))
        guard !Task.isCancelled else { return }
        if !reduceMotion {
            withAnimation(PaeoniaMotion.heroMorph) { phase = .clearing }
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }
        }
        withAnimation(reduceMotion ? PaeoniaMotion.meaningfulMoment : .spring(duration: 0.5, bounce: 0.35)) {
            phase = .checked(bloomStart: .now)
        }
        PaeoniaHaptics.firstStepsFinished()
        AccessibilityNotification.Announcement(String(localized: .homeFirstStepsFinished)).post()
        try? await Task.sleep(for: .milliseconds(1_500))
        guard !Task.isCancelled else { return }
        finish()
    }

    private func finish() {
        momentTask?.cancel()
        momentTask = nil
        phase = .finished
        onFinished()
    }

    private var header: some View {
        HStack(alignment: .top, spacing: PaeoniaSpacing.space12) {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
                Text(.homeFirstStepsTitle)
                    .font(PaeoniaTypography.sectionTitle)
                    .foregroundStyle(.paeoniaTextPrimary)
                Text(.homeFirstStepsProgress(steps.doneCount, steps.totalCount))
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .contentTransition(.numericText())
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaTextSecondary)
                    .frame(width: PaeoniaSpacing.compactButtonHeight, height: PaeoniaSpacing.compactButtonHeight)
                    .background(.paeoniaSurfaceSecondary, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.paeoniaPressableCard)
            .accessibilityLabel(Text(.homeFirstStepsClose))
            .accessibilityIdentifier("home.firstSteps.close")
        }
    }

    private func row(_ step: HomeFirstStep) -> some View {
        let isDone = steps.isDone(step)
        return HStack(spacing: PaeoniaSpacing.space12) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(PaeoniaTypography.sectionTitle)
                .foregroundStyle(isDone ? .paeoniaAccentPrimary : .paeoniaTextTertiary)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)

            Text(title(for: step))
                .font(PaeoniaTypography.body)
                .foregroundStyle(isDone ? .paeoniaTextSecondary : .paeoniaTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            Image(systemName: "chevron.right")
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextTertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, PaeoniaSpacing.space8)
        .contentShape(Rectangle())
    }

    private func title(for step: HomeFirstStep) -> LocalizedStringResource {
        switch step {
        case .game: .homeFirstStepsGame(partnerName)
        case .memory: .homeFirstStepsMemory
        case .countdown: .homeFirstStepsCountdown
        case .story: .homeFirstStepsStory
        case .topic: .homeFirstStepsTopic
        }
    }
}

#if DEBUG
#Preview {
    HomeFirstStepsCard(
        steps: HomeFirstSteps(doneSteps: [.game, .countdown]),
        partnerName: "Robin"
    )
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}

#Preview("All done") {
    ScrollView {
        HomeFirstStepsCard(
            steps: HomeFirstSteps(doneSteps: Set(HomeFirstStep.allCases)),
            partnerName: "Robin"
        )
        .padding()
    }
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}
#endif
