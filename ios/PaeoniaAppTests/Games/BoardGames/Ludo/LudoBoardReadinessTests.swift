import SwiftUI
import Testing
import UIKit
@testable import PaeoniaApp

@MainActor
struct LudoBoardReadinessTests {
    @Test func returningToALoadedBoardReportsReadinessAgain() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        var readyCount = 0
        let styles = BoardPieceStyles(
            one: BoardPieceStyle(color: .boardGameMine, mark: nil, initial: "A", owner: .one),
            two: BoardPieceStyle(color: .boardGamePartner, mark: nil, initial: "R", owner: .two)
        )
        let board = LudoBoardView(
            board: .initial, lastMove: nil, styles: styles, me: .one,
            die: .ready, movableChoices: [], showsOutcome: false,
            bloomSeed: "readiness", partnerName: "Robin", onRoll: { _ in }, onChoose: { _ in },
            onShown: { readyCount += 1 }
        )
        let host = UIHostingController(rootView: board.environment(PaeoniaBannerCenter()))
        let navigation = UINavigationController(rootViewController: host)
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKeyAndVisible()
        }
        let initiallyReady = await waitUntil(timeout: .seconds(30)) { @MainActor in readyCount >= 1 }
        #expect(initiallyReady)
        guard initiallyReady else { return }
        let initialCount = readyCount
        navigation.pushViewController(UIViewController(), animated: false)
        // Allow SwiftUI to cancel the scene's appearance task before returning.
        try await Task.sleep(for: .milliseconds(100))
        navigation.popViewController(animated: false)
        let readyAgain = await waitUntil { @MainActor in readyCount > initialCount }
        #expect(readyAgain)
    }
}
