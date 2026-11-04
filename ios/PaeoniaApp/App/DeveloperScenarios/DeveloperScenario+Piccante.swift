#if DEBUG
    import SwiftUI

    nonisolated extension DeveloperScenario {
        static let piccante: [DeveloperScenario] = [
            piccanteHide, piccanteBiting, piccanteLifted, piccanteSniff,
            piccanteBurn, piccanteSameOne, piccanteResult, piccanteChoose,
            piccanteChooseSecond, piccanteSniffHot, piccanteHub,
        ]
        static let piccanteHide = piccanteScreen(
            "piccante-hide", "Piccante · hiding", "Hide a chili and tuck in a note")
        static let piccanteBiting = piccanteScreen(
            "piccante-biting", "Piccante · biting", "Your turn to lift a chocolate and bite")
        static let piccanteLifted = piccanteScreen(
            "piccante-partner-lifted", "Piccante · partner lifted", "Robin has lifted a chocolate")
        static let piccanteSniff = piccanteScreen("piccante-sniff", "Piccante · sniff", "Your private sniff answer")
        static let piccanteBurn = piccanteScreen(
            "piccante-burn", "Piccante · burn", "A chili glows and both secrets open")
        static let piccanteSameOne = piccanteScreen(
            "piccante-same-one", "Piccante · same one", "Both chilis in the same chocolate")
        static let piccanteResult = piccanteScreen(
            "piccante-result", "Piccante · result", "The box and your partner's note")
        static let piccanteChoose = piccanteScreen(
            "piccante-choose", "Piccante · choose a box", "Pick a 3 by 3, 4 by 4 or 5 by 5 box")
        static let piccanteChooseSecond = piccanteScreen(
            "piccante-choose-second", "Piccante · second chooser", "Open the unchosen box as the second partner")
        static let piccanteSniffHot = piccanteScreen(
            "piccante-sniff-hot", "Piccante · hot sniff", "A private chili mark on the board")
        static let piccanteHub = DeveloperScenario(
            "piccante-hub", "Piccante · hub card", "The finished box on the Games card", .games
        ) { _ in DeveloperPiccanteHubScenarioView() }
        private static func piccanteScreen(_ id: String, _ title: String, _ detail: String) -> DeveloperScenario {
            DeveloperScenario(id, title, detail, .games) { DeveloperPiccanteScenarioView(scenario: $0) }
        }
    }

    @MainActor enum DeveloperPiccanteFixture {
        static func state(for scenario: DeveloperScenario) -> RemotePiccanteState {
            let me = DeveloperGamesFixture.me
            let partner = DeveloperGamesFixture.partner
            let finished = [DeveloperScenario.piccanteBurn, .piccanteSameOne, .piccanteResult].contains(scenario)
            let size = boxSize
            let iWon = UserDefaults.standard.bool(forKey: "paeonia-scenario-piccante-winner")
            let myTile = min(12, size * size - 1)
            let partnerTile = scenario == .piccanteSameOne ? myTile : min(10, size * size - 2)
            let game = RemotePiccanteGame(
                id: DeveloperGamesFixture.gameID, gameNumber: 1, version: finished ? 8 : 5,
                starterUserID: scenario == .piccanteChooseSecond ? partner : me,
                turnUserID: finished || [.piccanteChoose, .piccanteChooseSecond].contains(scenario)
                    ? nil : scenario == .piccanteLifted ? partner : me,
                phase: [.piccanteChoose, .piccanteChooseSecond].contains(scenario)
                    ? .choosing : scenario == .piccanteHide ? .hiding : finished ? .finished : .biting,
                size: [.piccanteChoose, .piccanteChooseSecond].contains(scenario) ? nil : size,
                myChili: scenario == .piccanteHide || [.piccanteChoose, .piccanteChooseSecond].contains(scenario)
                    ? nil : myTile,
                myNote: scenario == .piccanteHide ? nil : "You owe me a back rub.",
                partnerHidden: scenario != .piccanteHide,
                mySniff: scenario == .piccanteSniff ? .init(tile: 6, hasChili: false)
                    : scenario == .piccanteSniffHot ? .init(tile: 10, hasChili: true) : nil,
                partnerSniffUsed: scenario == .piccanteSniff,
                bites: scenario == .piccanteHide || [.piccanteChoose, .piccanteChooseSecond].contains(scenario)
                    ? []
                    : finished
                        ? [
                            .init(tile: 0, userID: partner), .init(tile: 3, userID: me),
                            .init(tile: partnerTile, userID: iWon ? partner : me),
                        ]
                        : [.init(tile: 0, userID: partner), .init(tile: 3, userID: me)],
                chilis: finished
                    ? [
                        .init(tile: myTile, userID: me, note: "You owe me a back rub."),
                        .init(tile: partnerTile, userID: partner, note: "Gotcha. A kiss when I see you."),
                    ] : [],
                winnerUserID: finished ? (iWon ? me : partner) : nil,
                loserUserID: finished ? (iWon ? partner : me) : nil,
                myWins: 3, partnerWins: finished ? 5 : 4, gamesFinished: finished ? 8 : 7,
                startedAt: DeveloperGamesFixture.now, finishedAt: finished ? DeveloperGamesFixture.now : nil)
            return RemotePiccanteState(
                userID: me, coupleID: DeveloperScenarioFixture.coupleID, partnerUserID: partner,
                dataEpoch: "piccante-scenario", game: game, unseenResult: finished ? game : nil)
        }
        private static var boxSize: Int {
            let requested = UserDefaults.standard.integer(forKey: "paeonia-scenario-piccante-size")
            return [3, 4, 5].contains(requested) ? requested : 4
        }
        static func configure(_ dependencies: inout GamesDependencies, for scenario: DeveloperScenario) {
            let state = state(for: scenario)
            dependencies.piccanteCache = InMemoryPiccanteCache(state: state)
            dependencies.piccanteGateway = DeveloperPiccanteGateway(state: state)
        }
    }

    actor DeveloperPiccanteGateway: PiccanteGateway {
        var state: RemotePiccanteState
        init(state: RemotePiccanteState) { self.state = state }
        // swiftlint:disable async_without_await
        func loadPiccante() async throws -> RemotePiccanteState { state }
        func ensurePiccante() async throws -> RemotePiccanteState { state }
        func sendPiccante(_ move: PiccanteMove, operation _: SyncClientOperation) async throws -> RemotePiccanteState {
            guard move.action == .sniff, let tile = move.tile, var game = state.game,
                PiccanteRules.canSniff(tile, in: game, userID: state.userID)
            else {
                throw UnavailableGamesGateway.Unavailable()
            }
            game.mySniff = PiccanteSniff(tile: tile, hasChili: tile == 10)
            game.version += 1
            state.game = game
            return state
        }
        func loadPiccanteResult(number _: Int) async throws -> RemotePiccanteGame {
            guard let game = state.game else { throw UnavailableGamesGateway.Unavailable() }
            return game
        }
        // swiftlint:enable async_without_await
    }

    @MainActor private struct DeveloperPiccanteScenarioView: View {
        let scenario: DeveloperScenario
        @State private var model: PiccanteViewModel
        init(scenario: DeveloperScenario) {
            self.scenario = scenario
            var dependencies = DeveloperGamesScenarioFactory.dependencies(for: scenario)
            DeveloperPiccanteFixture.configure(&dependencies, for: scenario)
            let model = PiccanteViewModel(dependencies: dependencies)
            model.configure(participants: DeveloperGamesFixture.participants)
            _model = State(initialValue: model)
        }
        var body: some View {
            NavigationStack {
                PiccanteScreen(viewModel: model)
                    .frame(maxWidth: compactWidth)
            }
            .onChange(of: model.playStyle, initial: true) { _, _ in
                if UserDefaults.standard.bool(forKey: "paeonia-scenario-piccante-together") {
                    model.playStyle = .together
                }
            }
            .onChange(of: model.partnerHere, initial: true) { _, _ in
                if scenario == .piccanteLifted {
                    model.partnerHere = true
                    model.partnerSelected = 6
                }
            }
            .task {
                await model.reload()
                if scenario == .piccanteLifted {
                    model.partnerHere = true
                    model.partnerSelected = 6
                }
                if scenario == .piccanteHide {
                    model.selected = 5
                    model.note = "A kiss when I see you."
                }
                if scenario == .piccanteBiting { model.selected = 6 }
            }
        }
        private var compactWidth: CGFloat {
            UserDefaults.standard.bool(forKey: "paeonia-scenario-piccante-compact") ? 320 : .infinity
        }
    }
#endif
