import Foundation
import LiveCommunicationKit
import Testing
@testable import PaeoniaApp

struct CallPartnerTests {
    private let robin = CallPartner(userID: UUID(), name: "Robin")

    @Test func theSystemShowsThePartnersName() {
        #expect(robin.handle.value == "Robin")
    }

    @Test func aCallBackFromRecentsCallsThePartnerByTheirCurrentName() {
        #expect(robin.answersCallBack(to: robin.handle.value))
    }

    @Test func aCallBackToAnotherNameIsRefused() {
        #expect(!robin.answersCallBack(to: "Paeonia"))
        #expect(!robin.answersCallBack(to: "Sam"))
        #expect(!robin.answersCallBack(to: robin.userID.uuidString.lowercased()))
        #expect(!robin.answersCallBack(to: ""))
    }
}
