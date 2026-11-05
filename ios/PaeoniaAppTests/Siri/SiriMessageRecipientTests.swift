import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct SiriMessageRecipientTests {
    private let owner = UUID()
    private let partner = UUID()

    @Test func acceptsThePartnerAsASingleRecipientOrAList() throws {
        let couple = couple
        let person = ChatPersonEntity(id: partner, name: "Alvilde", isMe: false)
        try SiriChats.validateRecipient(.messagePerson(person), couple: couple)
        try SiriChats.validateRecipient(.messagePeople([person]), couple: couple)
    }

    @Test func refusesAnotherPersonEvenWithTheSameDisplayName() {
        let person = ChatPersonEntity(id: UUID(), name: "Alvilde", isMe: false)
        #expect(throws: SiriFailure.self) {
            try SiriChats.validateRecipient(.messagePerson(person), couple: couple)
        }
        #expect(throws: SiriFailure.self) {
            try SiriChats.validateRecipient(.messagePeople([person]), couple: couple)
        }
    }

    @Test func refusesAnEmptyListOrAListContainingSomeoneElse() {
        let person = ChatPersonEntity(id: partner, name: "Alvilde", isMe: false)
        let other = ChatPersonEntity(id: UUID(), name: "Someone else", isMe: false)
        #expect(throws: SiriFailure.self) {
            try SiriChats.validateRecipient(.messagePeople([]), couple: couple)
        }
        #expect(throws: SiriFailure.self) {
            try SiriChats.validateRecipient(.messagePeople([person, other]), couple: couple)
        }
    }

    private var couple: SiriCouple {
        SiriCouple(ownerUserID: owner, coupleID: UUID(), partnerUserID: partner, partnerName: "Alvilde")
    }
}
