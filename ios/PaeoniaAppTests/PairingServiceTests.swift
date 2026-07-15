import Foundation
import StoreKit
import Testing
@testable import PaeoniaApp

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
        defaults.set(true, forKey: unrelatedKey)

        store.clearAll()

        #expect(!store.hasSeenCelebration(forPairID: firstPairID))
        #expect(!store.hasSeenCelebration(forPairID: secondPairID))
        #expect(defaults.bool(forKey: unrelatedKey))
    }
}

struct SupabasePairingServiceTests {
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
        let gateway = FakeSupabasePairingGateway(createdInviteID: inviteID)
        let service = SupabasePairingService(
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
        let gateway = FakeSupabasePairingGateway(
            createdInviteID: inviteID,
            createFailuresBeforeSuccess: 2
        )
        let generatedCodes = GeneratedInviteCodeSequence(["01ABCD", "02BCDE", "03CDEF"])
        let service = SupabasePairingService(
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
        let gateway = FakeSupabasePairingGateway(createFailuresBeforeSuccess: 3)
        let generatedCodes = GeneratedInviteCodeSequence(["01ABCD", "02BCDE", "03CDEF", "04DEFG"])
        let service = SupabasePairingService(
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
        let gateway = FakeSupabasePairingGateway(preview: preview)
        let service = SupabasePairingService(gateway: gateway)

        let result = try await service.previewInvite(
            codeInput: "https://paeonia.no/join/01-ab-cd"
        )

        #expect(result == preview)
        #expect(await gateway.previewedInviteCode == canonicalCode)
    }

    @Test func validateInviteNormalizesCachedCodeBeforeCallingGateway() async throws {
        let inviteID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let validation = PairingInviteValidation(
            inviteID: inviteID,
            status: .pending,
            expiresAt: Date(timeIntervalSince1970: 30)
        )
        let gateway = FakeSupabasePairingGateway(validation: validation)
        let service = SupabasePairingService(gateway: gateway)
        let invite = PairingInvite(
            id: inviteID,
            code: "01-ab-cd",
            joinURL: try PairingJoinURL.make(inviteCode: canonicalCode),
            expiresAt: Date(timeIntervalSince1970: 20)
        )

        let result = try await service.validateInvite(invite)

        #expect(result == validation)
        #expect(await gateway.validatedInviteID == inviteID)
        #expect(await gateway.validatedInviteCode == canonicalCode)
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
        let gateway = FakeSupabasePairingGateway(
            createFailuresBeforeSuccess: 1,
            rotatedInviteID: rotatedInviteID
        )
        let generatedCodes = GeneratedInviteCodeSequence(["01ABCD", "02BCDE"])
        let service = SupabasePairingService(
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
        let gateway = FakeSupabasePairingGateway(acceptedCoupleID: acceptedCoupleID)
        let service = SupabasePairingService(gateway: gateway)

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

    @Test func leaveRelationshipForwardsOperationToGateway() async throws {
        let clientID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let operation = PairingClientOperation(
            clientID: clientID,
            clientSequence: 12
        )
        let gateway = FakeSupabasePairingGateway(leaveResult: true)
        let service = SupabasePairingService(gateway: gateway)

        let didLeave = try await service.leaveRelationship(operation: operation)

        #expect(didLeave)
        #expect(await gateway.leftOperation == operation)
    }
}

struct PaywallInviteAcceptanceTests {
    @MainActor
    @Test func previewMustSucceedBeforeAcceptingInviteWithoutInventingStartDate() async throws {
        let operation = PairingClientOperation(
            id: try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333")),
            clientID: try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222")),
            clientSequence: 9,
            localCreatedAt: Date(timeIntervalSince1970: 40)
        )
        let preview = PairingInvitePreview(
            inviteID: try #require(UUID(uuidString: "44444444-4444-4444-4444-444444444444")),
            inviterUserID: try #require(UUID(uuidString: "55555555-5555-5555-5555-555555555555")),
            inviterDisplayName: "Alex",
            expiresAt: Date(timeIntervalSince1970: 100),
            hasSafetyWarning: false
        )
        let pairingService = PaywallPairingServiceSpy(preview: preview)
        let viewModel = PaywallViewModel(
            userID: "11111111-1111-1111-1111-111111111111",
            storeKitService: PaywallStoreKitServiceSpy(),
            pairingService: pairingService,
            operationProvider: StaticPairingOperationProvider(operation: operation)
        )

        let loadedPreview = await viewModel.previewInvite(codeInput: "01-ab-cd")

        #expect(loadedPreview == preview)
        #expect(viewModel.invitePreview == preview)
        #expect(await pairingService.previewedCodeInput == "01ABCD")
        #expect(await pairingService.acceptCallCount == 0)

        let accepted = await viewModel.acceptPreviewedInvite()

        #expect(accepted)
        #expect(viewModel.error == nil)
        #expect(viewModel.invitePreview == nil)
        #expect(await pairingService.acceptedCodeInput == "01ABCD")
        #expect(await pairingService.acceptedOperation == operation)
        #expect(await pairingService.acceptedStartedOn == nil)
    }

    @MainActor
    @Test func invalidInviteCodeDoesNotCallPreviewOrAccept() async {
        let pairingService = PaywallPairingServiceSpy()
        let viewModel = PaywallViewModel(
            userID: "11111111-1111-1111-1111-111111111111",
            storeKitService: PaywallStoreKitServiceSpy(),
            pairingService: pairingService,
            operationProvider: StaticPairingOperationProvider()
        )

        let preview = await viewModel.previewInvite(codeInput: "ABC12")

        #expect(preview == nil)
        #expect(viewModel.error == .inviteInvalid)
        #expect(await pairingService.previewCallCount == 0)
        #expect(await pairingService.acceptCallCount == 0)
    }

    @MainActor
    @Test func unavailableInviteExplainsInvalidOrExpiredCodeAndCannotBeAccepted() async {
        let pairingService = PaywallPairingServiceSpy(preview: nil)
        let viewModel = PaywallViewModel(
            userID: "11111111-1111-1111-1111-111111111111",
            storeKitService: PaywallStoreKitServiceSpy(),
            pairingService: pairingService,
            operationProvider: StaticPairingOperationProvider()
        )

        let preview = await viewModel.previewInvite(codeInput: "01ABCD")
        let accepted = await viewModel.acceptPreviewedInvite()

        #expect(preview == nil)
        #expect(!accepted)
        #expect(viewModel.error == .inviteUnavailable)
        #expect(await pairingService.previewCallCount == 1)
        #expect(await pairingService.acceptCallCount == 0)
        #expect(
            PaywallError.inviteUnavailable.message
                == String(localized: .paywallErrorInviteUnavailable)
        )
    }

    @MainActor
    @Test func previewRetainsPriorSafetyWarningForConfirmation() async throws {
        let warningPreview = PairingInvitePreview(
            inviteID: try #require(UUID(uuidString: "44444444-4444-4444-4444-444444444444")),
            inviterUserID: try #require(UUID(uuidString: "55555555-5555-5555-5555-555555555555")),
            inviterDisplayName: "Alex",
            expiresAt: Date(timeIntervalSince1970: 100),
            hasSafetyWarning: true
        )
        let viewModel = PaywallViewModel(
            userID: "11111111-1111-1111-1111-111111111111",
            storeKitService: PaywallStoreKitServiceSpy(),
            pairingService: PaywallPairingServiceSpy(preview: warningPreview),
            operationProvider: StaticPairingOperationProvider()
        )

        _ = await viewModel.previewInvite(codeInput: "01ABCD")

        #expect(viewModel.invitePreview?.hasSafetyWarning == true)
    }
}

struct PaywallUnpairTests {
    @MainActor
    @Test func leavingRelationshipUsesOperationAndSucceeds() async throws {
        let operation = PairingClientOperation(
            id: try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333")),
            clientID: try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222")),
            clientSequence: 11,
            localCreatedAt: Date(timeIntervalSince1970: 50)
        )
        let pairingService = PaywallPairingServiceSpy()
        let viewModel = PaywallViewModel(
            userID: "11111111-1111-1111-1111-111111111111",
            storeKitService: PaywallStoreKitServiceSpy(),
            pairingService: pairingService,
            operationProvider: StaticPairingOperationProvider(operation: operation)
        )

        let didLeave = await viewModel.leaveRelationship()

        #expect(didLeave)
        #expect(viewModel.error == nil)
        #expect(!viewModel.isLeavingRelationship)
        #expect(await pairingService.leftOperation == operation)
    }

    @MainActor
    @Test func failedLeaveSurfacesUnpairErrorAndStopsWorking() async {
        let pairingService = PaywallPairingServiceSpy(leaveShouldFail: true)
        let viewModel = PaywallViewModel(
            userID: "11111111-1111-1111-1111-111111111111",
            storeKitService: PaywallStoreKitServiceSpy(),
            pairingService: pairingService,
            operationProvider: StaticPairingOperationProvider()
        )

        let didLeave = await viewModel.leaveRelationship()

        #expect(!didLeave)
        #expect(viewModel.error == .unpairFailed)
        #expect(!viewModel.isLeavingRelationship)
        #expect(await pairingService.leaveCallCount == 1)
    }
}

struct PaywallStoreKitLoadingTests {
    @MainActor
    @Test func configuredTrialIsHiddenForAnIneligiblePriorSubscriber() async {
        let configuredTrial = PaeoniaFreeTrial(value: 14, unit: .day)
        let storeKitService = OfferPaywallStoreKitService(
            configuredTrial: configuredTrial,
            isEligible: false
        )
        let viewModel = PaywallViewModel(
            userID: "11111111-1111-1111-1111-111111111111",
            storeKitService: storeKitService,
            pairingService: PaywallPairingServiceSpy(),
            operationProvider: StaticPairingOperationProvider()
        )

        await viewModel.loadProducts()

        #expect(viewModel.isPresentationReady)
        #expect(viewModel.currentFreeTrial == nil)
        #expect(storeKitService.eligibilityChecks == Set(PaeoniaSubscriptionProductID.allCases))
    }

    @MainActor
    @Test func configuredTrialIsShownForAnEligibleSubscriber() async {
        let configuredTrial = PaeoniaFreeTrial(value: 14, unit: .day)
        let storeKitService = OfferPaywallStoreKitService(
            configuredTrial: configuredTrial,
            isEligible: true
        )
        let viewModel = PaywallViewModel(
            userID: "11111111-1111-1111-1111-111111111111",
            storeKitService: storeKitService,
            pairingService: PaywallPairingServiceSpy(),
            operationProvider: StaticPairingOperationProvider()
        )

        await viewModel.loadProducts()

        #expect(viewModel.isPresentationReady)
        #expect(viewModel.currentFreeTrial == configuredTrial)
    }

    @MainActor
    @Test func paywallPresentationWaitsForStoreKitProductsAndEligibilityToSettle() async {
        let storeKitService = BlockingPaywallStoreKitService()
        let viewModel = PaywallViewModel(
            userID: "11111111-1111-1111-1111-111111111111",
            storeKitService: storeKitService,
            pairingService: PaywallPairingServiceSpy(),
            operationProvider: StaticPairingOperationProvider()
        )

        #expect(!viewModel.isPresentationReady)

        let loadTask = Task { @MainActor in
            await viewModel.loadProducts()
        }
        await storeKitService.waitForLoadToStart()

        #expect(viewModel.isLoading)
        #expect(!viewModel.isPresentationReady)

        storeKitService.finishLoad()
        await storeKitService.waitForEligibilityToStart()

        #expect(viewModel.isLoading)
        #expect(!viewModel.isPresentationReady)

        storeKitService.finishEligibility()
        await loadTask.value

        #expect(!viewModel.isLoading)
        #expect(viewModel.isPresentationReady)
        #expect(viewModel.error == .productsUnavailable)

        viewModel.clearError()
        #expect(viewModel.isPresentationReady)
    }

    @MainActor
    @Test func eligibilityRefreshKeepsTheLastStableOfferUntilTheNewResultSettles() async {
        let configuredTrial = PaeoniaFreeTrial(value: 14, unit: .day)
        let storeKitService = RefreshingOfferPaywallStoreKitService(
            initialTrial: configuredTrial
        )
        let viewModel = PaywallViewModel(
            userID: "11111111-1111-1111-1111-111111111111",
            storeKitService: storeKitService,
            pairingService: PaywallPairingServiceSpy(),
            operationProvider: StaticPairingOperationProvider()
        )

        await viewModel.loadProducts()
        #expect(viewModel.isPresentationReady)
        #expect(viewModel.currentFreeTrial == configuredTrial)

        storeKitService.beginBlockingRefresh(returning: nil)
        let refreshTask = Task { @MainActor in
            await viewModel.loadProducts()
        }
        await storeKitService.waitForRefreshEligibilityToStart()

        #expect(viewModel.isLoading)
        #expect(viewModel.isPresentationReady)
        #expect(viewModel.currentFreeTrial == configuredTrial)

        storeKitService.finishRefreshEligibility()
        await refreshTask.value

        #expect(!viewModel.isLoading)
        #expect(viewModel.isPresentationReady)
        #expect(viewModel.currentFreeTrial == nil)
    }
}

struct PairingInviteViewModelTests {
    @MainActor
    @Test func initialInviteCreationKeepsPresentationUnreadyUntilInviteIsStable() async throws {
        let userID = "11111111-1111-1111-1111-111111111111"
        let invite = try PairingInvite(
            id: #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222")),
            code: "01ABCD",
            joinURL: PairingJoinURL.make(inviteCode: "01ABCD"),
            expiresAt: Date(timeIntervalSince1970: 20)
        )
        let pairingService = PendingCreatePairingService(invite: invite)
        let viewModel = PairingInviteViewModel(
            userID: userID,
            pairingService: pairingService,
            operationProvider: StaticPairingOperationProvider(),
            inviteStore: PairingInviteStoreSpy(initialInvite: nil)
        )

        #expect(!viewModel.isPresentationReady)

        let task = Task {
            await viewModel.loadInviteIfNeeded()
        }
        await pairingService.waitForCreateToStart()

        #expect(viewModel.isLoading)
        #expect(!viewModel.isPresentationReady)

        await pairingService.finishCreate()
        await task.value

        #expect(!viewModel.isLoading)
        #expect(viewModel.invite == invite)
        #expect(viewModel.isPresentationReady)
    }

    @MainActor
    @Test func cachedInviteValidationKeepsPresentationUnreadyUntilServerConfirms() async throws {
        let userID = "11111111-1111-1111-1111-111111111111"
        let currentInvite = try PairingInvite(
            id: #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222")),
            code: "01ABCD",
            joinURL: PairingJoinURL.make(inviteCode: "01ABCD"),
            expiresAt: Date(timeIntervalSince1970: 20)
        )
        let pairingService = BlockingValidationPairingService(invite: currentInvite)
        let viewModel = PairingInviteViewModel(
            userID: userID,
            pairingService: pairingService,
            operationProvider: StaticPairingOperationProvider(),
            inviteStore: PairingInviteStoreSpy(initialInvite: currentInvite)
        )

        let task = Task {
            await viewModel.loadInviteIfNeeded()
        }
        await pairingService.waitForValidationToStart()

        #expect(viewModel.invite == nil)
        #expect(viewModel.isLoading)
        #expect(!viewModel.isPresentationReady)

        await pairingService.finishValidation()
        await task.value

        #expect(viewModel.invite == currentInvite)
        #expect(!viewModel.isLoading)
        #expect(viewModel.isPresentationReady)
    }

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

    @MainActor
    @Test func failedInviteReplacementKeepsCurrentInviteVisible() async throws {
        let userID = "11111111-1111-1111-1111-111111111111"
        let currentInvite = try PairingInvite(
            id: #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222")),
            code: "01ABCD",
            joinURL: PairingJoinURL.make(inviteCode: "01ABCD"),
            expiresAt: Date(timeIntervalSince1970: 20)
        )
        let pairingService = FailingCreatePairingService()
        let inviteStore = PairingInviteStoreSpy(initialInvite: currentInvite)
        let viewModel = PairingInviteViewModel(
            userID: userID,
            pairingService: pairingService,
            operationProvider: StaticPairingOperationProvider(),
            inviteStore: inviteStore
        )
        await viewModel.loadInviteIfNeeded()
        #expect(viewModel.invite == currentInvite)

        let createdNewInvite = await viewModel.revokeAndCreateNewInvite()

        #expect(!createdNewInvite)
        #expect(viewModel.invite == currentInvite)
        #expect(viewModel.error == nil)
        #expect(!inviteStore.didClearInvite)
    }
}

struct PaywallAudienceTests {
    @Test func unpairedAudienceAllowsInviteEntryAndIsNotPaired() {
        let audience = PaywallAudience.unpaired

        #expect(audience.allowsInviteEntry)
        #expect(!audience.isPaired)
    }

    @Test func pairedAudienceHidesInviteEntryAndIsPaired() {
        let audience = PaywallAudience.paired(partnerName: "Riley")

        #expect(!audience.allowsInviteEntry)
        #expect(audience.isPaired)
        #expect(audience.partnerNameForCopy == "Riley")
    }

    @Test func pairedAudienceFallsBackWhenPartnerNameMissingOrBlank() {
        let fallback = String(localized: .paywallPairedPartnerFallback)

        #expect(PaywallAudience.paired(partnerName: nil).partnerNameForCopy == fallback)
        #expect(PaywallAudience.paired(partnerName: "   ").partnerNameForCopy == fallback)
    }

    @Test func unpairedAudienceUsesTrialCopyOnlyWhenTrialIsAvailable() {
        let audience = PaywallAudience.unpaired

        #expect(
            String(localized: audience.headlineTitle(hasFreeTrial: true))
                == String(localized: .paywallTrialTitle)
        )
        #expect(
            String(localized: audience.subtitle(hasFreeTrial: true))
                == String(localized: .paywallTrialSubtitle)
        )
        #expect(
            String(localized: audience.headlineTitle(hasFreeTrial: false))
                == String(localized: .paywallTitle)
        )
        #expect(
            String(localized: audience.subtitle(hasFreeTrial: false))
                == String(localized: .paywallSubtitle)
        )
    }

    @Test func pairedAudienceUsesPartnerNameAndTrialSpecificSubtitle() {
        let audience = PaywallAudience.paired(partnerName: "  Riley  ")

        #expect(
            String(localized: audience.headlineTitle(hasFreeTrial: true))
                == String(localized: .paywallPairedTitle("Riley"))
        )
        #expect(
            String(localized: audience.subtitle(hasFreeTrial: true))
                == String(localized: .paywallPairedTrialSubtitle)
        )
        #expect(
            String(localized: audience.subtitle(hasFreeTrial: false))
                == String(localized: .paywallPairedSubtitle)
        )
    }
}

