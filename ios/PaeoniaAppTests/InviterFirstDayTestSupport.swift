import Foundation
import PencilKit
import Testing
import UIKit
@testable import PaeoniaApp

/// Records the first day calls and fails the ones a test asks it to.
actor FirstDayGatewaySpy {
    var draft: FirstDayDraft
    private(set) var steps: [String] = []
    private(set) var savedAnswers: [(questionVersionID: UUID, text: String)] = []
    private(set) var startedOnValues: [String?] = []
    private var failingStep: String?
    private var failure: any Error = URLError(.notConnectedToInternet)

    init(draft: FirstDayDraft = firstDayDraft(answered: 0)) {
        self.draft = draft
    }

    func fail(_ step: String, with error: any Error = URLError(.notConnectedToInternet)) {
        failingStep = step
        failure = error
    }

    private func record(_ step: String) throws {
        steps.append(step)
        if step == failingStep {
            throw failure
        }
    }

    func startDraft() throws -> FirstDayDraft {
        try record("start")
        return draft
    }

    func setStartedOn(_ startedOn: String?, operation _: SyncClientOperation) throws {
        try record("startedOn")
        startedOnValues.append(startedOn)
    }

    func saveAnswer(questionVersionID: UUID, text: String, operation _: SyncClientOperation) throws {
        try record("answer")
        savedAnswers.append((questionVersionID, text))
    }

    func reserveDrawingUpload(revisionID _: UUID, operation _: SyncClientOperation) throws -> MediaUploadReservation {
        try record("reserve")
        return MediaUploadReservation(
            mediaAssetID: UUID(),
            bucket: "widget-drawings",
            storagePath: "drafts/test",
            uploadURL: URL(fileURLWithPath: "/")
        )
    }

    func uploadDrawingPayload(reservation _: MediaUploadReservation, data _: Data) throws -> String {
        try record("upload")
        return "storage"
    }

    func finalizeDrawingUpload(_: WidgetDrawingFinalizeInput, operation _: SyncClientOperation) throws {
        try record("finalize")
    }

    func saveDrawing(_: WidgetDrawingUploadPayload, mediaAssetID _: UUID, operation _: SyncClientOperation) throws {
        try record("save")
    }

    func signedDrawingURL(mediaAssetID _: UUID) throws -> URL? {
        try record("signedURL")
        return URL(fileURLWithPath: "/first-day-drawing")
    }
}

extension FirstDayGatewaySpy: FirstDayGateway {}

/// The widget's saved drawing, in memory.
actor FirstDayCanvasFake {
    private(set) var drawingData: Data?

    init(drawingData: Data? = nil) {
        self.drawingData = drawingData
    }

    func loadSavedDrawing() -> Data? {
        drawingData
    }

    func saveDrawing(_ drawingData: Data, canvasSize _: CGSize, authorName _: String?, createdAt _: Date) {
        self.drawingData = drawingData
    }

    func clearForPrivacy() {
        drawingData = nil
    }
}

extension FirstDayCanvasFake: WidgetCanvasManaging {}

/// Records the couple date write a queued first day date turns into.
actor FirstDayRelationshipDatesSpy {
    private(set) var savedStartedOn: PairingStartDate?
    private(set) var savedOwnerUserID: UUID?
    private(set) var savedOperation: SyncClientOperation?
    /// A date the couple already had before the queued one was handled.
    private var existingStartedOn: String?

    func seedExisting(_ startedOn: String) {
        existingStartedOn = startedOn
    }

    func loadStartedOn(ownerUserID _: UUID) -> RelationshipStartedOnLocalState {
        RelationshipStartedOnLocalState(
            startedOn: savedStartedOn?.rawValue ?? existingStartedOn,
            hasPendingChange: savedStartedOn != nil
        )
    }

    func setStartedOn(_ startedOn: PairingStartDate, ownerUserID: UUID, operation: SyncClientOperation) {
        savedStartedOn = startedOn
        savedOwnerUserID = ownerUserID
        savedOperation = operation
    }
}

extension FirstDayRelationshipDatesSpy: RelationshipStartedOnDataServicing {}

// swiftlint:disable async_without_await
nonisolated struct FirstDayPushFake: PushAuthorizationProviding {
    var isUndecided = false
    var denied = false

    func isNotDetermined() async -> Bool { isUndecided }
    func requestAuthorizationIfNeeded() async -> Bool { true }
    func isDenied() async -> Bool { denied }
}

nonisolated struct FirstDayPreferencesFake: NotificationPreferencesProviding {
    var questionTimeEnabled = false

    func loadNotificationPreferences() async throws -> NotificationPreferences {
        var preferences = NotificationPreferences()
        preferences.questionTime.isEnabled = questionTimeEnabled
        return preferences
    }

    func setNotificationPreference(_: NotificationPreferenceKind, enabled _: Bool) async throws {}

    func setQuestionTimeReminder(_: QuestionTimeReminder) async throws {}
}

nonisolated struct FirstDayOperationsFake: WidgetCanvasClientOperationProviding {
    func makeOperation() async -> SyncClientOperation {
        SyncClientOperation(clientID: firstDayUUID(9), clientSequence: 1)
    }
}

// swiftlint:enable async_without_await

nonisolated func firstDayUUID(_ number: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number)) ?? UUID()
}

/// Two questions, the first `answered` of them answered.
nonisolated func firstDayDraft(answered: Int, drawing: FirstDayDrawingReference? = nil) -> FirstDayDraft {
    FirstDayDraft(
        startedOn: nil,
        questions: (1...2).map { slot in
            FirstDayQuestion(
                slotNumber: slot,
                questionVersionID: firstDayUUID(slot),
                promptEN: "Prompt \(slot)",
                promptNB: "Spørsmål \(slot)",
                answerText: slot <= answered ? "Answer \(slot)" : nil
            )
        },
        drawing: drawing
    )
}

func firstDayTestDefaults() throws -> UserDefaults {
    let suite = "InviterFirstDayTests.\(UUID().uuidString)"
    return try #require(UserDefaults(suiteName: suite))
}

func firstDayPayload(_ text: String = "drawing") -> WidgetDrawingUploadPayload {
    WidgetDrawingUploadPayload(
        drawingData: Data(text.utf8),
        canvasSide: 320,
        strokeCount: 1,
        pointCount: 2,
        bounds: CGRect(x: 10, y: 20, width: 30, height: 40)
    )
}
