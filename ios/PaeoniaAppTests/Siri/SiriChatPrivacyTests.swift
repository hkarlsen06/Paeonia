import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct SiriChatPrivacyTests {
    @Test(arguments: [nil, false, true] as [Bool?])
    func questionChatsRequireKnownPublicPrivacy(_ privacy: Bool?) {
        #expect(SiriChats.canExpose(summary(subject: .question(UUID()), privacy: privacy)) == (privacy == false))
    }

    @Test func ordinaryCoupleChatsDoNotRequireTopicMetadata() {
        #expect(SiriChats.canExpose(summary(subject: .couple, privacy: nil)))
    }

    private func summary(subject: ThreadChatSubject, privacy: Bool?) -> ThreadChatSummary {
        ThreadChatSummary(
            threadID: UUID(), coupleID: UUID(), subject: subject,
            createdAt: .now, updatedAt: .now, lastMessageID: nil,
            lastMessageAt: nil, lastMessageSenderUserID: nil, lastMessageBody: nil,
            isPrivateTopic: privacy)
    }
}