struct PaywallErrorTests {
    @Test func purchaseConfirmationErrorMessageHidesTechnicalDiagnostics() {
        let message = PaywallError.purchaseNotConfirmed.message

        #expect(message == String(localized: .paywallErrorPurchaseNotConfirmed))
        #expect(!message.contains("StoreKit"))
        #expect(!message.contains("appAccountToken"))
    }

    @Test func linkedAccountErrorMessageHidesAppAccountToken() {
        let message = PaywallError.purchaseLinkedToAnotherAccount.message

        #expect(message == String(localized: .paywallErrorPurchaseLinkedToAnotherAccount))
        #expect(!message.contains("StoreKit"))
        #expect(!message.contains("appAccountToken"))
    }
}

// swiftlint:disable async_without_await
private actor FakeSupabasePairingGateway: SupabasePairingGateway {
    private let createdInviteID: UUID
    private var createFailuresBeforeSuccess: Int
    private let preview: PairingInvitePreview?
    private let validation: PairingInviteValidation
    private let acceptedCoupleID: UUID
    private let rotatedInviteID: UUID
    private let leaveResult: Bool
    private(set) var createdInviteCode: String?
    private(set) var createdInviteCodes: [String] = []
    private(set) var createdOperation: PairingClientOperation?
    private(set) var createdExpiresAt: Date?
    private(set) var validatedInviteID: UUID?
    private(set) var validatedInviteCode: String?
    private(set) var previewedInviteCode: String?
    private(set) var rotatedCurrentInviteID: UUID?
    private(set) var rotatedInviteCode: String?
    private(set) var rotatedInviteCodes: [String] = []
    private(set) var rotatedOperation: PairingClientOperation?
    private(set) var rotatedExpiresAt: Date?
    private(set) var acceptedInviteCode: String?
    private(set) var acceptedOperation: PairingClientOperation?
    private(set) var acceptedStartedOn: PairingStartDate?
    private(set) var leftOperation: PairingClientOperation?

    init(
        createdInviteID: UUID = UUID(),
        createFailuresBeforeSuccess: Int = 0,
        preview: PairingInvitePreview? = nil,
        validation: PairingInviteValidation = PairingInviteValidation(
            inviteID: nil,
            status: .notFound,
            expiresAt: nil
        ),
        acceptedCoupleID: UUID = UUID(),
        rotatedInviteID: UUID = UUID(),
        leaveResult: Bool = true
    ) {
        self.createdInviteID = createdInviteID
        self.createFailuresBeforeSuccess = createFailuresBeforeSuccess
        self.preview = preview
        self.validation = validation
        self.acceptedCoupleID = acceptedCoupleID
        self.rotatedInviteID = rotatedInviteID
        self.leaveResult = leaveResult
    }

    func createInvite(
        inviteCode: String,
        operation: PairingClientOperation,
        expiresAt: Date
    ) async throws -> UUID {
        createdInviteCode = inviteCode
        createdInviteCodes.append(inviteCode)
        createdOperation = operation
        createdExpiresAt = expiresAt

        if createFailuresBeforeSuccess > 0 {
            createFailuresBeforeSuccess -= 1
            throw PairingInviteCreationError.inviteCodeCollision
        }

        return createdInviteID
    }

    func validateInvite(inviteID: UUID, inviteCode: String) async throws -> PairingInviteValidation {
        validatedInviteID = inviteID
        validatedInviteCode = inviteCode
        return validation
    }

    func previewInvite(inviteCode: String) async throws -> PairingInvitePreview? {
        previewedInviteCode = inviteCode
        return preview
    }

    func rotateInvite(
        currentInviteID: UUID,
        inviteCode: String,
        operation: PairingClientOperation,
        expiresAt: Date
    ) async throws -> UUID {
        rotatedCurrentInviteID = currentInviteID
        rotatedInviteCode = inviteCode
        rotatedInviteCodes.append(inviteCode)
        rotatedOperation = operation
        rotatedExpiresAt = expiresAt

        if createFailuresBeforeSuccess > 0 {
            createFailuresBeforeSuccess -= 1
            throw PairingInviteCreationError.inviteCodeCollision
        }

        return rotatedInviteID
    }

    func acceptInvite(
        inviteCode: String,
        operation: PairingClientOperation,
        startedOn: PairingStartDate?
    ) async throws -> UUID {
        acceptedInviteCode = inviteCode
        acceptedOperation = operation
        acceptedStartedOn = startedOn
        return acceptedCoupleID
    }

    func revokeInvite(id: UUID) async throws -> Bool {
        true
    }

    func leaveRelationship(operation: PairingClientOperation) async throws -> Bool {
        leftOperation = operation
        return leaveResult
    }
}
// swiftlint:enable async_without_await

