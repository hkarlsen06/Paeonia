import Observation
import UIKit

/// A screen of the signed-out flow.
enum WelcomeStep: Equatable {
    /// What Paeonia is, and the three ways in.
    case welcome
    /// When the couple got together. Only on the start path.
    case startDate
    /// The first drawing for the partner's Home Screen. Only on the start path.
    case drawing
    case signIn(WelcomeSignInMode)
}

/// Why the person is signing in, which picks the sign-in step's headline.
enum WelcomeSignInMode: Equatable {
    /// Starting a couple. `hasDrawing` when a first drawing waits to be sent.
    case start(hasDrawing: Bool)
    /// A partner's invite code is saved.
    case joining
    case returning
}

/// Runs the signed-out flow. The person who starts the couple picks the start date
/// and makes the first drawing before an account exists, so signing in saves
/// something they made.
///
/// The start date waits in `store` until there is a session (`sessionStarted`), then
/// goes into the pending sync operations. A sent drawing waits in the welcome flow's own
/// canvas and "not sent yet" marker (`WelcomeDrawingStorage`), which another account's
/// data on this phone never mixes with. Once there is a session, and another account's
/// data has been cleared, `sessionStarted` moves it to the widget's canvas and marks it
/// as the first-day drawing that waits, and the invite screen sends it
/// (`InviterFirstDayModel.load`). Strokes not sent yet are a draft under a made-up ID
/// from `store`, so they survive Back and a relaunch, and go away at sign-in.
///
/// A doodle on the welcome widget comes along on the start path. It waits in `store`
/// until the drawing screen has loaded, which adds it to the draft one stroke at a time,
/// so undo takes it off like strokes drawn there. Choosing to join or to sign in to an
/// existing account drops it with the first drawing.
@MainActor
@Observable
final class WelcomeFlowModel {
    private(set) var step: WelcomeStep

    @ObservationIgnored private let store: any WelcomeFlowStoring
    @ObservationIgnored private let funnel: any WelcomeFunnelRecording
    /// The first drawing's canvas and marker before sign-in.
    @ObservationIgnored private let canvas: any WidgetCanvasManaging
    @ObservationIgnored private let pendingUploads: WidgetPendingUploadStore
    /// The widget's canvas and marker, where the first drawing goes at sign-in.
    @ObservationIgnored private let widgetCanvas: any WidgetCanvasManaging
    @ObservationIgnored private let widgetPendingUploads: WidgetPendingUploadStore
    @ObservationIgnored private let rasterizer: any WidgetDrawingRasterizing
    @ObservationIgnored private let startDateQueue: FirstDayStartedOnQueue
    @ObservationIgnored private let drawingDrafts: any WidgetDrawingDraftStoring
    /// The drawing screen's view model, kept while the flow runs so Back and Continue
    /// return to the same canvas.
    @ObservationIgnored private var drawingScreen: WidgetDrawingViewModel?

    init(
        store: any WelcomeFlowStoring = UserDefaultsWelcomeFlowStore(),
        funnel: any WelcomeFunnelRecording = WelcomeFunnelRecorder.shared,
        canvas: any WidgetCanvasManaging = WelcomeDrawingStorage.canvas,
        pendingUploads: WidgetPendingUploadStore = WelcomeDrawingStorage.pendingUploads,
        widgetCanvas: any WidgetCanvasManaging = WidgetCanvasService.shared,
        widgetPendingUploads: WidgetPendingUploadStore = .shared,
        rasterizer: any WidgetDrawingRasterizing = WidgetDrawingRasterizer(),
        startDateQueue: FirstDayStartedOnQueue = FirstDayStartedOnQueue(),
        drawingDrafts: any WidgetDrawingDraftStoring = FileWidgetDrawingDraftStore.shared
    ) {
        self.store = store
        self.funnel = funnel
        self.canvas = canvas
        self.pendingUploads = pendingUploads
        self.widgetCanvas = widgetCanvas
        self.widgetPendingUploads = widgetPendingUploads
        self.rasterizer = rasterizer
        self.startDateQueue = startDateQueue
        self.drawingDrafts = drawingDrafts
        // Someone who signed in on this phone before gets sign-in for returning. A saved
        // invite code moves on to sign-in for joining (`inviteCodeSaved`).
        step = store.hasSignedInBefore ? .signIn(.returning) : .welcome
    }

