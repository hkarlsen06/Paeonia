import Observation
import UIKit

/// A screen of the signed-out flow.
enum WelcomeStep: Equatable {
    /// What Paeonia is, and the three ways in.
    case welcome
    /// When the couple got together. Only on the start path.
    case startDate
    /// The first drawing for the partner's Home Screen. Only on the start path, and
    /// only when the phone holds no other account's data.
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
/// goes into the pending sync operations. A sent drawing needs no carryover of its own:
/// the canvas service saves it on the phone, `WelcomeDrawingUploader` marks it as the
/// first-day drawing that waits, and the invite screen sends it after sign-in
/// (`InviterFirstDayModel.load`). Strokes not sent yet are a draft under a made-up ID
/// from `store`, so they survive Back and a relaunch, and go away at sign-in.
///
/// A doodle on the welcome widget comes along on the start path. It waits in `store`
/// until the drawing screen has loaded, which adds it to the draft one stroke at a time,
/// so undo takes it off like strokes drawn there. Every other way out of welcome drops
/// it, and so does a phone that skips the drawing step.
@MainActor
@Observable
final class WelcomeFlowModel {
    private(set) var step: WelcomeStep

    @ObservationIgnored private let store: any WelcomeFlowStoring
    @ObservationIgnored private let funnel: any WelcomeFunnelRecording
    @ObservationIgnored private let canvas: any WidgetCanvasManaging
    @ObservationIgnored private let rasterizer: any WidgetDrawingRasterizing
    @ObservationIgnored private let pendingUploads: WidgetPendingUploadStore
    @ObservationIgnored private let startDateQueue: FirstDayStartedOnQueue
    @ObservationIgnored private let drawingDrafts: any WidgetDrawingDraftStoring
    /// The drawing screen's view model, kept while the flow runs so Back and Continue
    /// return to the same canvas.
    @ObservationIgnored private var drawingScreen: WidgetDrawingViewModel?
    /// False while the phone still holds data of an account whose session ended
    /// without a sign-out. That data shows on the canvas, and signing in as someone
    /// else clears it, so the drawing step is left out then.
    @ObservationIgnored private let phoneHasNoOtherAccount: @MainActor () -> Bool

    init(
        store: any WelcomeFlowStoring = UserDefaultsWelcomeFlowStore(),
        funnel: any WelcomeFunnelRecording = WelcomeFunnelRecorder.shared,
        canvas: any WidgetCanvasManaging = WidgetCanvasService.shared,
        rasterizer: any WidgetDrawingRasterizing = WidgetDrawingRasterizer(),
        pendingUploads: WidgetPendingUploadStore = .shared,
        startDateQueue: FirstDayStartedOnQueue = FirstDayStartedOnQueue(),
        drawingDrafts: any WidgetDrawingDraftStoring = FileWidgetDrawingDraftStore.shared,
        phoneHasNoOtherAccount: @escaping @MainActor () -> Bool
    ) {
        self.store = store
        self.funnel = funnel
        self.canvas = canvas
        self.rasterizer = rasterizer
        self.pendingUploads = pendingUploads
        self.startDateQueue = startDateQueue
        self.drawingDrafts = drawingDrafts
        self.phoneHasNoOtherAccount = phoneHasNoOtherAccount
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
        if let doodle, phoneHasNoOtherAccount() {
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
        store.carriedDoodle = nil
        step = .signIn(.returning)
    }

    /// A partner's code was saved, from the welcome step, the sign-in step or a link.
    func inviteCodeSaved() {
        store.startDate = nil
        store.carriedDoodle = nil
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
        guard phoneHasNoOtherAccount() else {
            store.carriedDoodle = nil
            step = .signIn(.start(hasDrawing: hasWaitingDrawing))
            return
        }
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
        step = .signIn(.start(hasDrawing: hasWaitingDrawing))
    }

    /// A first drawing made on this phone waits to be sent. Before sign-in it waits for
    /// an account, after it for the invite screen to send it.
    var hasWaitingDrawing: Bool {
        pendingUploads.pendingSnapshot?.isFirstDay == true
    }

    /// The waiting first drawing as the widget shows it, for the sign-in step. Nil when
    /// no first drawing waits or it no longer decodes.
    func waitingDrawingImage() async -> UIImage? {
        guard hasWaitingDrawing, let snapshot = await canvas.loadSavedSnapshot() else {
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
            step = phoneHasNoOtherAccount() ? .drawing : .startDate
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
    /// to the couple when the partner joined first.
    ///
    /// Also removes the unsent welcome drawing, which no screen can reach once someone
    /// is signed in. A sent one is not a draft: it stays with the canvas service and
    /// its waiting mark.
    func sessionStarted(ownerUserID: String) async {
        store.hasSignedInBefore = true
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
    /// returning after a sign-out, welcome after an account deletion. A start date that
    /// could not be queued for that account is dropped, so it never reaches whoever
    /// signs in next.
    func sessionEnded() {
        store.startDate = nil
        store.carriedDoodle = nil
        step = store.hasSignedInBefore ? .signIn(.returning) : .welcome
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