private final class GeneratedInviteCodeSequence: @unchecked Sendable {
    private var codes: [String]
    private var index = 0

    init(_ codes: [String]) {
        self.codes = codes
    }

    func next() -> String {
        defer { index += 1 }
        return codes[index]
    }
}

// swiftlint:disable async_without_await
@MainActor
private final class PaywallStoreKitServiceSpy: PaeoniaStoreKitServicing {
    var products: [Product] { [] }

    func configure(userID: String) {}
    func loadProducts() async throws {}
    func product(for productID: PaeoniaSubscriptionProductID) -> Product? { nil }
    func product(for productID: PaeoniaConsumableProductID) -> Product? { nil }
    func purchase(_ product: Product) async throws -> Bool { false }
    func restorePurchases() async throws -> Bool { false }
    func redeemStreakRestore() async throws -> Int? { nil }
    func recoverPendingStreakRestores() async -> Int? { nil }
}

@MainActor
private final class BlockingPaywallStoreKitService: PaeoniaStoreKitServicing {
    var products: [Product] { [] }

    private var loadContinuation: CheckedContinuation<Void, any Error>?
    private var loadStartedContinuation: CheckedContinuation<Void, Never>?
    private var eligibilityContinuation: CheckedContinuation<PaeoniaFreeTrial?, Never>?
    private var eligibilityStartedContinuation: CheckedContinuation<Void, Never>?
    private var eligibilityCallCount = 0