    // MARK: Welcome

    func welcomeAppeared() {
        funnel.record(.welcomeShown)
    }

    /// `doodle` is what the person drew on the welcome widget, if anything. It goes on
    /// top of a doodle still waiting from an earlier visit.
    func chooseStart(carrying doodle: WelcomeCarriedDoodle?) {
        funnel.record(.startChosen)
        PaeoniaHaptics.selection()
        if let doodle {
            store.carriedDoodle = store.carriedDoodle?.adding(doodle) ?? doodle
        }
        step = .startDate
    }

    /// The invited choice was tapped. The code sheet or the paste button follows.
    func chooseJoining() {
        funnel.record(.joinerChosen)
    }

    func chooseReturning() {
        funnel.record(.returningChosen)
        store.startDate = nil
        forgetDrawing()
        step = .signIn(.returning)
    }

    /// A partner's code was saved, from the welcome step, the sign-in step or a link.
    func inviteCodeSaved() {
        store.startDate = nil
        forgetDrawing()
        step = .signIn(.joining)
    }

    // MARK: Start date

    func saveStartDate(_ date: Date) {
        store.startDate = PairingStartDate(date: date)
        funnel.record(.dateSaved)
    }

    func skipStartDate() {
        store.startDate = nil
        funnel.record(.dateSkipped)
        finishStartDate()
    }

    /// The days count landed, or the date was skipped.
    func finishStartDate() {
        step = .drawing
    }

    // MARK: Drawing

    /// The real drawing screen's view model, the same one each time the step shows.
    /// There is no account, couple or partner yet, so it draws without the live relay,
    /// and keeps its draft under `store.drawingDraftID`. The view model reads that ID
    /// only for the draft key and the purge count. A waiting welcome doodle goes on
    /// its canvas once it has loaded.
    func drawingViewModel() -> WidgetDrawingViewModel {
        let viewModel = drawingScreen ?? makeDrawingViewModel()
        if let doodle = store.carriedDoodle {
            viewModel.addStrokesOnceLoaded(doodle.drawing, side: doodle.canvasSide) { [weak self] in
                self?.store.carriedDoodle = nil
            }
        }
        return viewModel
    }

    private func makeDrawingViewModel() -> WidgetDrawingViewModel {
        let draftID = store.drawingDraftID ?? UUID()
        store.drawingDraftID = draftID
        let viewModel = WidgetDrawingViewModel(
            ownerUserID: draftID,
            coupleID: draftID,
            authorName: nil,
            service: canvas,
            uploader: WelcomeDrawingUploader(pendingStore: pendingUploads),
            draftStore: drawingDrafts,
            live: nil
        )
        drawingScreen = viewModel
        return viewModel
    }

    func drawingSent() {
        funnel.record(.drawingSent)
    }

    func skipDrawing() {
        funnel.record(.drawingSkipped)
        finishDrawing()
    }

    func finishDrawing() {
        step = .signIn(.start(hasDrawing: drawingWaitsForAccount))
    }

    /// A first drawing sent on the drawing step waits for an account.
    private var drawingWaitsForAccount: Bool {
        pendingUploads.pendingSnapshot?.isFirstDay == true
    }

    /// After sign-in: the first drawing made before it has not reached the server yet.
    /// The invite screen sends it.
    var hasWaitingDrawing: Bool {
        widgetPendingUploads.pendingSnapshot?.isFirstDay == true
    }

    /// The waiting first drawing as the widget shows it, for the sign-in step. Nil when
    /// no first drawing waits or it no longer decodes.
    func waitingDrawingImage() async -> UIImage? {
        guard drawingWaitsForAccount, let snapshot = await canvas.loadSavedSnapshot() else {
            return nil
        }
        return await rasterizer.renderPNG(
            fromDrawingData: snapshot.drawingData,
            canvasSide: snapshot.canvasSide ?? WidgetDrawingViewModel.fallbackCanvasSide,
            pixelWidth: 900
        )
        .flatMap(UIImage.init(data:))
    }

