import Foundation
import StoreKit
import Testing
@testable import PaeoniaApp

@MainActor
struct PairingInviteCodeTests {
    private let canonicalCode = "01ABCD"

    @Test func normalizationRemovesSeparatorsAndUppercasesCode() throws {
        let rawCode = " 01-ab_cd "

        let normalizedCode = try PairingInviteCode.normalized(rawCode)

        #expect(normalizedCode == canonicalCode)
    }

    @Test func normalizationAcceptsPaeoniaJoinURL() throws {
        let normalizedCode = try PairingInviteCode.normalized(
            "https://paeonia.no/join/01-ab-cd"
        )

        #expect(normalizedCode == canonicalCode)
    }

    @Test func normalizationRejectsWrongLength() {
        #expect(throws: PairingInviteCodeError.invalidLength) {
            try PairingInviteCode.normalized("ABC12")
        }
    }

    @Test func normalizationRejectsInvalidCharacters() {
        #expect(throws: PairingInviteCodeError.invalidCharacters) {
            try PairingInviteCode.normalized("ABC12!")
        }
    }

    @Test func generatedCodeUsesCanonicalShape() throws {
        let code = PairingInviteCode.generate()

        #expect(code.count == PairingInviteCode.length)
        #expect(try PairingInviteCode.normalized(code) == code)
    }

    @Test func joinURLUsesCanonicalPublicDomainAndCodePath() throws {
        let url = try PairingJoinURL.make(inviteCode: canonicalCode.lowercased())

        #expect(url.absoluteString == "https://paeonia.no/join/\(canonicalCode)")
    }

    @Test func joinURLParserAcceptsCanonicalPublicJoinLinks() throws {
        let url = try #require(URL(string: "https://paeonia.no/join/01-ab-cd"))

        #expect(PairingJoinURL.inviteCode(from: url) == canonicalCode)
    }

    @Test func appJoinURLSupportsManualOpenFromWebFallback() throws {
        let url = try PairingJoinURL.makeAppURL(inviteCode: canonicalCode.lowercased())

        #expect(url.absoluteString == "paeonia://join/\(canonicalCode)")
        #expect(PairingJoinURL.inviteCode(from: url) == canonicalCode)
    }

    @Test func joinURLParserRejectsNonJoinLinks() throws {
        let wrongHost = try #require(URL(string: "https://example.com/join/01-ab-cd"))
        let wrongScheme = try #require(URL(string: "http://paeonia.no/join/01-ab-cd"))
        let wrongPath = try #require(URL(string: "https://paeonia.no/invite/01-ab-cd"))
        let extraPath = try #require(URL(string: "https://paeonia.no/join/01-ab-cd/extra"))
        let wrongAppHost = try #require(URL(string: "paeonia://invite/01-ab-cd"))
        let extraAppPath = try #require(URL(string: "paeonia://join/01-ab-cd/extra"))

        #expect(PairingJoinURL.inviteCode(from: wrongHost) == nil)
        #expect(PairingJoinURL.inviteCode(from: wrongScheme) == nil)
        #expect(PairingJoinURL.inviteCode(from: wrongPath) == nil)
        #expect(PairingJoinURL.inviteCode(from: extraPath) == nil)
        #expect(PairingJoinURL.inviteCode(from: wrongAppHost) == nil)
        #expect(PairingJoinURL.inviteCode(from: extraAppPath) == nil)
    }

    @Test func entryTextExtractsTheCodeFromAPastedLink() {
        #expect(PairingInviteCode.entryText("https://paeonia.no/join/01abcd") == canonicalCode)
        #expect(PairingInviteCode.entryText("paeonia://join/01-ab-cd") == canonicalCode)
        #expect(
            PairingInviteCode.entryText("Join me: https://paeonia.no/join/01ABCD.\nSee you!") == canonicalCode
        )
    }

    @Test func joinLinkCodeOnlyAcceptsPaeoniaJoinLinks() {
        #expect(PairingInviteCode.joinLinkCode(in: "https://paeonia.no/join/01abcd") == canonicalCode)
        #expect(PairingInviteCode.joinLinkCode(in: "See https://paeonia.no/join/01-ab-cd!") == canonicalCode)
        #expect(PairingInviteCode.joinLinkCode(in: "https://example.com/join/01ABCD") == nil)
        #expect(PairingInviteCode.joinLinkCode(in: "01ABCD") == nil)
    }

    @Test func entryTextCleansTypedText() {
        #expect(PairingInviteCode.entryText("o1-abcd") == "01ABCD")
        #expect(PairingInviteCode.entryText("lIoU u!") == "110")
        #expect(PairingInviteCode.entryText("0123456789") == "012345")
        #expect(PairingInviteCode.entryText("  ").isEmpty)
        #expect(PairingInviteCode.entryText(PairingInviteCode.entryText("zz zz zz zz")) == "ZZZZZZ")
    }

    @Test func pendingJoinInviteStoreDropsCodesOlderThanSevenDays() throws {
        let suiteName = "PaeoniaAppTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let savedAt = Date(timeIntervalSince1970: 1_000_000)
        var currentDate = savedAt
        let store = UserDefaultsPairingJoinInviteStore(defaults: defaults, now: { currentDate })
        store.saveInviteCode(canonicalCode)

        currentDate = savedAt.addingTimeInterval(UserDefaultsPairingJoinInviteStore.maximumAge)
        #expect(store.loadInviteCode() == canonicalCode)

        currentDate = savedAt.addingTimeInterval(UserDefaultsPairingJoinInviteStore.maximumAge + 1)
        #expect(store.loadInviteCode() == nil)
        #expect(defaults.string(forKey: "paeonia.pairing.pendingJoinInviteCode") == nil)
    }

    @Test func pendingJoinInviteStoreDropsCodesSavedWithoutADate() throws {
        let suiteName = "PaeoniaAppTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(canonicalCode, forKey: "paeonia.pairing.pendingJoinInviteCode")
        let store = UserDefaultsPairingJoinInviteStore(defaults: defaults)

        #expect(store.loadInviteCode() == nil)
        #expect(defaults.string(forKey: "paeonia.pairing.pendingJoinInviteCode") == nil)
    }

    @Test func pendingJoinInviteStorePersistsNormalizedCode() throws {
        let suiteName = "PaeoniaAppTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsPairingJoinInviteStore(defaults: defaults)
        store.saveInviteCode("01-ab-cd")

        #expect(store.loadInviteCode() == canonicalCode)

        store.clearInviteCode()

        #expect(store.loadInviteCode() == nil)
    }

    @MainActor
    @Test func pairingCelebrationStoreClearsOnlyCelebrationKeys() throws {
        let suiteName = "PaeoniaAppTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstPairID = UUID()
        let secondPairID = UUID()
        let unrelatedKey = "paeonia.pairing.unrelated"
        let store = UserDefaultsPairingCelebrationStore(defaults: defaults)
        store.markCelebrationSeen(forPairID: firstPairID)
        store.markCelebrationSeen(forPairID: secondPairID)
        store.saveHomeFirstSteps(HomeFirstStepsProgress(doneSteps: [.memory], isClosed: true), forPairID: firstPairID)
        defaults.set(true, forKey: unrelatedKey)

        store.clearAll()

        #expect(!store.hasSeenCelebration(forPairID: firstPairID))
        #expect(!store.hasSeenCelebration(forPairID: secondPairID))
        #expect(store.homeFirstSteps(forPairID: firstPairID) == HomeFirstStepsProgress())
        #expect(defaults.bool(forKey: unrelatedKey))
    }
}

