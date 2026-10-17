import Observation
import PencilKit
import UIKit

/// The "while you wait" part of the invite screen: the inviter answers their first two
/// questions and draws something for their partner, and the partner unwraps both when
/// they join.
///
/// `load` makes sure the server has a draft, which also picks the questions, and reads
/// what was made so far. After a reinstall the thumbnail comes from the server's copy,
/// and the widget extension puts that copy on the widget. A drawing saved on this phone
/// but not sent yet is retried whenever the screen loads or comes back to the front.
@MainActor
@Observable
final class InviterFirstDayModel {
    enum Item: Equatable {
        case questions
        case drawing
    }

    /// An item that just turned done, for the row's completion beat. A fresh id each
    /// time makes `onChange` fire.
    struct Completion: Equatable {
        let id = UUID()
        let item: Item
    }

    private(set) var draft: FirstDayDraft?
    /// The first load finished, whether or not it reached the server.
    private(set) var hasLoaded = false
    private(set) var drawingThumbnail: UIImage?
    /// The drawing is saved on this phone but has not reached the server yet.
    private(set) var isDrawingWaiting = false
    /// iOS allows notifications, so the person hears when their partner joins.
    private(set) var notificationsAllowed = false
    private(set) var completion: Completion?
    /// Set when opening the questions could not load them. The view shows it and
    /// then clears it.
    private(set) var loadFailure: PaeoniaFailure?

    let ownerUserID: UUID?
    let authorName: String?
    @ObservationIgnored let gateway: (any FirstDayGateway)?
    @ObservationIgnored private let uploader: FirstDayDrawingUploadService?
    @ObservationIgnored private let canvas: any WidgetCanvasManaging
    @ObservationIgnored private let downloader: any WidgetPayloadDownloading
    @ObservationIgnored private let pushAuthorization: any PushAuthorizationProviding
    @ObservationIgnored private let rasterizer: any WidgetDrawingRasterizing
    @ObservationIgnored private let identityStore: WidgetSyncIdentityStore
    @ObservationIgnored private let questionPreferences: (any NotificationPreferencesProviding)?
    @ObservationIgnored private var doneBeforeFlow: (questions: Bool, drawing: Bool) = (false, false)
    /// A drawing was sent from this screen, so the one saved on this phone is the first drawing.
    @ObservationIgnored private var sentDrawingHere = false

    private static let thumbnailPixelWidth: CGFloat = 240

    init(
        ownerUserID: UUID?,
        authorName: String?,
        gateway: (any FirstDayGateway)? = FirstDayGatewayFactory.makeDefault(),
        uploader: FirstDayDrawingUploadService? = nil,
        canvas: any WidgetCanvasManaging = WidgetCanvasService.shared,
        downloader: any WidgetPayloadDownloading = URLSessionWidgetPayloadDownloader(),
        pushAuthorization: any PushAuthorizationProviding = PushAuthorizationService(),
        rasterizer: any WidgetDrawingRasterizing = WidgetDrawingRasterizer(),
        identityStore: WidgetSyncIdentityStore = .shared,
        questionPreferences: (any NotificationPreferencesProviding)? =
            NotificationPreferencesServiceFactory.makeDefault()
    ) {
        self.ownerUserID = ownerUserID
        self.authorName = authorName
        self.gateway = gateway
        self.uploader = uploader ?? gateway.map {
            FirstDayDrawingUploadService(gateway: $0, localStore: canvas)
        }
        self.canvas = canvas
        self.downloader = downloader
        self.pushAuthorization = pushAuthorization
        self.rasterizer = rasterizer
        self.identityStore = identityStore
        self.questionPreferences = questionPreferences
    }

    var hasAnsweredQuestions: Bool {
        draft?.hasAnsweredAll ?? false
    }

    /// A drawing is on this phone, or on the server when it could not be brought back yet.
    var hasDrawing: Bool {
        drawingThumbnail != nil || draft?.drawing != nil
    }

    // MARK: Loading

    func load() async {
        // The widget extension names the author of the first drawing from this when it
        // puts the server's copy on the widget. Pairing replaces it.
        identityStore.save(
            WidgetSyncIdentity(currentUserID: ownerUserID, currentDisplayName: authorName, partnerDisplayName: nil)
        )
        await loadDraft()
        hasLoaded = true
        await refreshNotificationPermission()
        await refreshDrawing()
        await retryDrawingUpload()
    }

    /// The app came back to the front: notifications may have been turned on in
    /// Settings, and the connection may be back.
    func refreshOnForeground() async {
        await refreshNotificationPermission()
        await retryDrawingUpload()
    }

    func clearLoadFailure() {
        loadFailure = nil
    }

    private func loadDraft(reportingFailure: Bool = false) async {
        guard let gateway else {
            if reportingFailure {
                loadFailure = .other
            }
            return
        }
        do {
            draft = try await gateway.startDraft()
        } catch is CancellationError {
            return
        } catch {
            // The screen keeps what it had. Opening the questions tries again.
            if reportingFailure {
                loadFailure = PaeoniaFailure(error)
            }
        }
    }

