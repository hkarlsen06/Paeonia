#if DEBUG
import SwiftUI
import UIKit

nonisolated extension DeveloperScenario {
    static let mailEmpty = DeveloperScenario(
        "mail-empty", "Mail · empty", "The mailbox before the first letter, on the Sent list", .localFlows
    ) { _ in DeveloperLocalFlowHost(seed: .paired, mail: .empty(showing: MailPresentation(tab: .sent))) }
    static let mailMailbox = DeveloperScenario(
        "mail-mailbox", "Mail · mailbox", "Received letters, one sealed and one opened", .localFlows
    ) { _ in DeveloperLocalFlowHost(seed: .paired, mail: .everyKind(showing: MailPresentation())) }
    static let mailComposerTemplates = DeveloperScenario(
        "mail-composer-templates", "Mail · pick a card", "The composer's first step with all eight cards", .localFlows
    ) { _ in
        DeveloperLocalFlowHost(seed: .paired, mail: .empty(showing: MailPresentation(path: [.composer], tab: .sent)))
    }
    static let mailReader = DeveloperScenario(
        "mail-reader", "Mail · reader", "An opened letter from Robin with a note and a photo", .localFlows
    ) { _ in
        DeveloperLocalFlowHost(
            seed: .paired,
            mail: .everyKind(showing: MailPresentation(path: [.reader(DeveloperMailFixture.openedLetterID)]))
        )
    }
    static let homeMailWaiting = DeveloperScenario(
        "home-mail-waiting", "Home · letter waiting", "The Mail card with a sealed letter from Robin", .localFlows
    ) { _ in DeveloperLocalFlowHost(seed: .paired, mail: .everyKind(showing: nil)) }
}

/// The letters a local flow starts with, and the Mail screen it opens on.
struct DeveloperMailSeed {
    var letters: [Letter]
    var presentation: MailPresentation?

    static let none = DeveloperMailSeed(letters: [], presentation: nil)

    static func empty(showing presentation: MailPresentation) -> DeveloperMailSeed {
        DeveloperMailSeed(letters: [], presentation: presentation)
    }

    /// A sealed letter waiting, an opened one, and two sent ones: one on its way and one opened.
    static func everyKind(showing presentation: MailPresentation?) -> DeveloperMailSeed {
        DeveloperMailSeed(letters: DeveloperMailFixture.letters(), presentation: presentation)
    }
}

enum DeveloperMailFixture {
    nonisolated static let waitingLetterID = UUID(uuidString: "8a1d3c5e-0000-4000-8000-000000000001") ?? UUID()
    nonisolated static let openedLetterID = UUID(uuidString: "8a1d3c5e-0000-4000-8000-000000000002") ?? UUID()
    nonisolated static let photo = UUID(uuidString: "8a1d3c5e-0000-4000-8000-0000000000aa") ?? UUID()

    static func viewModel(_ seed: DeveloperMailSeed) -> MailViewModel {
        seedPhoto()
        let gateway = DeveloperMailGateway(letters: seed.letters)
        let shown = seed.letters.map { letter in
            letter.recipientUserID == DeveloperScenarioFixture.currentUserID && letter.state == .delivered
                ? letter.sealedForRecipient : letter
        }
        let model = MailViewModel(
            cache: DeveloperMailCache(MailSnapshot(letters: shown, partnerTimeZoneID: "Asia/Tokyo")),
            gateway: gateway,
            operationProvider: DeveloperScenarioOperationProvider()
        )
        model.presentation = seed.presentation
        return model
    }

    static func letters(now: Date = .now) -> [Letter] {
        let me = DeveloperScenarioFixture.currentUserID
        let partner = DeveloperScenarioFixture.partnerUserID
        let hour: TimeInterval = 3_600
        return [
            Letter(
                id: waitingLetterID, authorUserID: partner, recipientUserID: me, templateKey: .goodMorning,
                body: "Good morning, love. I left a note in your coat pocket too.", mediaAssetID: photo,
                deliveryKind: nil, deliverAt: nil, state: .delivered, deliveredAt: now.addingTimeInterval(-hour),
                openedAt: nil, createdAt: now.addingTimeInterval(-10 * hour)
            ),
            Letter(
                id: UUID(), authorUserID: me, recipientUserID: partner, templateKey: .goodNight,
                body: "Sleep well. I'm thinking of you.", mediaAssetID: nil, deliveryKind: .morning,
                deliverAt: now.addingTimeInterval(9 * hour), state: .sealed, deliveredAt: nil, openedAt: nil,
                createdAt: now.addingTimeInterval(-2 * hour)
            ),
            Letter(
                id: openedLetterID, authorUserID: partner, recipientUserID: me, templateKey: .missYou,
                body: "I miss you. Three more weeks, and then I'm at the station with far too many bags."
                    + "\n\nSave me the window seat at our café.",
                mediaAssetID: photo, deliveryKind: nil, deliverAt: nil, state: .opened,
                deliveredAt: now.addingTimeInterval(-50 * hour), openedAt: now.addingTimeInterval(-49 * hour),
                createdAt: now.addingTimeInterval(-60 * hour)
            ),
            Letter(
                id: UUID(), authorUserID: me, recipientUserID: partner, templateKey: .thankYou,
                body: "Thank you for being you.", mediaAssetID: nil, deliveryKind: .now,
                deliverAt: now.addingTimeInterval(-80 * hour), state: .opened,
                deliveredAt: now.addingTimeInterval(-80 * hour), openedAt: now.addingTimeInterval(-70 * hour),
                createdAt: now.addingTimeInterval(-80 * hour)
            ),
        ]
    }

