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
    static let mailComposerDelivery = DeveloperScenario(
        "mail-composer-delivery", "Mail · delivery step",
        "A saved letter set for a time that has passed, while the partner's time zone is unknown", .localFlows
    ) { _ in
        DeveloperLocalFlowHost(seed: .paired, mail: DeveloperMailSeed(
            letters: [], presentation: MailPresentation(path: [.composer], tab: .sent),
            draft: DeveloperMailFixture.pastDraft, deliveryOptions: MailDeliveryOptions()
        ))
    }
    static let mailComposerTogether = DeveloperScenario(
        "mail-composer-together", "Mail · when we next meet",
        "The delivery step for a couple who share location and plan a visit in nine days", .localFlows
    ) { _ in
        DeveloperLocalFlowHost(seed: .paired, mail: DeveloperMailSeed(
            letters: [], presentation: MailPresentation(path: [.composer], tab: .sent),
            draft: DeveloperMailFixture.deliveryDraft(.together),
            deliveryOptions: MailDeliveryOptions(
                partnerTimeZoneID: "Asia/Tokyo",
                nextVisitStartDate: Date.now.addingTimeInterval(9 * 86_400)
                    .formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day()),
                bothShareLocation: true
            )
        ))
    }
    static let mailComposerTogetherUnchecked = DeveloperScenario(
        "mail-composer-together-unchecked", "Mail · meeting not checked",
        "A letter for when you next meet, while the phone could not check how you meet", .localFlows
    ) { _ in
        DeveloperLocalFlowHost(seed: .paired, mail: DeveloperMailSeed(
            letters: [], presentation: MailPresentation(path: [.composer], tab: .sent),
            draft: DeveloperMailFixture.deliveryDraft(.together), deliveryOptions: nil
        ))
    }
    static let mailComposerNoVisit = DeveloperScenario(
        "mail-composer-no-visit", "Mail · no visit planned",
        "The delivery step for a couple with no visit planned who don't share location", .localFlows
    ) { _ in
        DeveloperLocalFlowHost(seed: .paired, mail: DeveloperMailSeed(
            letters: [], presentation: MailPresentation(path: [.composer], tab: .sent),
            draft: DeveloperMailFixture.deliveryDraft(.now),
            deliveryOptions: MailDeliveryOptions(partnerTimeZoneID: "Asia/Tokyo")
        ))
    }
    static let mailComposerVisitTooSoon = DeveloperScenario(
        "mail-composer-visit-too-soon", "Mail · visit too soon",
        "The delivery step when the next visit starts too soon to wait for and location can't tell", .localFlows
    ) { _ in
        DeveloperLocalFlowHost(seed: .paired, mail: DeveloperMailSeed(
            letters: [], presentation: MailPresentation(path: [.composer], tab: .sent),
            draft: DeveloperMailFixture.deliveryDraft(.now),
            deliveryOptions: MailDeliveryOptions(partnerTimeZoneID: "Asia/Tokyo", nextVisitTooSoon: true)
        ))
    }
    static let mailReaderGone = DeveloperScenario(
        "mail-reader-gone", "Mail · letter gone", "A link to a letter its author deleted", .localFlows
    ) { _ in
        DeveloperLocalFlowHost(seed: .paired, mail: .empty(showing: MailPresentation(path: [.reader(UUID())])))
    }
    static let homeMailDraft = DeveloperScenario(
        "home-mail-draft", "Home · letter being written", "The Mail row for a letter not sent yet", .localFlows
    ) { _ in
        DeveloperLocalFlowHost(seed: .paired, mail: DeveloperMailSeed(
            letters: [], presentation: nil, draft: DeveloperMailFixture.unfinishedDraft
        ))
    }
    static let mailSent = DeveloperScenario(
        "mail-sent", "Mail · sent", "The Sent list with a letter on its way and one Robin opened", .localFlows
    ) { _ in DeveloperLocalFlowHost(seed: .paired, mail: .everyKind(showing: MailPresentation(tab: .sent))) }
    static let mailReaderSealedSent = DeveloperScenario(
        "mail-reader-sealed-sent", "Mail · own letter on its way", "A letter you sent that has not arrived yet",
        .localFlows
    ) { _ in
        DeveloperLocalFlowHost(seed: .paired, mail: .everyKind(
            showing: MailPresentation(path: [.reader(DeveloperMailFixture.sealedSentLetterID)], tab: .sent)
        ))
    }
    static let mailComposerBirthday = DeveloperScenario(
        "mail-composer-birthday", "Mail · birthday card",
        "A birthday card at the delivery step, with Robin's birthday saved in Settings", .localFlows
    ) { _ in
        DeveloperLocalFlowHost(seed: .paired, mail: DeveloperMailSeed(
            letters: [], presentation: MailPresentation(path: [.composer], tab: .sent),
            draft: DeveloperMailFixture.birthdayDraft,
            deliveryOptions: MailDeliveryOptions(
                partnerTimeZoneID: "Asia/Tokyo", partnerBirthday: DeveloperMailFixture.birthdaySoon
            )
        ))
    }
    static let mailComposerChange = DeveloperScenario(
        "mail-composer-change", "Mail · change a letter", "Changing a letter you sent that has not arrived yet",
        .localFlows
    ) { _ in
        DeveloperLocalFlowHost(seed: .paired, mail: DeveloperMailSeed(
            letters: DeveloperMailFixture.letters(), presentation: MailPresentation(path: [.composer], tab: .sent),
            draft: DeveloperMailFixture.letters().first { $0.id == DeveloperMailFixture.sealedSentLetterID }
                .flatMap(LetterDraft.init(changing:))
        ))
    }
    static let homeMailWaiting = DeveloperScenario(
        "home-mail-waiting", "Home · letter waiting", "The Mail card with a sealed letter from Robin", .localFlows
    ) { _ in DeveloperLocalFlowHost(seed: .paired, mail: .everyKind(showing: nil)) }
}