    // MARK: Sign-in

    /// The previous step. Leaving joining forgets the saved code, through `onForgetInviteCode`.
    func back(onForgetInviteCode: () -> Void) {
        switch step {
        case .welcome:
            return
        case .startDate:
            step = .welcome
        case .drawing:
            step = .startDate
        case .signIn(.start):
            step = .drawing
        case .signIn(.joining):
            onForgetInviteCode()
            step = .welcome
        case .signIn(.returning):
            step = .welcome
        }
    }

    func signInAppeared() {
        funnel.record(.signInShown)
    }

    /// A sign-in went through.
    func signedIn() {
        funnel.record(.signedIn)
    }

    /// A session is about to be used, after a sign-in or at launch, and after another
    /// account's data was cleared from the phone. Hands a start date picked before
    /// sign-in to the pending sync operations, which send it to the first day draft, or
    /// to the couple when the partner joined first. Moves a sent first drawing to the
    /// widget's canvas, marked as the first-day drawing that waits.
    ///
    /// Also removes the unsent welcome drawing, which no screen can reach once someone
    /// is signed in.
    func sessionStarted(ownerUserID: String) async {
        store.hasSignedInBefore = true
        await handOverSentDrawing()
        forgetUnsentDrawing()
        guard let startDate = store.startDate, let ownerUserID = UUID(uuidString: ownerUserID) else {
            return
        }
        do {
            try await startDateQueue.save(startDate, ownerUserID: ownerUserID)
            store.startDate = nil
        } catch {
            // Stays saved, and goes in on the next session start.
        }
    }

    /// The account was deleted, so the next person starts at welcome.
    func accountDeleted() {
        store.hasSignedInBefore = false
    }

    /// The session ended, just before the signed-out flow shows again: sign-in for
    /// returning after a sign-out, welcome after an account deletion. A start date or
    /// first drawing that could not be handed to that account is dropped, so it never
    /// reaches whoever signs in next.
    func sessionEnded() {
        store.startDate = nil
        forgetDrawing()
        step = store.hasSignedInBefore ? .signIn(.returning) : .welcome
    }

    /// Puts the sent first drawing on the widget's canvas with the first-day marker, so
    /// the invite screen sends it for this account. Kept for the next session start if
    /// the widget's canvas cannot save it.
    private func handOverSentDrawing() async {
        guard let pending = pendingUploads.pendingSnapshot else {
            return
        }
        guard pending.isFirstDay,
              let snapshot = await canvas.loadSavedSnapshot(),
              WidgetCanvasUploadService.sha256Hex(of: snapshot.drawingData) == pending.contentHash
        else {
            // The marker describes a drawing that is no longer saved.
            await clearSentDrawing()
            return
        }
        let side = snapshot.canvasSide ?? CGFloat(pending.canvasSide)
        do {
            try await widgetCanvas.saveDrawing(
                snapshot.drawingData,
                canvasSize: CGSize(width: side, height: side),
                authorName: snapshot.authorName,
                createdAt: snapshot.createdAt ?? pending.markedAt
            )
        } catch {
            return
        }
        widgetPendingUploads.markPending(
            pending.uploadPayload(with: snapshot.drawingData),
            contentHash: pending.contentHash,
            isFirstDay: true
        )
        await clearSentDrawing()
    }

    private func clearSentDrawing() async {
        pendingUploads.clearAll()
        await canvas.clearForPrivacy()
    }

    /// Drops the first drawing, sent or not, and a welcome doodle still waiting.
    private func forgetDrawing() {
        forgetUnsentDrawing()
        pendingUploads.clearAll()
        Task { [canvas] in
            await canvas.clearForPrivacy()
        }
    }

    /// Clearing by owner also stops an open drawing screen from writing the draft back.
    private func forgetUnsentDrawing() {
        store.carriedDoodle = nil
        guard let draftID = store.drawingDraftID else {
            return
        }
        drawingDrafts.clearDraft(for: draftID)
        store.drawingDraftID = nil
        drawingScreen = nil
    }
}
