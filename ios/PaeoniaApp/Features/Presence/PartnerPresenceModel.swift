import Observation
import SwiftUI

/// The partner's presence while both have Paeonia open: where the partner is, this person's own
/// "Show when I'm here", the heartbeat that tells the partner this person is here, and how the
/// partner's avatar is drawn with the notice it shows. `MainTabView` owns one and runs it while the
/// app is in the foreground for the signed-in couple.
@MainActor
@Observable
final class PartnerPresenceModel {
    private(set) var feed = PartnerFeed.waiting
    /// "Show when I'm here", as the switch shows it. It moves at once and goes back if the save fails.
    private(set) var showsPresence = true
    /// A reading has said what "Show when I'm here" is. The switch waits for it.
    private(set) var isSettingLoaded = false
    private var pill: PresencePill
    /// Where a tap on the avatar asked to go. `MainTabView` opens it and clears it.
    private(set) var openRequest: PresenceDestination?
    /// What this person has on screen. `MainTabView` keeps it current. Opening or closing the
    /// drawing tells the partner at once, not at the next heartbeat.
    var viewer = PresenceViewerPlace() {
        didSet {
            if isRunning, confirmedShowsPresence, viewer.isDrawing != oldValue.isDrawing { enqueueInApp(true) }
        }
    }
    /// The call that shows in the avatar's place. The call overlay keeps it current.
    var callCover = PresenceCallCover.none {
        didSet {
            if callCover == .none || (callCover == .small && callNotice?.isAboutPartner == false) {
                setCallNotice(nil)
            }
        }
    }
    /// What the partner just did, which the call says for a few seconds while it covers the avatar.
    private(set) var callNotice: PresenceNotice?
    /// The chats with a message from the partner this person has not read, newest first, which the
    /// avatar counts once its notice has gone. `MainTabView` keeps it current.
    var unreadChats: [ThreadChatSubject] = []
    /// Grows each time the partner opens "Just us" while this person is here, so its edge can
    /// peek in.
    private(set) var partnerOpenedCoupleChat = 0

    private let gateway: any PartnerPresenceGateway
    private let heartbeatInterval: Duration
    private let noticeDuration: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    /// The setting the server last confirmed.
    private var confirmedShowsPresence = true
    private var isSavingShowsPresence = false
    private var noticeTask: Task<Void, Never>?
    private var callNoticeTask: Task<Void, Never>?
    /// The newest presence write. The next one waits for it, so a leave sent after a heartbeat
    /// reaches the server after it.
    private var lastWrite: Task<Void, Never>?
    /// Between the start and the end of `run`, when heartbeats go out.
    private var isRunning = false

    /// The heartbeat comes 2.5 times per timeout (`APP_PRESENCE_TIMEOUT_MS`, 30 seconds).
    init(
        gateway: any PartnerPresenceGateway,
        heartbeatInterval: Duration = .seconds(12),
        noticeDuration: Duration = .seconds(5),
        mode: PresencePillMode = .avatar(notice: nil),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.gateway = gateway
        pill = PresencePill(chosen: mode)
        self.heartbeatInterval = heartbeatInterval
        self.noticeDuration = noticeDuration
        self.sleep = sleep
    }

    /// The partner is here and both partners show it, so the avatar shows while no call is up.
    var isShown: Bool { feed.partner != nil }

    /// How the avatar is drawn.
    var mode: PresencePillMode { pill.mode }

    /// What the call's bubble says, while it still tells this person something new.
    var callCallout: PresenceCallout? {
        callNotice.flatMap { $0.concerns(viewer) ? $0.callout : nil }
    }

    var status: PresencePillStatus? {
        feed.partner.map { PresencePillStatus(partner: $0, notice: mode.shownNotice, viewer: viewer) }
    }

    /// What Join opens: the partner's game while it is not the one this person has open, or else
    /// the drawing while the partner draws and this person does not.
    var joinTarget: PresenceDestination? {
        guard let partner = feed.partner else { return nil }
        if let game = partner.game, game != viewer.openGame { return .game(game) }
        if partner.isDrawing, !viewer.isDrawing { return .drawing }
        return nil
    }