/// The letters a local flow starts with, and the Mail screen it opens on.
struct DeveloperMailSeed {
    var letters: [Letter]
    var presentation: MailPresentation?
    var draft: LetterDraft?
    /// Nil when the delivery options can't be read.
    var deliveryOptions: MailDeliveryOptions? = MailDeliveryOptions(partnerTimeZoneID: "Asia/Tokyo")

    static let none = DeveloperMailSeed(letters: [], presentation: nil)

    static func empty(showing presentation: MailPresentation) -> DeveloperMailSeed {
        DeveloperMailSeed(letters: [], presentation: presentation)
    }

    /// A sealed letter waiting, an opened one, and three sent ones: one on its way, one for the
    /// next meeting, and one opened.
    static func everyKind(showing presentation: MailPresentation?) -> DeveloperMailSeed {
        DeveloperMailSeed(letters: DeveloperMailFixture.letters(), presentation: presentation)
    }
}

enum DeveloperMailFixture {
    nonisolated static let waitingLetterID = UUID(uuidString: "8a1d3c5e-0000-4000-8000-000000000001") ?? UUID()
    nonisolated static let openedLetterID = UUID(uuidString: "8a1d3c5e-0000-4000-8000-000000000002") ?? UUID()
    nonisolated static let sealedSentLetterID = UUID(uuidString: "8a1d3c5e-0000-4000-8000-000000000003") ?? UUID()
    nonisolated static let photo = UUID(uuidString: "8a1d3c5e-0000-4000-8000-0000000000aa") ?? UUID()
    static var pastDraft: LetterDraft {
        var content = LetterContent(templateKey: .goodNight, body: "Sleep well. I'm thinking of you.")
        content.delivery = .at(Date.now.addingTimeInterval(-2 * 3_600))
        var draft = LetterDraft(content: content)
        draft.step = .delivery
        draft.deliveryIsChosen = true
        return draft
    }
    static func deliveryDraft(_ delivery: LetterDelivery) -> LetterDraft {
        var content = LetterContent(templateKey: .missYou, body: "I can't wait to hug you at the station.")
        content.delivery = delivery
        var draft = LetterDraft(content: content)
        draft.step = .delivery
        draft.deliveryIsChosen = true
        return draft
    }
    static var birthdayDraft: LetterDraft {
        var draft = LetterDraft(content: LetterContent(
            templateKey: .birthday, body: String(localized: .mailTemplateBirthdayFirstLine)
        ))
        draft.step = .delivery
        return draft
    }
    /// Robin's birthday twelve days from now, in a year long past.
    static var birthdaySoon: String {
        let day = Calendar.current.dateComponents([.month, .day], from: .now.addingTimeInterval(12 * 86_400))
        return String(format: "1998-%02d-%02d", day.month ?? 1, day.day ?? 1)
    }
    static var unfinishedDraft: LetterDraft {
        var draft = LetterDraft(content: LetterContent(templateKey: .missYou, body: "Three more weeks. I"))
        draft.step = .note
        return draft
    }

