import SwiftUI
import UIKit

/// Places the partner's avatar at the call bubble's spot (`CallBubblePlacement`), or as a tab at its
/// edge while it is tucked away. A notice or the Call, Message and Join buttons widen the avatar's
/// capsule toward the middle of the screen (`PresenceIsland`). A drag moves it anywhere along the
/// left or right edge. While a sheet or cover is over the app the avatar waits as the tab at its
/// side (`PresencePill`).
struct PresencePillLayer: View {
    let overlay: CallOverlayModel

    @Environment(CallStarter.self) private var starter: CallStarter?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset = CGSize.zero
    /// How far the tab has been dragged up or down along its edge.
    @State private var tabDragHeight: CGFloat = 0
    /// A sheet under the avatar holds unsaved work, so nothing here may close it.
    @State private var coversHoldUnsavedWork = false

    private var model: PartnerPresenceModel { overlay.presence }
    private var partnerName: String { overlay.participants.partnerName }

    private var motion: Animation {
        reduceMotion ? .easeInOut(duration: PaeoniaMotion.motionDefault) : PaeoniaMotion.callOverlay
    }

    var body: some View {
        GeometryReader { proxy in
            let placement = overlay.placement(in: proxy)
            ZStack {
                if model.mode.isExpanded {
                    // The window takes every touch while the toolbar is open, so a tap beside it
                    // closes it and goes no further.
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture { model.collapse() }
                        .accessibilityHidden(true)
                }
                if let status = model.status {
                    if case let .tucked(edge, pending) = model.mode {
                        tab(edge: edge, hasWaitingNotice: pending != nil || model.unreadChats > 0, in: placement)
                    } else {
                        pill(status, in: placement)
                    }
                }
            }
        }
        .animation(motion, value: model.mode)
        .animation(motion, value: model.status)
        .animation(motion, value: model.unreadChats)
        // A chat's composer comes on screen, or the keyboard lifts it, and the avatar moves above it.
        .animation(motion, value: overlay.controlsTop)
        .task { await followCovers() }
        // The window's layer stays the same, so VoiceOver hears of a new notice only from here.
        .onChange(of: model.mode.shownNotice) { _, notice in
            guard let notice else { return }
            AccessibilityNotification.Announcement(notice.callout.accessibilityLabel(partnerName: partnerName)).post()
        }
    }