    func configure(userID: String) {}

    func loadProducts() async throws {
        try await withCheckedThrowingContinuation { continuation in
            loadContinuation = continuation
            loadStartedContinuation?.resume()
            loadStartedContinuation = nil
        }
    }

    func waitForLoadToStart() async {
        if loadContinuation != nil {
            return
        }

        await withCheckedContinuation { continuation in
            loadStartedContinuation = continuation
        }
    }

    func finishLoad() {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    func eligibleFreeTrial(for productID: PaeoniaSubscriptionProductID) async -> PaeoniaFreeTrial? {
        eligibilityCallCount += 1
        if eligibilityCallCount > 1 {
            return nil
        }

        return await withCheckedContinuation { continuation in
            eligibilityContinuation = continuation
            eligibilityStartedContinuation?.resume()
            eligibilityStartedContinuation = nil
        }
    }

    func waitForEligibilityToStart() async {
        if eligibilityContinuation != nil {
            return
        }

        await withCheckedContinuation { continuation in
            eligibilityStartedContinuation = continuation
        }
    }

    func finishEligibility() {
        eligibilityContinuation?.resume(returning: nil)
        eligibilityContinuation = nil
    }

    func product(for productID: PaeoniaSubscriptionProductID) -> Product? { nil }
    func product(for productID: PaeoniaConsumableProductID) -> Product? { nil }
    func purchase(_ product: Product) async throws -> Bool { false }
    func restorePurchases() async throws -> Bool { false }
    func redeemStreakRestore() async throws -> Int? { nil }
    func recoverPendingStreakRestores() async -> Int? { nil }
}

@MainActor
private final class OfferPaywallStoreKitService: PaeoniaStoreKitServicing {
    var products: [Product] { [] }
    private let configuredTrial: PaeoniaFreeTrial
    private let isEligible: Bool
    private(set) var eligibilityChecks = Set<PaeoniaSubscriptionProductID>()