    static func viewModel(_ seed: DeveloperMailSeed) -> MailViewModel {
        seedPhoto()
        let gateway = DeveloperMailGateway(letters: seed.letters, deliveryOptions: seed.deliveryOptions)
        let model = MailViewModel(
            cache: DeveloperMailCache(snapshot(of: seed.letters), draft: seed.draft),
            gateway: gateway,
            operationProvider: DeveloperScenarioOperationProvider(),
            evictPhotos: { _ in }
        )
        model.presentation = seed.presentation
        return model
    }

    /// The letters as `letters:get_letters` gives them to the current person.
    static func snapshot(of letters: [Letter]) -> MailSnapshot {
        let me = DeveloperScenarioFixture.currentUserID
        let received = letters
            .filter { $0.recipientUserID == me && $0.state != .sealed }
            .map { $0.state == .delivered ? $0.sealedForRecipient : $0 }
            .sorted { MailTimeline.precedes($0, $1, in: .received) }
        let sent = letters.filter { $0.authorUserID == me }.sorted { MailTimeline.precedes($0, $1, in: .sent) }
        return MailSnapshot(
            waiting: MailTimeline.waiting(received, for: me),
            received: MailPage(letters: received),
            sent: MailPage(letters: sent)
        )
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
                id: sealedSentLetterID, authorUserID: me, recipientUserID: partner, templateKey: .goodNight,
                body: "Sleep well. I'm thinking of you.", mediaAssetID: nil, deliveryKind: .morning,
                deliverAt: now.addingTimeInterval(9 * hour), state: .sealed, deliveredAt: nil, openedAt: nil,
                createdAt: now.addingTimeInterval(-2 * hour)
            ),
            Letter(
                id: UUID(), authorUserID: me, recipientUserID: partner, templateKey: .missYou,
                body: "Open this when we're finally together again.", mediaAssetID: nil, deliveryKind: .together,
                deliverAt: nil, state: .sealed, deliveredAt: nil, openedAt: nil,
                createdAt: now.addingTimeInterval(-5 * hour)
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
    /// How the recipient's phone gets a letter it has not opened, as arrived and nothing more.
    var sealedForRecipient: Letter {
        Letter(
            id: id, authorUserID: authorUserID, recipientUserID: recipientUserID, templateKey: nil,
            body: nil, mediaAssetID: nil, deliveryKind: nil, deliverAt: nil, state: state,
            deliveredAt: deliveredAt, openedAt: openedAt, createdAt: nil
        )
    }
}

actor DeveloperMailCache: MailCaching {
    private var value: MailSnapshot
    private var stored: LetterDraft?
    private var photos: [UUID: Data] = [:]
    private(set) var purgeGeneration = 0
    private(set) var draftGeneration = 0

    init(_ value: MailSnapshot, draft: LetterDraft? = nil) {
        self.value = value
        stored = draft
    }

    func snapshot(ownerUserID: UUID) -> MailSnapshot { value }
    func save(_ snapshot: MailSnapshot, ownerUserID: UUID) { value = snapshot }
    func update(
        ownerUserID: UUID, ifGeneration generation: Int, _ change: @Sendable (inout MailSnapshot) -> Void
    ) -> Bool {
        guard generation == purgeGeneration else { return false }
        change(&value)
        return true
    }
    func storedDraft(ownerUserID: UUID) -> StoredLetterDraft {
        let photo = stored?.content.photo.flatMap { photos[$0.id] }
        return StoredLetterDraft(draft: stored, photo: photo, generation: draftGeneration)
    }
    func saveDraft(_ draft: LetterDraft?, ownerUserID: UUID, ifGeneration generation: Int) -> Bool {
        guard generation == draftGeneration else { return false }
        stored = draft
        photos = photos.filter { $0.key == draft?.content.photo?.id }
        return true
    }
    func saveDraftPhoto(_ data: Data, id: UUID, ownerUserID: UUID, ifGeneration generation: Int) -> Bool {
        guard generation == draftGeneration else { return false }
        photos[id] = data
        return true
    }
    func trackPhotos(_ shown: Set<UUID>, ownerUserID: UUID) -> Set<UUID> { [] }
    func clearAll() {
        purgeGeneration += 1
        value = MailSnapshot()
    }
    func clearDrafts() {
        draftGeneration += 1
        stored = nil
        photos = [:]
    }
}

/// Sends, changes, opens and deletes letters in memory. A letter for now arrives at once, and one
/// for later or for the next meeting stays sealed. Without delivery options their read fails.
actor DeveloperMailGateway: MailGateway {
    private var letters: [UUID: Letter]
    private let options: MailDeliveryOptions?

    init(letters: [Letter], deliveryOptions: MailDeliveryOptions?) {
        self.letters = Dictionary(uniqueKeysWithValues: letters.map { ($0.id, $0) })
        options = deliveryOptions
    }

    // Protocol methods replace the network boundary with local results.
    // swiftlint:disable async_without_await
    func send(_ letter: LetterSend, photo: MemoryUploadMedia?, coupleID: UUID) async throws -> Letter? {
        store(letter, photo: photo, createdAt: .now)
    }

    func change(_ letter: LetterSend, photo: MemoryUploadMedia?, coupleID: UUID) async throws -> Letter? {
        guard let old = letters[letter.id] else {
            throw PaeoniaConvexError.server(code: "P0002", message: "letter was deleted")
        }
        guard old.state == .sealed else {
            throw PaeoniaConvexError.server(code: "40001", message: "letter already arrived")
        }
        return store(letter, photo: photo, createdAt: old.createdAt ?? .now)
    }

    private func store(_ letter: LetterSend, photo: MemoryUploadMedia?, createdAt: Date) -> Letter {
        let now = Date()
        let deliverAt: Date? = switch letter.content.delivery {
        case .now: now
        case .morning:
            LetterDelivery.nextMorning(
                after: now, in: TimeZone(identifier: options?.partnerTimeZoneID ?? "UTC") ?? .current
            )
        case let .at(date): date
        case .together: nil
        }
        let arrived = deliverAt.map { $0 <= now } ?? false
        let stored = Letter(
            id: letter.id, authorUserID: DeveloperScenarioFixture.currentUserID,
            recipientUserID: DeveloperScenarioFixture.partnerUserID, templateKey: letter.content.templateKey,
            body: letter.content.trimmedBody,
            mediaAssetID: photo == nil ? letter.content.storedPhotoID : DeveloperMailFixture.photo,
            deliveryKind: letter.content.delivery.kind, deliverAt: deliverAt,
            state: arrived ? .delivered : .sealed, deliveredAt: arrived ? now : nil,
            openedAt: nil, createdAt: createdAt
        )
        letters[stored.id] = stored
        return stored
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

    func olderLetters(in list: MailboxTab, before: LetterCursor, limit: Int) async throws -> MailPage {
        MailPage()
    }

    func deliveryOptions(at now: Date) async throws -> MailDeliveryOptions {
        guard let options else { throw URLError(.badServerResponse) }
        return options
    }
    // swiftlint:enable async_without_await
}
#endif