struct RemotePairingServiceTests {
    private let canonicalCode = "01ABCD"

    @Test func createInviteUsesGeneratedCodeAndReturnsJoinURL() async throws {
        let inviteID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let clientID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let operationID = try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        let operation = PairingClientOperation(
            id: operationID,
            clientID: clientID,
            clientSequence: 7,
            localCreatedAt: Date(timeIntervalSince1970: 10)
        )
        let expiresAt = Date(timeIntervalSince1970: 20)
        let gateway = FakePairingGateway(createdInviteID: inviteID)
        let service = RemotePairingService(
            gateway: gateway,
            generateInviteCode: { "01-ab-cd" }
        )

        let invite = try await service.createInvite(
            operation: operation,
            expiresAt: expiresAt
        )

        #expect(invite.id == inviteID)
        #expect(invite.code == canonicalCode)
        #expect(invite.joinURL.absoluteString == "https://paeonia.no/join/\(canonicalCode)")
        #expect(invite.expiresAt == expiresAt)
        #expect(await gateway.createdInviteCode == canonicalCode)
        #expect(await gateway.createdOperation == operation)
        #expect(await gateway.createdExpiresAt == expiresAt)
    }

    @Test func createInviteRetriesCodeCollisionThreeTimes() async throws {
        let inviteID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let operation = PairingClientOperation(
            clientID: try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222")),
            clientSequence: 7
        )
        let expiresAt = Date(timeIntervalSince1970: 20)
        let gateway = FakePairingGateway(
            createdInviteID: inviteID,
            createFailuresBeforeSuccess: 2
        )
        let generatedCodes = GeneratedInviteCodeSequence(["01ABCD", "02BCDE", "03CDEF"])
        let service = RemotePairingService(
            gateway: gateway,
            generateInviteCode: { generatedCodes.next() }
        )

        let invite = try await service.createInvite(
            operation: operation,
            expiresAt: expiresAt
        )

        #expect(invite.id == inviteID)
        #expect(invite.code == "03CDEF")
        #expect(await gateway.createdInviteCodes == ["01ABCD", "02BCDE", "03CDEF"])
    }

