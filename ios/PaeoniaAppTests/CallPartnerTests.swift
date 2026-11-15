import Foundation
import LiveCommunicationKit
import Testing
@testable import PaeoniaApp

struct CallPartnerTests {
    private let robin = CallPartner(userID: UUID(), name: "Robin")

    @Test func theSystemShowsTheNameTheCallIsFor() {
        #expect(robin.handle(showsName: true).value == "Robin")
        #expect(robin.handle(showsName: false).value == "Paeonia")
    }

    @Test func aCallBackFromRecentsCallsThePartnerByEitherShownName() {
        #expect(robin.answersCallBack(to: robin.handle(showsName: true).value))
        #expect(robin.answersCallBack(to: robin.handle(showsName: false).value))
    }

    @Test func aCallBackToAnotherNameIsRefused() {
        #expect(!robin.answersCallBack(to: "Sam"))
        #expect(!robin.answersCallBack(to: robin.userID.uuidString.lowercased()))
        #expect(!robin.answersCallBack(to: ""))
    }
}