    init(configuredTrial: PaeoniaFreeTrial, isEligible: Bool) {
        self.configuredTrial = configuredTrial
        self.isEligible = isEligible
    }

    func configure(userID: String) {}
    func loadProducts() async throws {}

    func eligibleFreeTrial(for productID: PaeoniaSubscriptionProductID) async -> PaeoniaFreeTrial? {
        eligibilityChecks.insert(productID)
        return PaeoniaStoreKitOfferEligibility.freeTrial(
            configuredOffer: configuredTrial,
            isEligible: isEligible
        )
    }

    func product(for productID: PaeoniaSubscriptionProductID) -> Product? { nil }
    func product(for productID: PaeoniaConsumableProductID) -> Product? { nil }
    func purchase(_ product: Product) async throws -> Bool { false }
    func restorePurchases() async throws -> Bool { false }
    func redeemStreakRestore() async throws -> Int? { nil }
    func recoverPendingStreakRestores() async -> Int? { nil }
}

@MainActor
private final class RefreshingOfferPaywallStoreKitService: PaeoniaStoreKitServicing {
    var products: [Product] { [] }

    private var monthlyTrial: PaeoniaFreeTrial?
    private var shouldBlockMonthlyEligibility = false
    private var refreshEligibilityContinuation: CheckedContinuation<Void, Never>?
    private var refreshEligibilityStartedContinuation: CheckedContinuation<Void, Never>?