    @Test func createInviteStopsAfterThreeCodeCollisions() async throws {
        let operation = PairingClientOperation(
            clientID: try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222")),
            clientSequence: 7
        )
        let gateway = FakePairingGateway(createFailuresBeforeSuccess: 3)
        let generatedCodes = GeneratedInviteCodeSequence(["01ABCD", "02BCDE", "03CDEF", "04DEFG"])
        let service = RemotePairingService(
            gateway: gateway,
            generateInviteCode: { generatedCodes.next() }
        )

        await #expect(throws: PairingInviteCreationError.inviteCodeCollision) {
            try await service.createInvite(
                operation: operation,
                expiresAt: Date(timeIntervalSince1970: 20)
            )
        }

        #expect(await gateway.createdInviteCodes == ["01ABCD", "02BCDE", "03CDEF"])
    }

    @Test func previewInviteNormalizesPastedJoinURLBeforeCallingGateway() async throws {
        let preview = PairingInvitePreview(
            inviteID: try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111")),
            inviterUserID: try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222")),
            inviterDisplayName: "Alex",
            expiresAt: Date(timeIntervalSince1970: 30),
            hasSafetyWarning: false
        )
        let gateway = FakePairingGateway(preview: preview)
        let service = RemotePairingService(gateway: gateway)

        let result = try await service.previewInvite(
            codeInput: "https://paeonia.no/join/01-ab-cd"
        )

        #expect(result == preview)
        #expect(await gateway.previewedInviteCode == canonicalCode)
    }

    @Test func rotateInviteRetriesCodeCollisionAndReturnsJoinURL() async throws {
        let currentInviteID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let rotatedInviteID = try #require(UUID(uuidString: "44444444-4444-4444-4444-444444444444"))
        let operation = PairingClientOperation(
            clientID: try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222")),
            clientSequence: 7
        )
        let expiresAt = Date(timeIntervalSince1970: 20)
        let currentInvite = PairingInvite(
            id: currentInviteID,
            code: canonicalCode,
            joinURL: try PairingJoinURL.make(inviteCode: canonicalCode),
            expiresAt: Date(timeIntervalSince1970: 10)
        )
        let gateway = FakePairingGateway(
            createFailuresBeforeSuccess: 1,
            rotatedInviteID: rotatedInviteID
        )
        let generatedCodes = GeneratedInviteCodeSequence(["01ABCD", "02BCDE"])
        let service = RemotePairingService(
            gateway: gateway,
            generateInviteCode: { generatedCodes.next() }
        )

        let invite = try await service.rotateInvite(
            currentInvite: currentInvite,
            operation: operation,
            expiresAt: expiresAt
        )

        #expect(invite.id == rotatedInviteID)
        #expect(invite.code == "02BCDE")
        #expect(invite.joinURL.absoluteString == "https://paeonia.no/join/02BCDE")
        #expect(invite.expiresAt == expiresAt)
        #expect(await gateway.rotatedCurrentInviteID == currentInviteID)
        #expect(await gateway.rotatedInviteCodes == ["01ABCD", "02BCDE"])
        #expect(await gateway.rotatedOperation == operation)
        #expect(await gateway.rotatedExpiresAt == expiresAt)
    }

    @Test func acceptInviteNormalizesCodeAndLeavesRelationshipDateUnset() async throws {
        let acceptedCoupleID = try #require(UUID(uuidString: "44444444-4444-4444-4444-444444444444"))
        let clientID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let operation = PairingClientOperation(
            clientID: clientID,
            clientSequence: 8
        )
        let gateway = FakePairingGateway(acceptedCoupleID: acceptedCoupleID)
        let service = RemotePairingService(gateway: gateway)

        let relationship = try await service.acceptInvite(
            codeInput: "https://paeonia.no/join/01-ab-cd",
            operation: operation,
            startedOn: nil
        )

        #expect(relationship.coupleID == acceptedCoupleID)
        #expect(await gateway.acceptedInviteCode == canonicalCode)
        #expect(await gateway.acceptedOperation == operation)
        #expect(await gateway.acceptedStartedOn == nil)
    }
}

