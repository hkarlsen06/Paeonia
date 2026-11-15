import SwiftUI
import UIKit

/// Places the partner's avatar in the call bubble's corner (`CallBubblePlacement`), with a notice or
/// the toolbar beside it toward the middle of the screen, or as a tab at an edge while it is tucked
/// away. A drag moves it between corners, and a throw past the left or right edge tucks it. While a
/// sheet or cover is over the app the avatar waits as the tab at its side (`PresencePill`).
struct PresencePillLayer: View {
    let overlay: CallOverlayModel

    @Environment(CallStarter.self) private var starter: CallStarter?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset = CGSize.zero
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
                        tab(edge: edge, hasWaitingNotice: pending != nil, in: placement)
                    } else {
                        pill(status, in: placement)
                    }
                }
            }
        }
        .animation(motion, value: model.mode)
        .animation(motion, value: model.status)
        // A chat that comes on screen moves the avatar to the top, clear of its composer.
        .animation(motion, value: overlay.chatIsOnScreen)
        .task { await followCovers() }
    }

    /// UIKit sends no event when something is presented over the app's window, so the layer looks
    /// four times a second, and only while the avatar is on screen.
    private func followCovers() async {
        defer { model.coversClosed() }
        while !Task.isCancelled {
            if PaeoniaAppWindow.isCovered {
                model.coverOpened(tuckingAt: overlay.corner.isLeading ? .leading : .trailing)
            } else {
                model.coversClosed()
            }
            let holdsUnsavedWork = AppCovers.holdUnsavedWork
            if holdsUnsavedWork != coversHoldUnsavedWork { coversHoldUnsavedWork = holdsUnsavedWork }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    // MARK: - The avatar and what is beside it

    private func pill(_ status: PresencePillStatus, in placement: CallBubblePlacement) -> some View {
        let corner = overlay.corner
        let atTop = placement.showsAtTop(corner, height: PresenceAvatar.outerSize.height)
        return HStack(alignment: atTop ? .top : .bottom, spacing: PaeoniaSpacing.space8) {
            if corner.isLeading { avatar(status, in: placement) }
            beside(status, growsFrom: corner.isLeading ? .leading : .trailing)
            if !corner.isLeading { avatar(status, in: placement) }
        }
        // The window passes every touch outside this frame to the app underneath.
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { overlay.avatarFrame = $0 }
        .frame(
            width: placement.area.width, height: placement.area.height,
            alignment: Alignment(horizontal: corner.isLeading ? .leading : .trailing, vertical: atTop ? .top : .bottom)
        )
        .position(x: placement.area.midX, y: placement.area.midY)
        .offset(dragOffset)
    }

    /// The toolbar while it is open, otherwise the callout. Under a sheet that holds unsaved work,
    /// which nothing here may close, neither offers anything to open.
    @ViewBuilder
    private func beside(_ status: PresencePillStatus, growsFrom anchor: UnitPoint) -> some View {
        let transition: AnyTransition = reduceMotion
            ? .opacity : .opacity.combined(with: .scale(scale: 0.85, anchor: anchor))
        let canLeave = !coversHoldUnsavedWork
        if model.mode.isExpanded {
            PresenceToolbar(
                partnerName: partnerName, headline: status.headline, showsButtons: canLeave,
                showsMessage: model.viewer.visibleChat != .couple, joinableGame: model.joinableGame,
                call: call, message: { open(.chat(.couple)) }, join: { open(.game($0)) }
            )
            .accessibilityAction(.escape) { model.collapse() }
            .transition(transition)
        } else if let callout = status.callout {
            PresenceNoticePill(callout: callout, partnerName: partnerName, canOpen: canLeave) {
                open(callout.destination, clearingNotice: true)
            }
            .transition(transition)
        }
    }

    private func avatar(_ status: PresencePillStatus, in placement: CallBubblePlacement) -> some View {
        PresenceAvatar(participants: overlay.participants, place: status.place)
            .contentShape(Circle())
            .onTapGesture { model.toggleToolbar() }
            .gesture(drag(in: placement))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(status.accessibilityLabel(partnerName: partnerName)))
            .accessibilityHint(Text(.presenceAvatarAccessibilityHint))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { model.toggleToolbar() }
            .accessibilityAction(named: Text(.presenceActionTuck)) {
                model.tuck(overlay.corner.isLeading ? .leading : .trailing)
            }
            .accessibilityIdentifier("presence.avatar")
    }

    // MARK: - Tucked away

    private func tab(edge: HorizontalEdge, hasWaitingNotice: Bool, in placement: CallBubblePlacement) -> some View {
        let width = PresenceTab.size.width
        let y = placement.center(of: overlay.corner, bubble: PresenceAvatar.outerSize).y
        return PresenceTab(edge: edge, partnerName: partnerName, hasWaitingNotice: hasWaitingNotice)
            .onTapGesture { model.untuck() }
            .accessibilityAddTraits(.isButton)
            .gesture(DragGesture(minimumDistance: 8).onEnded { _ in model.untuck() })
            .accessibilityAction { model.untuck() }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { overlay.tabFrame = $0 }
            .position(x: edge == .leading ? width / 2 : placement.size.width - width / 2, y: y)
            .transition(.move(edge: edge == .leading ? .leading : .trailing).combined(with: .opacity))
    }

    private func drag(in placement: CallBubblePlacement) -> some Gesture {
        // In global space, because the avatar moves under the finger.
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                model.collapse()
                dragOffset = value.translation
            }
            .onEnded { value in
                let landing = placement.landing(
                    thrownFrom: overlay.corner, by: value.predictedEndTranslation, bubble: PresenceAvatar.outerSize)
                withAnimation(motion) {
                    overlay.corner = landing.corner
                    if case let .tucked(edge, _) = landing { model.tuck(edge) }
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