    /// UIKit sends no event when something is presented over the app's window, so the layer looks
    /// four times a second, and only while the avatar is on screen.
    private func followCovers() async {
        defer { model.coversClosed() }
        while !Task.isCancelled {
            if PaeoniaAppWindow.isCovered {
                model.coverOpened(tuckingAt: overlay.spot.edge)
            } else {
                model.coversClosed()
            }
            let holdsUnsavedWork = AppCovers.holdUnsavedWork
            if holdsUnsavedWork != coversHoldUnsavedWork { coversHoldUnsavedWork = holdsUnsavedWork }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    // MARK: - The avatar, its notice and its toolbar

    /// The avatar's capsule against its edge. A notice or the buttons widen it toward the middle of
    /// the screen, and the face stays where it is.
    private func pill(_ status: PresencePillStatus, in placement: CallBubblePlacement) -> some View {
        let spot = overlay.spot
        let rowY = placement.center(of: spot, bubble: PresenceAvatar.outerSize).y
        let content = islandContent(status)
        return PresenceIsland(faceEdge: spot.edge, showsContent: content != .none) {
            islandContent(content)
                .transition(.opacity)
        } face: {
            face(status, hasOwnGlass: content == .none, in: placement)
        }
        .overlay(alignment: spot.isLeading ? .topLeading : .topTrailing) {
            if model.unreadChats > 0 {
                PresenceUnreadBadge(count: model.unreadChats)
                    .frame(width: PresenceAvatar.outerSize.width, alignment: .trailing)
                    .offset(x: PaeoniaSpacing.space4, y: -PaeoniaSpacing.space4)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        // The window passes every touch outside this frame to the app underneath.
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { overlay.avatarFrame = $0 }
        .placed(on: spot.edge, rowY: rowY, rowHeight: PresenceAvatar.outerSize.height, in: placement)
        .offset(dragOffset)
    }

    /// What the capsule holds beside the face.
    private enum IslandContent: Equatable {
        case none
        case callout(PresenceCallout)
        /// Call, Message, and Join for `join`, a game or the drawing.
        case actions(join: PresenceDestination?)
        /// Where the partner is, for an open toolbar over a sheet that holds unsaved work, which
        /// nothing here may close.
        case place
    }

    /// The open toolbar shows the buttons. So does the partner opening a game or the drawing, so Join
    /// is one tap away.
    private func islandContent(_ status: PresencePillStatus) -> IslandContent {
        let canLeave = !coversHoldUnsavedWork
        if model.mode.isExpanded { return canLeave ? .actions(join: model.joinTarget) : .place }
        switch status.callout {
        case let .openedGame(kind) where canLeave: return .actions(join: .game(kind))
        case .openedDrawing where canLeave: return .actions(join: .drawing)
        case let .some(callout): return .callout(callout)
        case nil: return .none
        }
    }

    @ViewBuilder
    private func islandContent(_ content: IslandContent) -> some View {
        switch content {
        case .none:
            EmptyView()
        case let .callout(callout):
            PresenceCalloutContent(
                callout: callout, partnerName: partnerName,
                canOpen: !coversHoldUnsavedWork && callout.destination != nil
            ) {
                if let destination = callout.destination { open(destination, clearingNotice: true) }
            }
        case let .actions(join):
            PresenceActions(
                partnerName: partnerName, showsMessage: model.viewer.visibleChat != .couple, join: join,
                call: call, message: { open(.chat(.couple)) }, open: { open($0, clearingNotice: true) }
            )
            .accessibilityAction(.escape) { model.collapse() }
        case .place:
            Text(verbatim: model.status?.headline ?? "")
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextSecondary)
                .lineLimit(1)
                .padding(.horizontal, PaeoniaSpacing.space12)
        }
    }

    private func face(
        _ status: PresencePillStatus, hasOwnGlass: Bool, in placement: CallBubblePlacement
    ) -> some View {
        PresenceAvatar(participants: overlay.participants, place: status.place, hasOwnGlass: hasOwnGlass)
            .contentShape(Circle())
            .onTapGesture { model.toggleToolbar() }
            .gesture(drag(in: placement))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(status.accessibilityLabel(partnerName: partnerName)))
            .accessibilityValue(
                model.unreadChats > 0 ? Text(.presenceAvatarUnreadChats(model.unreadChats)) : Text(verbatim: ""))
            .accessibilityHint(Text(.presenceAvatarAccessibilityHint))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { model.toggleToolbar() }
            .accessibilityAction(named: Text(.presenceActionTuck)) { model.tuck(overlay.spot.edge) }
            .accessibilityIdentifier("presence.avatar")
    }

    // MARK: - Tucked away

    private func tab(edge: HorizontalEdge, hasWaitingNotice: Bool, in placement: CallBubblePlacement) -> some View {
        let width = PresenceTab.size.width
        let y = placement.center(of: overlay.spot, bubble: PresenceAvatar.outerSize).y
        let shownY = placement.center(
            of: CallBubbleSpot(edge: edge, y: y + tabDragHeight), bubble: PresenceAvatar.outerSize).y
        return PresenceTab(edge: edge, partnerName: partnerName, hasWaitingNotice: hasWaitingNotice)
            .onTapGesture { model.untuck() }
            .accessibilityAddTraits(.isButton)
            .gesture(tabDrag(edge: edge, fromY: y, in: placement))
            .accessibilityAction { model.untuck() }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { overlay.tabFrame = $0 }
            .position(x: edge == .leading ? width / 2 : placement.size.width - width / 2, y: shownY)
            .transition(.move(edge: edge == .leading ? .leading : .trailing).combined(with: .opacity))
    }

    /// The tab slides up and down its edge with the finger and stays where it is dropped. A pull in
    /// from the edge brings the avatar out there.
    private func tabDrag(edge: HorizontalEdge, fromY y: CGFloat, in placement: CallBubblePlacement) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { tabDragHeight = $0.translation.height }
            .onEnded { value in
                let inward = edge == .leading ? value.translation.width : -value.translation.width
                let droppedY = placement.settledY(y + value.translation.height, bubble: PresenceAvatar.outerSize)
                withAnimation(motion) {
                    overlay.spot = CallBubbleSpot(edge: edge, y: droppedY)
                    if inward > PresenceTab.size.width * 1.5 { model.untuck() }
                    tabDragHeight = 0
                }
            }
    }

    /// The avatar follows the finger and settles against the edge it was thrown toward, at the height
    /// it was dropped. Only a third past the edge, or a hard fling at it, tucks it away.
    private func drag(in placement: CallBubblePlacement) -> some Gesture {
        // In global space, because the avatar moves under the finger.
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                model.collapse()
                dragOffset = value.translation
            }
            .onEnded { value in
                let landing = placement.landing(
                    from: overlay.spot, translation: value.translation, velocity: value.velocity,
                    bubble: PresenceAvatar.outerSize)
                withAnimation(motion) {
                    overlay.spot = landing.spot
                    if case let .tucked(spot) = landing { model.tuck(spot.edge) }
                    dragOffset = .zero
                }
            }
    }

    // MARK: - Actions

    /// The sheets and covers over the app close first, so what a tap opens shows on top. Call's night
    /// question is an alert under them in the app's window, so Call waits for them as well.
    private func call() {
        model.collapse()
        AppCovers.close { [starter, partnerName] in starter?.start(partnerName: partnerName) }
    }

    /// A notice goes only once what it opens shows, because a sheet that gained unsaved work since
    /// the avatar last drew stays open and opens nothing.
    private func open(_ destination: PresenceDestination, clearingNotice: Bool = false) {
        model.collapse()
        AppCovers.close { [model] in
            if clearingNotice { model.clearNotice() }
            model.open(destination)
        }
    }
}

/// The sheets and covers over the app's screens, in the app's own window.
@MainActor
private enum AppCovers {
    /// One of them holds unsaved work or a save in progress, which `interactiveDismissDisabled`
    /// marks, so it must stay open. SwiftUI answers that through the presentation's delegate and
    /// leaves `isModalInPresentation` false, so both are asked.
    static var holdUnsavedWork: Bool {
        PaeoniaAppWindow.presentedControllers.contains { controller in
            if controller.isModalInPresentation { return true }
            guard let presentation = controller.presentationController else { return false }
            return presentation.delegate?.presentationControllerShouldDismiss?(presentation) == false
        }
    }

    /// Closes all of them, then runs `then`. It runs at once when none is up, and never while one
    /// holds unsaved work.
    static func close(then: @escaping @MainActor () -> Void) {
        guard let root = PaeoniaAppWindow.rootViewController, root.presentedViewController != nil else {
            then()
            return
        }
        guard !holdUnsavedWork else { return }
        root.dismiss(animated: true, completion: then)
    }
}
