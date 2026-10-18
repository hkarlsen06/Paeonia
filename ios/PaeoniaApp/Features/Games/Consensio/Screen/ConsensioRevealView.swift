import SwiftUI

/// The reveal of a guessed round. This person's own pin stands on the line (their
/// guess, or their real spot), the partner's pin drops in next to it, a gold
/// thread joins them, and the verdict and points land. A guess still on its way
/// holds the first frame until the server answers with the real spot.
struct ConsensioRevealView: View {
    @Bindable var viewModel: ConsensioViewModel

    @State private var timeline = ConsensioRevealTimeline()
    @State private var pulseScale: CGFloat = 1
    @State private var isWide = false
    @AccessibilityFocusState private var isTitleFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var round: RemoteConsensioRound? { viewModel.round }

    private var isHeld: Bool {
        viewModel.phase == .reveal(isHeld: true)
    }

    private var isPlacer: Bool {
        round?.placerUserID == viewModel.currentUserID
    }

    private var myValue: Int? {
        isPlacer ? round?.spot : round?.guess
    }

    private var partnerValue: Int? {
        isPlacer ? round?.guess : round?.spot
    }

    private var plan: ConsensioRevealPlan? {
        guard let distance = round?.knownDistance else { return nil }
        return ConsensioRevealPlan(
            verdict: ConsensioRules.verdict(distance: distance),
            points: round?.knownPoints ?? ConsensioRules.points(distance: distance)
        )
    }

