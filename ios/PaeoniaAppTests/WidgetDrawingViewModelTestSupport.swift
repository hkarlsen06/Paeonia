import PencilKit
@testable import PaeoniaApp

// The widget canvas test doubles mirror async protocols, so their synchronous
// bodies do not await. This matches the project's other test doubles.
// swiftlint:disable async_without_await

func makeNonEmptyDrawing(seed: CGFloat = 12) -> PKDrawing {
    let point = PKStrokePoint(
        location: CGPoint(x: seed, y: seed),
        timeOffset: 0,
        size: CGSize(width: 4, height: 4),
        opacity: 1,
        force: 1,
        azimuth: 0,
        altitude: 0
    )
    let path = PKStrokePath(controlPoints: [point], creationDate: Date())
    let stroke = PKStroke(ink: PKInk(.pen, color: .black), path: path)
    return PKDrawing(strokes: [stroke])
}

enum WidgetDrawingTestError: Error {
    case failed
}

final class WidgetCanvasServiceSpy: WidgetCanvasManaging, @unchecked Sendable {
    private(set) var saveCount = 0
    private(set) var loadCount = 0
    private(set) var clearCount = 0
    private(set) var lastSavedData: Data?
    private(set) var lastCanvasSize: CGSize?
    private(set) var lastAuthorName: String?
    var saveError: Error?
    var savedDrawingData: Data?
    var savedAuthorName: String?
    var savedCreatedAt: Date?

    func loadSavedDrawing() async -> Data? {
        savedDrawingData
    }

    func loadSavedSnapshot() async -> WidgetCanvasSnapshot? {
        loadCount += 1
        guard let savedDrawingData else {
            return nil
        }
        return WidgetCanvasSnapshot(
            drawingData: savedDrawingData,
            authorName: savedAuthorName,
            createdAt: savedCreatedAt
        )
    }

    func saveDrawing(
        _ drawingData: Data,
        canvasSize: CGSize,
        authorName: String?,
        createdAt: Date
    ) async throws {
        saveCount += 1
        lastSavedData = drawingData
        lastCanvasSize = canvasSize
        lastAuthorName = authorName
        if let saveError {
            throw saveError
        }
    }

    func clearForPrivacy() async {
        clearCount += 1
    }
}

final class WidgetCanvasUploadSpy: WidgetCanvasUploading, @unchecked Sendable {
    private(set) var enqueued: [WidgetDrawingUploadPayload] = []
    private(set) var events: [String] = []
    var outcome: WidgetDrawingDelivery = .delivered
    var pendingUpload = false

    var hasPendingUpload: Bool {
        pendingUpload
    }

    func markPending(_: WidgetDrawingUploadPayload) -> WidgetPendingUploadSnapshot? {
        events.append("markPending")
        return nil
    }

    func send(_ payload: WidgetDrawingUploadPayload) -> WidgetDrawingDelivery {
        events.append("send")
        enqueued.append(payload)
        return outcome
    }

    func uploadPending(_ payload: WidgetDrawingUploadPayload) async throws {
        enqueued.append(payload)
    }
}

actor SuspendedWidgetCanvasService: WidgetCanvasManaging {
    private var shouldSuspendNextSave = false
    private var suspendedSaveStarted = false
    private var suspendedSaveStartedContinuation: CheckedContinuation<Void, Never>?
    private var suspendedSaveReleaseContinuation: CheckedContinuation<Void, Never>?

    func suspendNextSave() {
        shouldSuspendNextSave = true
        suspendedSaveStarted = false
    }

    func waitForSuspendedSaveToStart() async {
        if suspendedSaveStarted {
            return
        }

        await withCheckedContinuation { continuation in
            suspendedSaveStartedContinuation = continuation
        }
    }

    func releaseSuspendedSave() {
        suspendedSaveReleaseContinuation?.resume()
        suspendedSaveReleaseContinuation = nil
    }

    func loadSavedDrawing() async -> Data? {
        nil
    }

    func loadSavedSnapshot() async -> WidgetCanvasSnapshot? {
        nil
    }

    func saveDrawing(
        _: Data,
        canvasSize _: CGSize,
        authorName _: String?,
        createdAt _: Date
    ) async throws {
        guard shouldSuspendNextSave else {
            return
        }

        shouldSuspendNextSave = false
        suspendedSaveStarted = true
        suspendedSaveStartedContinuation?.resume()
        suspendedSaveStartedContinuation = nil

        await withCheckedContinuation { continuation in
            suspendedSaveReleaseContinuation = continuation
        }
    }

    func clearForPrivacy() async {}
}

/// The couple every draft test runs in, unless a test says otherwise.
let draftTestCoupleID = UUID()

func draftKey(_ ownerUserID: UUID, coupleID: UUID = draftTestCoupleID) -> WidgetDrawingDraftKey {
    WidgetDrawingDraftKey(ownerUserID: ownerUserID, coupleID: coupleID)
}

@MainActor
final class InMemoryWidgetDrawingDraftStore: WidgetDrawingDraftStoring {
    private var drafts: [WidgetDrawingDraftKey: Data] = [:]
    private var purgeGenerations: [UUID: Int] = [:]

    func draft(for key: WidgetDrawingDraftKey) -> Data? {
        drafts[key]
    }

    func setDraft(_ data: Data, for key: WidgetDrawingDraftKey) {
        drafts[key] = data
    }

    func removeDraft(for key: WidgetDrawingDraftKey) {
        drafts[key] = nil
    }

    func clearDraft(for ownerUserID: UUID) {
        purgeGenerations[ownerUserID, default: 0] += 1
        drafts = drafts.filter { $0.key.ownerUserID != ownerUserID }
    }

    func purgeGeneration(for ownerUserID: UUID) -> Int {
        purgeGenerations[ownerUserID, default: 0]
    }

    private var bases: [WidgetDrawingDraftKey: String] = [:]

    func draftBase(for key: WidgetDrawingDraftKey) -> String? {
        drafts[key] == nil ? nil : bases[key]
    }

    func setDraftBase(_ fingerprint: String, for key: WidgetDrawingDraftKey) {
        bases[key] = fingerprint
    }
}

// swiftlint:enable async_without_await