    init(initialTrial: PaeoniaFreeTrial?) {
        monthlyTrial = initialTrial
    }

    func configure(userID: String) {}
    func loadProducts() async throws {}

    func eligibleFreeTrial(for productID: PaeoniaSubscriptionProductID) async -> PaeoniaFreeTrial? {
        guard productID == .coupleMonthly else {
            return nil
        }

        if shouldBlockMonthlyEligibility {
            await withCheckedContinuation { continuation in
                refreshEligibilityContinuation = continuation
                refreshEligibilityStartedContinuation?.resume()
                refreshEligibilityStartedContinuation = nil
            }
            shouldBlockMonthlyEligibility = false
        }

        return monthlyTrial
    }

    func beginBlockingRefresh(returning trial: PaeoniaFreeTrial?) {
        monthlyTrial = trial
        shouldBlockMonthlyEligibility = true
    }

    func waitForRefreshEligibilityToStart() async {
        if refreshEligibilityContinuation != nil {
            return
        }

        await withCheckedContinuation { continuation in
            refreshEligibilityStartedContinuation = continuation
        }
    }

    func finishRefreshEligibility() {
        refreshEligibilityContinuation?.resume()
        refreshEligibilityContinuation = nil
    }

    func product(for productID: PaeoniaSubscriptionProductID) -> Product? { nil }
    func product(for productID: PaeoniaConsumableProductID) -> Product? { nil }
    func purchase(_ product: Product) async throws -> Bool { false }
    func restorePurchases() async throws -> Bool { false }
    func redeemStreakRestore() async throws -> Int? { nil }
    func recoverPendingStreakRestores() async -> Int? { nil }
}

@MainActor
private final class StaticPairingOperationProvider: PairingClientOperationProviding {
    private let operation: PairingClientOperation
    private(set) var makeOperationCallCount = 0