    var body: some View {
        // A tap anywhere skips to the settled result. It is a shortcut, and the buttons stay.
        // swiftlint:disable:next accessibility_trait_for_button
        GameFocusedLayout(fillsHeight: true) {
            VStack(spacing: PaeoniaSpacing.space24) {
                Spacer(minLength: PaeoniaSpacing.space8)
                VStack(spacing: PaeoniaSpacing.space8) {
                    Text(verbatim: round?.subject ?? "")
                        .font(PaeoniaTypography.title)
                        .foregroundStyle(.paeoniaTextSecondary)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    stage
                    legend
                        .padding(.bottom, PaeoniaSpacing.space16)
                }
                result
                Spacer(minLength: PaeoniaSpacing.space8)
            }
            .frame(maxWidth: .infinity)
            .overlay {
                // Over the whole screen, so the petals are not clipped to the line.
                if let start = timeline.bloomStart {
                    GamePetalBloom(
                        start: start,
                        seed: round?.id.uuidString ?? "",
                        origin: UnitPoint(x: bloomOriginX, y: 0.38),
                        intensity: 2.2
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
        } bottom: {
            actions
        }
        .simultaneousGesture(TapGesture().onEnded {
            if timeline.canSkip { timeline.skip() }
        })
        .onGeometryChange(for: Bool.self) { proxy in
            proxy.size.width >= 700 && proxy.size.width > proxy.size.height
        } action: { isWide = $0 }
        .onChange(of: plan, initial: true) { beginIfNeeded() }
        .onChange(of: timeline.pulse) { _, _ in pulse() }
        .onChange(of: timeline.verdict) { _, verdict in
            guard verdict != nil else { return }
            announce()
        }
        .onChange(of: timeline.titleShown) { _, shown in
            guard shown else { return }
            viewModel.revealSettled()
            if UIAccessibility.isVoiceOverRunning { isTitleFocused = true }
        }
        .onDisappear { timeline.stop() }
        .accessibilityIdentifier("consensio.reveal")
    }

    // MARK: Timeline

    private func beginIfNeeded() {
        guard !timeline.hasBegun else { return }
        guard let plan, !isHeld else {
            timeline.hold()
            return
        }
        timeline.begin(plan, reduceMotion: reduceMotion)
    }

    /// Where the two pins meet, as a share of the screen's width.
    private var bloomOriginX: Double {
        Double((myValue ?? 50) + (partnerValue ?? myValue ?? 50)) / 200
    }

    private func pulse() {
        guard !reduceMotion else { return }
        withAnimation(.spring(duration: 0.14, bounce: 0)) { pulseScale = 1.16 }
        Task {
            try? await Task.sleep(for: .milliseconds(140))
            withAnimation(.spring(duration: 0.16, bounce: 0)) { pulseScale = 1 }
        }
    }

    private func announce() {
        guard let round, let plan, let spot = round.spot, let guess = round.guess else { return }
        let place = ConsensioScaleValue.string(spot, in: round)
        let guessed = ConsensioScaleValue.string(guess, in: round)
        let verdict = String(localized: Self.title(for: plan.verdict)).trimmingCharacters(in: .punctuationCharacters)
        let name = viewModel.partnerName
        let text = isPlacer
            ? String(localized: .consensioRevealAnnouncementPlacer(name, guessed, place, verdict, plan.points))
            : String(localized: .consensioRevealAnnouncementGuesser(name, place, guessed, verdict, plan.points))
        AccessibilityNotification.Announcement(text).post()
    }

    // MARK: Stage

    private var stage: some View {
        ConsensioRevealStage(
            round: round,
            myValue: myValue,
            partnerValue: partnerValue,
            myStyle: viewModel.myStyle,
            partnerStyle: viewModel.partnerStyle,
            timeline: timeline,
            pulseScale: pulseScale,
            isWide: isWide,
            a11yValue: stageA11yValue,
            isFar: plan?.verdict == .far,
            isSpotOn: plan?.verdict == .spotOn
        )
    }

    private var stageA11yValue: LocalizedStringResource {
        guard timeline.dropped, let round, let spot = round.spot, let guess = round.guess else {
            return .consensioRevealHiddenA11Y(viewModel.partnerName)
        }
        return .consensioRevealStageA11Y(
            ConsensioScaleValue.string(spot, in: round),
            ConsensioScaleValue.string(guess, in: round)
        )
    }

    /// Whose pin is whose, once both are on the line.
    private var legend: some View {
        HStack(spacing: PaeoniaSpacing.space16) {
            legendItem(Text(.consensioRevealYou), color: viewModel.myStyle.color)
            legendItem(Text(verbatim: viewModel.partnerName), color: viewModel.partnerStyle.color)
        }
        .font(PaeoniaTypography.caption.weight(.semibold))
        .foregroundStyle(.paeoniaTextSecondary)
        .opacity(timeline.dropped ? 1 : 0)
        .accessibilityHidden(true)
    }

    private func legendItem(_ text: Text, color: Color) -> some View {
        HStack(spacing: PaeoniaSpacing.space4) {
            Circle().fill(color).frame(width: 10, height: 10)
            text
        }
    }

    // MARK: Result

    @ViewBuilder
    private var result: some View {
        if isHeld, viewModel.isHeldOnPhone {
            ConsensioHeldLine(viewModel: viewModel) {
                Label {
                    Text(.consensioRevealWaitingServer(viewModel.partnerName))
                } icon: {
                    Image(systemName: "clock").accessibilityHidden(true)
                }
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaSyncPending)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("consensio.reveal.held")
            }
        } else if let plan {
            // Laid out from the start and faded in, so the line above never moves.
            VStack(spacing: PaeoniaSpacing.space16) {
                VStack(spacing: PaeoniaSpacing.space4) {
                    Text(Self.title(for: plan.verdict))
                        .font(PaeoniaTypography.largeTitle)
                        .foregroundStyle(.paeoniaTextPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text(line(for: plan))
                        .font(PaeoniaTypography.body)
                        .foregroundStyle(.paeoniaTextSecondary)
                }
                .multilineTextAlignment(.center)
                .accessibilityElement(children: .combine)
                .accessibilityFocused($isTitleFocused)
                .accessibilityIdentifier("consensio.reveal.title")
                ConsensioRevealScoreLine(
                    me: viewModel.me,
                    partner: viewModel.partner,
                    sharedPoints: viewModel.sharedPoints,
                    points: plan.points,
                    countedPoints: timeline.countedPoints
                )
            }
            .opacity(timeline.titleShown ? 1 : 0)
            .offset(y: timeline.titleShown || reduceMotion ? 0 : 12)
            .accessibilityHidden(!timeline.titleShown)
        }
    }

    static func title(for verdict: ConsensioVerdict) -> LocalizedStringResource {
        switch verdict {
        case .spotOn: .consensioRevealSpotOnTitle
        case .soClose: .consensioRevealSoCloseTitle
        case .close: .consensioRevealCloseTitle
        case .far: .consensioRevealFarTitle
        }
    }

    private func line(for plan: ConsensioRevealPlan) -> LocalizedStringResource {
        let name = viewModel.partnerName
        guard let round, let spot = round.spot, let guess = round.guess else { return .consensioRevealOff(0) }
        switch plan.verdict {
        case .spotOn:
            return isPlacer ? .consensioRevealSpotOnPlacer(name) : .consensioRevealSpotOnGuesser(name)
        case .soClose, .close:
            return .consensioRevealOff(abs(spot - guess))
        case .far:
            if isPlacer {
                if ConsensioRules.middleRange.contains(spot), !ConsensioRules.middleRange.contains(guess) {
                    return .consensioRevealFarMiddlePlacer(name)
                }
                let end = guess > 50 ? round.rightEnd : round.leftEnd
                return .consensioRevealFarPlacer(name, ConsensioEndText.inSentence(end))
            }
            if ConsensioRules.middleRange.contains(spot) {
                return .consensioRevealFarMiddleGuesser(name)
            }
            let end = spot > 50 ? round.rightEnd : round.leftEnd
            return .consensioRevealFarGuesser(name, ConsensioEndText.inSentence(end))
        }
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        let isShown = (isHeld && viewModel.isHeldOnPhone) || timeline.actionsShown
        Button {
            viewModel.continueFromReveal()
        } label: {
            Text(isPlacer ? .consensioHandoffContinue : .consensioHandoffPlace)
        }
        .buttonStyle(PaeoniaPrimaryButtonStyle())
        .opacity(isShown ? 1 : 0)
        .offset(y: isShown || reduceMotion ? 0 : 12)
        .allowsHitTesting(isShown)
        .accessibilityHidden(!isShown)
        .accessibilityIdentifier("consensio.reveal.continue")
    }
}
