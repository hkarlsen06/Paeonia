import SwiftUI

/// Native die and pawn controls with every pawn's location, including the partner's.
struct LudoAccessibilityLayer: View {
    let board: LudoBoard
    let me: BoardPlayer
    let die: LudoDieState
    let movableChoices: [LudoChoice]
    let size: CGSize
    let onRoll: () -> Void
    let onChoose: (LudoChoice) -> Void

    let partnerName: String

    var body: some View {
        VStack {
            Spacer()
            GameBoardControls {
                dieControls
                ForEach([me, me.other], id: \.rawValue) { player in
                    Section {
                        ForEach(0..<LudoBoard.pawnsPerPlayer, id: \.self) { pawn in
                            let state = pawnState(player, pawn: pawn)
                            if player == me, let choice = LudoChoice(rawValue: pawn), movableChoices.contains(choice) {
                                Button(state) { onChoose(choice) }
                                    .accessibilityIdentifier("ludo.pawn.\(pawn)")
                            } else {
                                Text(state)
                                    .accessibilityIdentifier("ludo.pawn.state.\(player.rawValue).\(pawn)")
                            }
                        }
                    } header: {
                        Text(player == me ? String(localized: .gamesCellYours) : partnerName)
                    }
                }
            }
            .padding(PaeoniaSpacing.space8)
        }
        .frame(width: size.width, height: size.height)
    }

    private var dieControls: some View {
        Section {
            switch die {
            case .ready:
                Button(.ludoDieRoll, action: onRoll)
                    .accessibilityIdentifier("ludo.roll")
            case let .showing(value, _):
                Text(.ludoDieRolled(value))
            case .rolling:
                ProgressView()
            case .idle:
                EmptyView()
            }
        }
    }

    private func pawnState(_ player: BoardPlayer, pawn: Int) -> String {
        let progress = board.progress[LudoBoard.pawnIndex(player, pawn)]
        let place: String
        if progress == 0 {
            place = String(localized: .ludoPawnBase)
        } else if progress == LudoBoard.homeProgress {
            place = String(localized: .ludoPawnHome)
        } else if let square = LudoBoard.trackSquare(of: player, progress: progress) {
            place = String(localized: .ludoPawnTrack(square + 1, LudoBoard.safeSquares.contains(square)
                ? String(localized: .ludoPawnSafe) : String(localized: .ludoPawnExposed)))
        } else {
            place = String(localized: .ludoPawnHomeLane(LudoBoard.homeProgress - progress))
        }
        return String(localized: .ludoPawnState(pawn + 1, place))
    }
}