    /// The question time step may have just asked for notifications.
    func refreshNotificationPermission() async {
        let isUndecided = await pushAuthorization.isNotDetermined()
        let isDenied = await pushAuthorization.isDenied()
        notificationsAllowed = !isUndecided && !isDenied
    }

    // MARK: Questions

    /// The questions model for the answer flow, loading the draft first when the screen
    /// could not. Nil when that fails too, with `loadFailure` set.
    func makeQuestionsModel() async -> FirstDayQuestionsModel? {
        if draft == nil {
            await loadDraft(reportingFailure: true)
        }
        guard let draft, !draft.questions.isEmpty, let ownerUserID, let gateway else {
            if loadFailure == nil {
                loadFailure = .other
            }
            return nil
        }
        doneBeforeFlow.questions = draft.hasAnsweredAll
        return FirstDayQuestionsModel(
            questions: draft.questions,
            ownerUserID: ownerUserID,
            gateway: gateway,
            preferences: questionPreferences
        )
    }

    func questionsFlowClosed(with questions: [FirstDayQuestion]) {
        guard var draft else {
            return
        }
        draft.questions = questions
        self.draft = draft
        if !doneBeforeFlow.questions, draft.hasAnsweredAll {
            completion = Completion(item: .questions)
        }
    }

    // MARK: Drawing

    /// The real widget drawing screen's view model, sending to the draft and with no
    /// live drawing, since there is no partner yet.
    func makeDrawingViewModel() -> WidgetDrawingViewModel {
        doneBeforeFlow.drawing = hasDrawing
        return WidgetDrawingViewModel(
            ownerUserID: ownerUserID,
            // There is no couple yet. The person's own ID keys the unsent draft, and no
            // real couple shares it, so it never shows up for a partner.
            coupleID: ownerUserID,
            authorName: authorName,
            service: canvas,
            uploader: uploader ?? NoOpWidgetCanvasUpload(),
            live: nil
        )
    }

    /// Call after a send on the drawing screen. Returns the drawing as an image for the
    /// widget step, or nil when the widget is on the Home Screen already.
    func drawingSent() async -> UIImage? {
        sentDrawingHere = true
        await refreshDrawing()
        guard let drawingThumbnail, !(await WidgetNudgeModel.isWidgetInstalled()) else {
            return nil
        }
        return drawingThumbnail
    }

    func drawingFlowClosed() async {
        await refreshDrawing()
        if !doneBeforeFlow.drawing, hasDrawing {
            completion = Completion(item: .drawing)
        }
    }

    private func retryDrawingUpload() async {
        guard let uploader, await uploader.hasPendingUpload else {
            return
        }
        await uploader.retryPending()
        isDrawingWaiting = await uploader.hasPendingUpload
    }

    /// Shows the first drawing saved on this phone, or the server's copy when this phone
    /// has none. A drawing on this phone counts only when it is waiting to send, was sent
    /// from here, or the draft has one, so a drawing left from an earlier relationship
    /// never shows as the first drawing.
    private func refreshDrawing() async {
        let isWaiting = await uploader?.hasPendingUpload ?? false
        let savedIsFirstDrawing = isWaiting || sentDrawingHere || draft?.drawing != nil
        if savedIsFirstDrawing, let snapshot = await canvas.loadSavedSnapshot() {
            drawingThumbnail = await thumbnail(
                of: snapshot.drawingData,
                canvasSide: snapshot.canvasSide ?? WidgetDrawingViewModel.fallbackCanvasSide
            )
        } else if let reference = draft?.drawing {
            await loadServerThumbnail(reference)
        }
        isDrawingWaiting = isWaiting
    }

    /// Downloads the draft's drawing for the thumbnail only. It doesn't touch the widget
    /// or the drawing saved on this phone.
    private func loadServerThumbnail(_ reference: FirstDayDrawingReference) async {
        guard let gateway,
              let url = try? await gateway.signedDrawingURL(mediaAssetID: reference.mediaAssetID),
              let data = try? await downloader.download(from: url),
              let drawing = try? PKDrawing(data: data)
        else {
            return
        }
        // ponytail: the app doesn't read the draft's `bounds.canvasSide`, so the drawing's
        // own extent stands in for it. Decode it if a thumbnail ever looks shifted.
        let side = max(WidgetDrawingViewModel.fallbackCanvasSide, drawing.bounds.maxX, drawing.bounds.maxY)
        drawingThumbnail = await thumbnail(of: data, canvasSide: side)
    }

    private func thumbnail(of drawingData: Data, canvasSide: CGFloat) async -> UIImage? {
        await rasterizer
            .renderPNG(fromDrawingData: drawingData, canvasSide: canvasSide, pixelWidth: Self.thumbnailPixelWidth)
            .flatMap(UIImage.init(data:))
    }
}
