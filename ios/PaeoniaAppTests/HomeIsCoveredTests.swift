import SwiftUI
import Testing
import UIKit
@testable import PaeoniaApp

/// A card's sheet must reach the Us tab through the visit photo form's host, so the tab does not
/// switch layout while the sheet is open.
@MainActor
struct HomeIsCoveredTests {
    @Observable final class Reported {
        var covered: Bool?
    }

    @Test(arguments: [true, false])
    func aCardsSheetStillCoversTheTabUnderTheVisitPhotoFormHost(cardSheetIsOpen: Bool) async throws {
        let reported = Reported()
        let tab = VStack {
            Text(verbatim: "Story composer").preference(key: HomeIsCoveredKey.self, value: cardSheetIsOpen)
            Text(verbatim: "Photo card")
        }
        .modifier(VisitMemoryFormSheet(form: .constant(nil), memories: nil, viewerID: nil))
        .onPreferenceChange(HomeIsCoveredKey.self) { reported.covered = $0 }
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: tab.environment(PaeoniaBannerCenter()))
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKeyAndVisible()
        }

        #expect(await waitUntil { reported.covered != nil })
        #expect(reported.covered == cardSheetIsOpen)
    }
}