struct PairingInviteViewModelTests {
    @MainActor
    @Test func revokedCachedInviteIsClearedBeforeCreatingReplacement() async throws {
        let userID = "11111111-1111-1111-1111-111111111111"
        let currentInvite = try PairingInvite(
            id: #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222")),
            code: "01ABCD",
            joinURL: PairingJoinURL.make(inviteCode: "01ABCD"),
            expiresAt: Date(timeIntervalSince1970: 20)
        )
        let replacementInvite = try PairingInvite(
            id: #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333")),
            code: "02BCDE",
            joinURL: PairingJoinURL.make(inviteCode: "02BCDE"),
            expiresAt: Date(timeIntervalSince1970: 30)
        )
        let pairingService = CachedInviteRecoveryPairingService(
            validation: PairingInviteValidation(
                inviteID: currentInvite.id,
                status: .revoked,
                expiresAt: currentInvite.expiresAt
            ),
            createdInvite: replacementInvite
        )
        let inviteStore = PairingInviteStoreSpy(initialInvite: currentInvite)
        let viewModel = PairingInviteViewModel(
            userID: userID,
            pairingService: pairingService,
            operationProvider: StaticPairingOperationProvider(),
            inviteStore: inviteStore
        )

        await viewModel.loadInviteIfNeeded()

        #expect(await pairingService.validatedInvite == currentInvite)
        #expect(viewModel.invite == replacementInvite)
        #expect(inviteStore.didClearInvite)
        #expect(inviteStore.savedInvite == replacementInvite)
    }

    @MainActor
    @Test func replacingInviteKeepsCurrentInviteUntilNewInviteIsReady() async throws {
        let userID = "11111111-1111-1111-1111-111111111111"
        let currentInvite = try PairingInvite(
            id: #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222")),
            code: "01ABCD",
            joinURL: PairingJoinURL.make(inviteCode: "01ABCD"),
            expiresAt: Date(timeIntervalSince1970: 20)
        )
        let replacementInvite = try PairingInvite(
            id: #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333")),
            code: "02BCDE",
            joinURL: PairingJoinURL.make(inviteCode: "02BCDE"),
            expiresAt: Date(timeIntervalSince1970: 30)
        )
        let pairingService = PendingCreatePairingService(invite: replacementInvite)
        let inviteStore = PairingInviteStoreSpy(initialInvite: currentInvite)
        let viewModel = PairingInviteViewModel(
            userID: userID,
            pairingService: pairingService,
            operationProvider: StaticPairingOperationProvider(),
            inviteStore: inviteStore
        )
        await viewModel.loadInviteIfNeeded()
        #expect(viewModel.invite == currentInvite)

        let task = Task {
            await viewModel.revokeAndCreateNewInvite()
        }
        await pairingService.waitForCreateToStart()

        #expect(viewModel.invite == currentInvite)
        #expect(viewModel.isRevoking)

        await pairingService.finishCreate()
        let createdNewInvite = await task.value

        #expect(createdNewInvite)
        #expect(viewModel.invite == replacementInvite)
        #expect(!viewModel.isRevoking)
        #expect(inviteStore.savedInvite == replacementInvite)
    }
}