    /// What Message opens: the chat with the partner's newest unread message, or else
    /// `viewer.messageChat`. Nil while that chat is already on screen.
    var messageTarget: ThreadChatSubject? {
        let chat = unreadChats.first ?? viewer.messageChat
        return chat == viewer.visibleChat ? nil : chat
    }

    // MARK: - Running

    /// Follows the partner and says this person is here, until the task is cancelled. Then it says
    /// this person left and forgets the partner, so nothing of the session stays after sign-out, a
    /// relationship ending or the app leaving the foreground.
    func run(coupleID: UUID) async {
        let heartbeat = Task { await beat() }
        isRunning = true
        defer {
            isRunning = false
            heartbeat.cancel()
            leave()
        }
        for await reading in gateway.readings(coupleID: coupleID) {
            guard !Task.isCancelled else { return }
            apply(reading)
        }
    }

    /// A person who hides their presence sends no heartbeat. The server would only take them out
    /// of the room again.
    private func beat() async {
        while !Task.isCancelled {
            if confirmedShowsPresence { await enqueueInApp(true).value }
            try? await sleep(heartbeatInterval)
        }
    }

    private func leave() {
        let background = BackgroundTaskToken(name: "App presence")
        let write = enqueueInApp(false)
        Task {
            await write.value
            background.end()
        }
        follow(.waiting)
    }

    @discardableResult
    private func enqueueInApp(_ isInApp: Bool) -> Task<Void, Never> {
        let previous = lastWrite
        let gateway = gateway
        let isDrawing = isInApp && viewer.isDrawing
        let write = Task {
            await previous?.value
            try? await gateway.setInApp(isInApp, isDrawing: isDrawing)
        }
        lastWrite = write
        return write
    }

    private func apply(_ reading: PartnerPresenceReading?) {
        // A dropped subscription says nothing about the partner, so a notice that waits keeps
        // waiting until a reading says they left.
        guard let reading else {
            feed = .waiting
            return
        }
        confirmedShowsPresence = reading.showsPresence
        isSettingLoaded = true
        if !isSavingShowsPresence { showsPresence = reading.showsPresence }
        let previous = feed
        let partner = reading.partner?.ordered(after: previous.partner)
        follow(.reading(partner))
        // "Opened Ludo" that waited while the avatar was away is no longer true once they left Ludo.
        choose(pill.chosen.keepingNotice { $0.isTrue(of: partner) })
        if let callNotice, !callNotice.isTrue(of: partner) { setCallNotice(nil) }
        // The first reading of a run finds the partner where they already were. After that, a game
        // or the drawing or "Just us" that appears was just opened.
        guard case let .reading(before) = previous, let partner else { return }
        for kind in partner.games where before?.games.contains(kind) != true {
            receive(.openedGame(kind))
        }
        if partner.isDrawing, before?.isDrawing != true { receive(.openedDrawing) }
        if partner.chat == .couple, before?.chat != .couple { partnerOpenedCoupleChat += 1 }
    }

    /// Whenever the partner goes, their notices go too.
    private func follow(_ next: PartnerFeed) {
        feed = next
        if next.partner == nil {
            choose(pill.chosen.partnerLeft)
            if callNotice?.isAboutPartner == true { setCallNotice(nil) }
        }
    }

    // MARK: - Notices

    /// Shows a notice in the avatar for a few seconds, or keeps it until the toolbar closes or
    /// the avatar comes back from the edge or the cover over the app closes. A notice that tells this
    /// person nothing new is dropped. While a call covers the avatar, the call says it instead
    /// (`PresenceCallCover`).
    /// False while neither the avatar nor the call takes it, so the caller shows a banner instead.
    @discardableResult
    func receive(_ notice: PresenceNotice) -> Bool {
        guard isShown else { return false }
        switch (callCover, notice) {
        case (.none, _):
            if notice.concerns(viewer) { choose(pill.chosen.receiving(notice)) }
        case (.small, .message), (.small, .update):
            return false
        case (.small, _), (.fullScreen, _):
            if notice.concerns(viewer) { setCallNotice(notice) }
        }
        return true
    }

