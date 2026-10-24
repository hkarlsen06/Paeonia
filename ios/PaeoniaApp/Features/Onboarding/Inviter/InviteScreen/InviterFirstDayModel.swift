import Foundation
import Observation

/// The first questions on the invite screen: the inviter answers their first two
/// questions while the code is out, and the partner sees the answers when they join.
///
/// `load` makes sure the server has a draft, which also picks the questions, and reads
/// what was answered so far. It also sends the first drawing for the partner, made
/// before sign-in (`WelcomeDrawingStep`) and saved on this phone, whenever the screen
/// loads or comes back to the front, until it reaches the draft.
@MainActor
@Observable
final class InviterFirstDayModel {
    /// The answers just turned done, for the row's completion beat. A fresh id each
    /// time makes `onChange` fire.
    struct Completion: Equatable {
        let id = UUID()
    }

    private(set) var draft: FirstDayDraft?
    /// The first load finished, whether or not it reached the server.
    private(set) var hasLoaded = false
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
    @ObservationIgnored private let pushAuthorization: any PushAuthorizationProviding
    @ObservationIgnored private let identityStore: WidgetSyncIdentityStore
    @ObservationIgnored private let questionPreferences: (any NotificationPreferencesProviding)?
    @ObservationIgnored private var answeredBeforeFlow = false

    init(
        ownerUserID: UUID?,
        authorName: String?,
        gateway: (any FirstDayGateway)? = FirstDayGatewayFactory.makeDefault(),
        uploader: FirstDayDrawingUploadService? = nil,
        canvas: any WidgetCanvasManaging = WidgetCanvasService.shared,
        pushAuthorization: any PushAuthorizationProviding = PushAuthorizationService(),
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
        self.pushAuthorization = pushAuthorization
        self.identityStore = identityStore
        self.questionPreferences = questionPreferences
    }

    var hasAnsweredQuestions: Bool {
        draft?.hasAnsweredAll ?? false
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
        answeredBeforeFlow = draft.hasAnsweredAll
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
        if !answeredBeforeFlow, draft.hasAnsweredAll {
            completion = Completion()
        }
    }

    // MARK: Drawing

    private func retryDrawingUpload() async {
        guard let uploader, await uploader.hasPendingUpload else {
            return
        }
        await uploader.retryPending()
    }
}
