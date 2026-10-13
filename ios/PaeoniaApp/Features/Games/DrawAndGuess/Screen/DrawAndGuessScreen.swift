import SwiftUI

/// The Draw & Guess screen. It shows the part of the turn the person is in and
/// holds no game rules: `DrawAndGuessViewModel` decides the phase, and the
/// phase views call its actions.
struct DrawAndGuessScreen: View {
    @Bindable var viewModel: DrawAndGuessViewModel

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            phaseContent
                .id(phaseIdentity)
                .transition(phaseTransition)
        }
        .animation(reduceMotion ? PaeoniaMotion.buttonPress : PaeoniaMotion.meaningfulMoment, value: phaseIdentity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .paeoniaScreenBackground(.paeoniaBackgroundSecondary)
        .navigationTitle(Text(.gamesDrawAndGuessName))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.paeoniaBackgroundSecondary, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .task { await viewModel.start() }
        .onAppear { viewModel.prefersReducedMotion = reduceMotion }
        .onChange(of: reduceMotion) { _, newValue in viewModel.prefersReducedMotion = newValue }
        .onDisappear { viewModel.stop() }
        .onChange(of: scenePhase) { _, phase in
            viewModel.scenePhaseChanged(isActive: phase == .active)
        }
        .onChange(of: viewModel.notice) { _, notice in
            guard let notice else { return }
            bannerCenter.show(notice.banner)
            viewModel.clearNotice()
        }
        .accessibilityIdentifier("draw.screen")
    }

    /// Cross-fade and a 12 point rise. Reduce Motion keeps only the cross-fade.
    private var phaseTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(insertion: .opacity.combined(with: .offset(y: 12)), removal: .opacity)
    }

    /// Changes when the screen needs a new view, so state such as a replay starts
    /// fresh for each round. The guesser's screen and the drawer's result each
    /// stay one view from the first stroke to the result, so the reveal can play
    /// on the screen the player already looks at.
    private var phaseIdentity: String {
        let round = viewModel.round?.id.uuidString ?? "none"
        switch viewModel.phase {
        case .watchingLive, .guessing:
            return "guess-\(round)"
        case .reveal:
            return "\(isDrawerOfRound ? "drawer" : "guess")-\(round)"
        case .waitingForGuess:
            return "drawer-\(round)"
        default:
            return "\(viewModel.phase)-\(round)"
        }
    }

    private var isDrawerOfRound: Bool {
        guard let round = viewModel.round, let userID = viewModel.currentUserID else { return false }
        return round.isDrawer(userID)
    }

    /// The view a phase shows. The guesser's screen and the drawer's result each
    /// keep one case across their playing and revealed phases, so SwiftUI keeps
    /// the same view, with its measured square and scroll position, when the
    /// result arrives.
    private enum Screen {
        case status, chooseWord, waiting, drawing, drawerResult, guess
    }

    private var screen: Screen {
        switch viewModel.phase {
        case .loading, .needsSetup, .preparing, .waitingToSync: .status
        case .chooseWord: .chooseWord
        case .waitingForWord, .waitingForDrawing: .waiting
        case .drawing: .drawing
        case .waitingForGuess: .drawerResult
        case .watchingLive, .guessing: .guess
        case .reveal: isDrawerOfRound ? .drawerResult : .guess
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch screen {
        case .status:
            DrawAndGuessStatusView(viewModel: viewModel)
        case .chooseWord:
            DrawAndGuessChooseWordView(viewModel: viewModel)
        case .waiting:
            DrawAndGuessWaitingView(viewModel: viewModel)
        case .drawing:
            DrawAndGuessDrawingView(viewModel: viewModel)
        case .drawerResult:
            DrawAndGuessDrawerResultView(viewModel: viewModel)
        case .guess:
            DrawAndGuessGuessView(viewModel: viewModel)
        }
    }
}