    /// Shows a notice in the avatar only while it is out with its toolbar closed, or on the full call
    /// screen. A notification has nowhere else to wait, so otherwise the caller shows a banner.
    func receiveNow(_ notice: PresenceNotice) -> Bool {
        switch callCover {
        case .none: guard case .avatar = mode else { return false }
        case .small: return false
        case .fullScreen: break
        }
        return receive(notice)
    }

    /// Says on the full call screen that `kind` newly needs this person, because the call covers the
    /// game. Without a call, or beside a small one, the game, the Games tab and the badges say it.
    /// It is the game's news, not the avatar's, so it shows while either partner hides their presence.
    func gameNeedsYou(_ kind: GameKind, _ need: GameNeed) {
        guard callCover == .fullScreen else { return }
        setCallNotice(.game(kind, need))
    }

    func clearNotice() {
        choose(pill.chosen.withoutNotice)
    }

    private func choose(_ chosen: PresencePillMode) {
        show(pill.choosing(chosen))
    }

    /// Moves to `next`, and times the notice it shows in the avatar. A notice the avatar keeps
    /// while it is put away starts its time when it shows.
    private func show(_ next: PresencePill) {
        guard next != pill else { return }
        if let notice = next.mode.shownNotice, notice != mode.shownNotice {
            noticeTask?.cancel()
            noticeTask = expire(notice)
        } else if next.mode.shownNotice == nil {
            noticeTask?.cancel()
        }
        pill = next
    }

    /// Shows `notice` on the call for as long as a notice shows in the avatar.
    private func setCallNotice(_ notice: PresenceNotice?) {
        callNoticeTask?.cancel()
        callNotice = notice
        guard let notice else { return }
        let duration = noticeDuration
        let sleep = sleep
        callNoticeTask = Task { [weak self] in
            try? await sleep(duration)
            guard !Task.isCancelled, let self, callNotice == notice else { return }
            callNotice = nil
        }
    }

    func clearCallNotice() {
        setCallNotice(nil)
    }

    private func expire(_ notice: PresenceNotice) -> Task<Void, Never> {
        let duration = noticeDuration
        let sleep = sleep
        return Task { [weak self] in
            try? await sleep(duration)
            guard !Task.isCancelled, let self, mode.shownNotice == notice else { return }
            clearNotice()
        }
    }

    // MARK: - The avatar

    /// A tap on the avatar opens the toolbar, or closes it.
    func toggleToolbar() {
        choose(pill.chosen.toggled)
    }

    func collapse() {
        choose(pill.chosen.collapsed)
    }

    func tuck(_ edge: HorizontalEdge) {
        choose(pill.chosen.tucked(at: edge))
    }

    func untuck() {
        show(pill.untucked)
    }

    /// A sheet or cover is over the app, which puts the avatar away at `edge` until the person
    /// brings it out.
    func coverOpened(tuckingAt edge: HorizontalEdge) {
        show(pill.covered(tuckingAt: edge))
    }

    func coversClosed() {
        show(pill.uncovered)
    }

    /// Asks `MainTabView` to open `destination`.
    func open(_ destination: PresenceDestination) {
        openRequest = destination
    }

    /// The destination to open next. Taking it clears it.
    func takeOpenRequest() -> PresenceDestination? {
        defer { openRequest = nil }
        return openRequest
    }

    // MARK: - Setting

    /// Turns "Show when I'm here" on or off. The switch moves at once, one save runs at a time, and a
    /// failed save puts back what the server last confirmed. False when the save failed.
    func setShowsPresence(_ shows: Bool) async -> Bool {
        guard shows != showsPresence else { return true }
        showsPresence = shows
        guard !isSavingShowsPresence else { return true }
        isSavingShowsPresence = true
        defer { isSavingShowsPresence = false }
        while showsPresence != confirmedShowsPresence {
            let desired = showsPresence
            do {
                confirmedShowsPresence = try await gateway.setShowsPresence(desired)
                // Back in the room now, not at the next heartbeat.
                if confirmedShowsPresence { enqueueInApp(true) }
            } catch {
                showsPresence = confirmedShowsPresence
                return false
            }
        }
        return true
    }
}
