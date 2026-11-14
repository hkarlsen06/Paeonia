import Foundation

/// The sniff target stays on this phone. Only a confirmed sniff goes to the server, and never over the relay.
enum PiccanteBoardMode: Equatable {
    case bite
    case sniff(target: Int?)
}

extension PiccanteViewModel {
    /// The board lifts the sniff target while sniffing, so the public bite selection stays where it was.
    var boardSelection: Int? {
        switch boardMode {
        case .bite: selected
        case .sniff(let target): target
        }
    }

    var canStartSniff: Bool {
        game?.phase == .biting && game?.mySniff == nil && canAct
    }

    func canSniff(_ tile: Int) -> Bool {
        guard let game, let userID else { return false }
        return PiccanteRules.canSniff(tile, in: game, userID: userID)
    }

    func startSniff() {
        guard canStartSniff else { return }
        boardMode = .sniff(target: nil)
    }

    func cancelSniff() {
        boardMode = .bite
    }

    func confirmSniff() async {
        guard case .sniff(let target?) = boardMode else { return }
        await act(.sniff, tile: target)
    }
}