    private static func seedPhoto() {
        if let url = Bundle.main.url(forResource: "scenario-memory-oslo-opera", withExtension: "jpg"),
           let image = UIImage(contentsOfFile: url.path) {
            MemoryImageDecoding.store(image, for: photo, maxPixelSize: 2_048)
        }
    }
}

nonisolated extension Letter {
    /// How the recipient's phone gets a letter it has not opened: without the note and the photo.
    var sealedForRecipient: Letter {
        Letter(
            id: id, authorUserID: authorUserID, recipientUserID: recipientUserID, templateKey: templateKey,
            body: nil, mediaAssetID: nil, deliveryKind: nil, deliverAt: nil, state: state,
            deliveredAt: deliveredAt, openedAt: openedAt, createdAt: createdAt
        )
    }
}

actor DeveloperMailCache: MailCaching {
    private var value: MailSnapshot
    private var storedDraft: LetterDraft?
    private var storedPhoto: Data?
    private(set) var purgeGeneration = 0

    init(_ value: MailSnapshot) { self.value = value }
    func snapshot(ownerUserID: UUID) -> MailSnapshot { value }
    func save(_ snapshot: MailSnapshot, ownerUserID: UUID) { value = snapshot }
    func update(
        ownerUserID: UUID, ifGeneration generation: Int, _ change: @Sendable (inout MailSnapshot) -> Void
    ) -> Bool {
        guard generation == purgeGeneration else { return false }
        change(&value)
        return true
    }
    func draft(ownerUserID: UUID) -> LetterDraft? { storedDraft }
    func draftPhoto(ownerUserID: UUID) -> Data? { storedPhoto }
    func saveDraft(_ draft: LetterDraft, photo: Data?, ownerUserID: UUID, ifGeneration generation: Int) {
        guard generation == purgeGeneration else { return }
        storedDraft = draft
        storedPhoto = photo
    }
    func clearDraft(ownerUserID: UUID) {
        storedDraft = nil
        storedPhoto = nil
    }
    func clearAll() {
        purgeGeneration += 1
        value = MailSnapshot()
    }
    func clearDrafts() {
        purgeGeneration += 1
        storedDraft = nil
        storedPhoto = nil
    }
}

/// Sends, opens and deletes letters in memory. A letter for now arrives at once, and one for
/// later stays sealed.
actor DeveloperMailGateway: MailGateway {
    private var letters: [UUID: Letter]

    init(letters: [Letter]) {
        self.letters = Dictionary(uniqueKeysWithValues: letters.map { ($0.id, $0) })
    }

    // Protocol methods replace the network boundary with local results.
    // swiftlint:disable async_without_await
    func send(_ letter: LetterSend, photo: MemoryUploadMedia?, coupleID: UUID) async throws -> Letter? {
        let now = Date()
        let deliverAt: Date = switch letter.content.delivery {
        case .now: now
        case .morning: LetterDelivery.nextMorning(after: now, in: TimeZone(identifier: "Asia/Tokyo") ?? .current)
        case let .at(date): date
        }
        let sent = Letter(
            id: letter.id, authorUserID: DeveloperScenarioFixture.currentUserID,
            recipientUserID: DeveloperScenarioFixture.partnerUserID, templateKey: letter.content.templateKey,
            body: letter.content.trimmedBody, mediaAssetID: photo == nil ? nil : DeveloperMailFixture.photo,
            deliveryKind: letter.content.delivery.kind, deliverAt: deliverAt,
            state: deliverAt <= now ? .delivered : .sealed, deliveredAt: deliverAt <= now ? now : nil,
            openedAt: nil, createdAt: now
        )
        letters[sent.id] = sent
        return sent
    }

    func open(id: UUID) async throws -> Letter {
        guard var letter = letters[id] else { throw URLError(.fileDoesNotExist) }
        letter.state = .opened
        letter.openedAt = letter.openedAt ?? .now
        letters[id] = letter
        return letter
    }

    func delete(id: UUID, operation: SyncClientOperation) async throws {
        letters[id] = nil
    }
    // swiftlint:enable async_without_await
}
#endif