    init(
        operation: PairingClientOperation = PairingClientOperation(
            clientID: UUID(),
            clientSequence: 1
        )
    ) {
        self.operation = operation
    }

    func makeOperation() -> PairingClientOperation {
        makeOperationCallCount += 1
        return operation
    }
}

private actor PaywallPairingServiceSpy: PairingServicing {
    private(set) var previewCallCount = 0
    private(set) var previewedCodeInput: String?
    private(set) var acceptCallCount = 0
    private(set) var acceptedCodeInput: String?
    private(set) var acceptedOperation: PairingClientOperation?
    private(set) var acceptedStartedOn: PairingStartDate?
    private(set) var leaveCallCount = 0
    private(set) var leftOperation: PairingClientOperation?
    private let leaveShouldFail: Bool
    private let preview: PairingInvitePreview?

    init(
        leaveShouldFail: Bool = false,
        preview: PairingInvitePreview? = nil
    ) {
        self.leaveShouldFail = leaveShouldFail
        self.preview = preview
    }

    func createInvite(
        operation: PairingClientOperation,
        expiresAt: Date
    ) async throws -> PairingInvite {
        PairingInvite(
            id: UUID(),
            code: "01ABCD",
            joinURL: try PairingJoinURL.make(inviteCode: "01ABCD"),
            expiresAt: expiresAt
        )
    }

    func validateInvite(_ invite: PairingInvite) async throws -> PairingInviteValidation {
        PairingInviteValidation(
            inviteID: invite.id,
            status: .pending,
            expiresAt: invite.expiresAt
        )
    }

    func previewInvite(codeInput: String) async throws -> PairingInvitePreview? {
        previewCallCount += 1
        previewedCodeInput = codeInput
        return preview
    }

    func rotateInvite(
        currentInvite: PairingInvite,
        operation: PairingClientOperation,
        expiresAt: Date
    ) async throws -> PairingInvite {
        PairingInvite(
            id: UUID(),
            code: "02BCDE",
            joinURL: try PairingJoinURL.make(inviteCode: "02BCDE"),
            expiresAt: expiresAt
        )
    }

    func acceptInvite(
        codeInput: String,
        operation: PairingClientOperation,
        startedOn: PairingStartDate?
    ) async throws -> PairingAcceptedRelationship {
        acceptCallCount += 1
        acceptedCodeInput = codeInput
        acceptedOperation = operation
        acceptedStartedOn = startedOn
        return PairingAcceptedRelationship(coupleID: UUID())
    }

    func revokeInvite(id: UUID) async throws -> Bool {
        return true
    }

    func leaveRelationship(operation: PairingClientOperation) async throws -> Bool {
        leaveCallCount += 1
        leftOperation = operation
        if leaveShouldFail {
            throw PairingInviteCreationError.inviteCodeCollision
        }
        return true
    }
}
// swiftlint:enable async_without_await

@MainActor
private final class PairingInviteStoreSpy: PairingInviteStoring {
    private let initialInvite: PairingInvite?
    private(set) var savedInvite: PairingInvite?
    private(set) var didClearInvite = false

    init(initialInvite: PairingInvite?) {
        self.initialInvite = initialInvite
    }

    func loadInvite(for userID: String) -> PairingInvite? {
        return initialInvite
    }

    func saveInvite(_ invite: PairingInvite, for userID: String) {
        savedInvite = invite
    }

