import Foundation
import Testing
@testable import PaeoniaApp

struct PaeoniaWidgetDeepLinkTests {
    @Test func drawingURLUsesWidgetDrawingRoute() {
        let url = PaeoniaWidgetDeepLink.drawingURL

        #expect(url.absoluteString == "paeonia://widget/drawing")
        #expect(PaeoniaWidgetDeepLink(url) == .drawing)
        #expect(PaeoniaWidgetDeepLink.handles(url))
    }

    @Test func rejectsNonWidgetURLs() throws {
        let joinURL = try #require(URL(string: "https://paeonia.no/join/01ABCD"))
        let authURL = try #require(URL(string: "paeonia://auth/callback"))
        let widgetRootURL = try #require(URL(string: "paeonia://widget"))

        #expect(!PaeoniaWidgetDeepLink.handles(joinURL))
        #expect(!PaeoniaWidgetDeepLink.handles(authURL))
        #expect(!PaeoniaWidgetDeepLink.handles(widgetRootURL))
    }
}