    func clearInvite(for userID: String) {
        didClearInvite = true
    }
}

private actor BlockingValidationPairingService: PairingServicing {
    private let invite: PairingInvite
    private var validationContinuation: CheckedContinuation<PairingInviteValidation, any Error>?
    private var validationStartedContinuation: CheckedContinuation<Void, Never>?

    init(invite: PairingInvite) {
        self.invite = invite
    }

    func createInvite(
        operation: PairingClientOperation,
        expiresAt: Date
    ) async throws -> PairingInvite {
        fatalError("unused")
    }

    func validateInvite(_ invite: PairingInvite) async throws -> PairingInviteValidation {
        return try await withCheckedThrowingContinuation { continuation in
            validationContinuation = continuation
            validationStartedContinuation?.resume()
            validationStartedContinuation = nil
        }
    }

    func waitForValidationToStart() async {
        if validationContinuation != nil {
            return
        }

        await withCheckedContinuation { continuation in
            validationStartedContinuation = continuation
        }
    }

    func finishValidation() {
        validationContinuation?.resume(
            returning: PairingInviteValidation(
                inviteID: invite.id,
                status: .pending,
                expiresAt: invite.expiresAt
            )
        )
        validationContinuation = nil
    }

    func previewInvite(codeInput: String) async throws -> PairingInvitePreview? {
        fatalError("unused")
    }

    func rotateInvite(
        currentInvite: PairingInvite,
        operation: PairingClientOperation,
        expiresAt: Date
    ) async throws -> PairingInvite {
        fatalError("unused")
    }

    func acceptInvite(
        codeInput: String,
        operation: PairingClientOperation,
        startedOn: PairingStartDate?
    ) async throws -> PairingAcceptedRelationship {
        fatalError("unused")
    }

    func revokeInvite(id: UUID) async throws -> Bool {
        fatalError("unused")
    }

    func leaveRelationship(operation: PairingClientOperation) async throws -> Bool {
        fatalError("unused")
    }
}

private actor CachedInviteRecoveryPairingService: PairingServicing {
    private let validation: PairingInviteValidation
    private let createdInvite: PairingInvite
    private(set) var validatedInvite: PairingInvite?

    init(validation: PairingInviteValidation, createdInvite: PairingInvite) {
        self.validation = validation
        self.createdInvite = createdInvite
    }

    func createInvite(
        operation: PairingClientOperation,
        expiresAt: Date
    ) async throws -> PairingInvite {
        createdInvite
    }

    func validateInvite(_ invite: PairingInvite) async throws -> PairingInviteValidation {
        validatedInvite = invite
        return validation
    }

    func previewInvite(codeInput: String) async throws -> PairingInvitePreview? {
        fatalError("unused")
    }

    func rotateInvite(
        currentInvite: PairingInvite,
        operation: PairingClientOperation,
        expiresAt: Date
    ) async throws -> PairingInvite {
        fatalError("unused")
    }

    func acceptInvite(
        codeInput: String,
        operation: PairingClientOperation,
        startedOn: PairingStartDate?
    ) async throws -> PairingAcceptedRelationship {
        fatalError("unused")
    }

    func revokeInvite(id: UUID) async throws -> Bool {
        fatalError("unused")
    }

    func leaveRelationship(operation: PairingClientOperation) async throws -> Bool {
        fatalError("unused")
    }
}

private actor PendingCreatePairingService: PairingServicing {
    private let invite: PairingInvite
    private var createContinuation: CheckedContinuation<PairingInvite, any Error>?
    private var createStartedContinuation: CheckedContinuation<Void, Never>?

    init(invite: PairingInvite) {
        self.invite = invite
    }

    func createInvite(
        operation: PairingClientOperation,
        expiresAt: Date
    ) async throws -> PairingInvite {
        return try await withCheckedThrowingContinuation { continuation in
            createContinuation = continuation
            createStartedContinuation?.resume()
            createStartedContinuation = nil
        }
    }

    func validateInvite(_ invite: PairingInvite) async throws -> PairingInviteValidation {
        PairingInviteValidation(
            inviteID: invite.id,
            status: .pending,
            expiresAt: invite.expiresAt
        )
    }

    func waitForCreateToStart() async {
        if createContinuation != nil {
            return
        }

        await withCheckedContinuation { continuation in
            createStartedContinuation = continuation
        }
    }

    func finishCreate() {
        createContinuation?.resume(returning: invite)
        createContinuation = nil
    }

    func previewInvite(codeInput: String) async throws -> PairingInvitePreview? {
        await Task.yield()
        return nil
    }

    func rotateInvite(
        currentInvite: PairingInvite,
        operation: PairingClientOperation,
        expiresAt: Date
    ) async throws -> PairingInvite {
        return try await withCheckedThrowingContinuation { continuation in
            createContinuation = continuation
            createStartedContinuation?.resume()
            createStartedContinuation = nil
        }
    }

    func acceptInvite(
        codeInput: String,
        operation: PairingClientOperation,
        startedOn: PairingStartDate?
    ) async throws -> PairingAcceptedRelationship {
        await Task.yield()
        return PairingAcceptedRelationship(coupleID: UUID())
    }

    func revokeInvite(id: UUID) async throws -> Bool {
        await Task.yield()
        return true
    }

    func leaveRelationship(operation: PairingClientOperation) async throws -> Bool {
        await Task.yield()
        return true
    }
}

private actor FailingCreatePairingService: PairingServicing {
    func createInvite(
        operation: PairingClientOperation,
        expiresAt: Date
    ) async throws -> PairingInvite {
        await Task.yield()
        throw PairingInviteCreationError.inviteCodeCollision
    }

    func validateInvite(_ invite: PairingInvite) async throws -> PairingInviteValidation {
        PairingInviteValidation(
            inviteID: invite.id,
            status: .pending,
            expiresAt: invite.expiresAt
        )
    }

    func previewInvite(codeInput: String) async throws -> PairingInvitePreview? {
        await Task.yield()
        return nil
    }

    func rotateInvite(
        currentInvite: PairingInvite,
        operation: PairingClientOperation,
        expiresAt: Date
    ) async throws -> PairingInvite {
        await Task.yield()
        throw PairingInviteCreationError.inviteCodeCollision
    }

    func acceptInvite(
        codeInput: String,
        operation: PairingClientOperation,
        startedOn: PairingStartDate?
    ) async throws -> PairingAcceptedRelationship {
        await Task.yield()
        return PairingAcceptedRelationship(coupleID: UUID())
    }

    func revokeInvite(id: UUID) async throws -> Bool {
        await Task.yield()
        return true
    }

    func leaveRelationship(operation: PairingClientOperation) async throws -> Bool {
        await Task.yield()
        return true
    }
} // swiftlint:disable:this file_length
