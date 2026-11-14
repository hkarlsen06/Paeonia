import SwiftUI

extension View {
    /// Shows a game's chat over the lower part of the Games tab.
    func gameChatPanel(_ destination: Binding<GameChatDestination?>) -> some View {
        modifier(GameChatPanel(destination: destination))
    }
}

/// A game's chat as a panel under the game. The whole game screen shows smaller above the
/// panel and keeps running (`GameChatScreen`), so the couple sees the game while they write.
/// The keyboard opens inside the panel, so the game does not move again.
///
/// A wide window and a landscape phone have no room above a panel. There the chat is a
/// sheet over the game, which stays where it is.
struct GameChatPanel: ViewModifier {
    /// The share of the screen's height the panel takes.
    private static let panelFraction: CGFloat = 0.64
    /// The room between the small game and the status bar and the screen's sides.
    private static let gamePadding = PaeoniaSpacing.space8
    /// How far the bottom of the game rises while its chat peeks up under it.
    private static let peekLift: CGFloat = 56

    @Binding var destination: GameChatDestination?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @State private var screen = CGSize.zero
    /// The screen inside its safe area, in global coordinates.
    @State private var safeFrame = CGRect.zero
    /// The top of the game's bottom controls, such as its action bar, in global coordinates.
    @State private var controlsTop: CGFloat?
    /// Where the game's content starts under a navigation bar that holds nothing about the
    /// game, in global coordinates. Nil when the bar stays in view.
    @State private var contentTop: CGFloat?
    /// The chat in the panel. It stays from before the panel rises until the panel is down
    /// again, so the chat is there for both slides.
    @State private var mounted: GameChatDestination?
    @State private var isRaised = false
    /// The game whose chat peeks up. It stays until the peek is down again.
    @State private var peekKind: GameKind?
    @State private var isPeekRaised = false

    private var isPanel: Bool {
        horizontalSizeClass == .compact && verticalSizeClass == .regular
    }

    private var slide: Animation? {
        reduceMotion ? nil : .spring(duration: PaeoniaMotion.motionDefault, bounce: 0)
    }

    func body(content: Content) -> some View {
        let panel = isPanel ? destination : nil
        let panelHeight = screen.height * Self.panelFraction
        content
            // Here, before the panel joins in with its own composer. The edge is followed while
            // the panel is open, since a game opened together with its chat is still settling.
            .onPreferenceChange(PaeoniaBannerBottomEdgeKey.self) { edge in
                controlsTop = edge
            }
            .onPreferenceChange(GameChatContentTopKey.self) { top in
                if mounted == nil { contentTop = top }
            }
            .environment(\.gameChatShrink, isRaised ? shrink(above: panelHeight) : nil)
            .environment(\.gameChatLift, isPeekRaised ? Self.peekLift : 0)
            .environment(\.gameChatPeek, isPanel && mounted == nil ? GameChatPeek(show: showPeek, hide: hidePeek) : nil)
            .allowsHitTesting(mounted == nil)
            .accessibilityHidden(mounted != nil)
            // Shows around the small game, and around its corners while its chat peeks up.
            .background { if mounted != nil || peekKind != nil { Color.black.ignoresSafeArea() } }
            .overlay {
                Color.clear
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { safeFrame = $0 }
                    .allowsHitTesting(false)
            }
            .overlay { panelLayer(height: panelHeight) }
            // The keyboard opens inside the panel. It would otherwise lift the panel.
            .ignoresSafeArea(.keyboard, edges: mounted == nil ? [] : .bottom)
            .onChange(of: panel?.id) {
                if let panel {
                    hidePeek()
                    raise(panel)
                } else {
                    lower()
                }
            }
            .sheet(item: isPanel ? .constant(nil) : $destination) { destination in
                ThreadChatScreen(
                    viewModel: destination.viewModel,
                    presentation: .sheet,
                    onClose: { self.destination = nil }
                )
                // Half height leaves the board visible. The keyboard raises the sheet to full height.
                .presentationDetents([.medium, .large])
                .presentationContentInteraction(.scrolls)
            }
    }

    /// The screen as large as it can be with its first row under the status bar and the top
    /// of its bottom controls at the panel. The first row is the top of the content when
    /// the navigation bar holds nothing about the game, and the bar is then cut off. The
    /// panel covers the bottom controls, which nobody can use while it is open. A screen
    /// that reports neither shows whole.
    private func shrink(above panelHeight: CGFloat) -> GameChatShrink? {
        let roomTop = safeFrame.minY + Self.gamePadding
        // Down to the panel itself, so nothing of what it covers shows above it.
        let room = screen.height - panelHeight - roomTop
        guard room > 0, safeFrame.height > 0, screen.width > 0 else { return nil }
        // At least the middle half of the screen stays in view.
        let top = contentTop.map { min(max($0, safeFrame.minY), safeFrame.minY + safeFrame.height / 4) }
        let bottom = controlsTop.map { min(max($0, safeFrame.midY), safeFrame.maxY) } ?? safeFrame.maxY
        let first = top ?? safeFrame.minY
        let scale = min(room / (bottom - first), (screen.width - 2 * Self.gamePadding) / screen.width, 1)
        return GameChatShrink(
            scale: scale,
            origin: CGPoint(x: (screen.width - scale * screen.width) / 2, y: roomTop - scale * first),
            top: top ?? 0
        )
    }

    /// Builds the chat under the screen's bottom edge, then slides it up one turn later,
    /// when it has been built. A panel on its way down turns round.
    private func raise(_ panel: GameChatDestination) {
        mounted = panel
        DispatchQueue.main.async {
            guard destination?.id == panel.id else { return }
            // Again, in case a panel on its way down was taken out in between.
            mounted = panel
            withAnimation(slide) { isRaised = true }
            AccessibilityNotification.ScreenChanged().post()
        }
    }

    /// Slides the panel down and then takes the chat out. A rotation ends up here too, when
    /// the sheet takes over the chat.
    private func lower() {
        // The keyboard leaves with the panel, not after it.
        PaeoniaKeyboard.dismiss()
        withAnimation(slide) {
            isRaised = false
        } completion: {
            guard !isRaised else { return }
            mounted = nil
            AccessibilityNotification.ScreenChanged().post()
        }
        // Over the game the swipe works on, for someone who keeps opening the chat with its button.
        if GameChatSwipeLessons.saved.takeTip() {
            bannerCenter.show(
                .info(message: String(localized: .gamesChatSwipeTip), systemImage: "bubble.left.and.bubble.right")
            )
        }
    }

    private func showPeek(_ kind: GameKind) {
        guard mounted == nil else { return }
        peekKind = kind
        // Built under the screen's bottom edge first, like the panel.
        DispatchQueue.main.async {
            guard peekKind == kind, mounted == nil else { return }
            withAnimation(slide) { isPeekRaised = true }
        }
    }

    private func hidePeek() {
        guard peekKind != nil else { return }
        withAnimation(slide) {
            isPeekRaised = false
        } completion: {
            if !isPeekRaised { peekKind = nil }
        }
    }

    /// The panel at the bottom of the whole screen, where it keeps its place when the
    /// keyboard opens inside it.
    private func panelLayer(height: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .onGeometryChange(for: CGSize.self) { $0.size } action: { screen = $0 }
            if mounted == nil, let peekKind {
                GameChatPeekStrip(kind: peekKind)
                    .frame(height: height)
                    .modifier(PanelSlide(offset: height - (isPeekRaised ? Self.peekLift : 0)))
                    .allowsHitTesting(false)
            }
            if let mounted {
                // A tap on the game goes back to it. The panel has the close button.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { destination = nil }
                    .accessibilityHidden(true)
                GameChatPanelSurface(destination: mounted) { destination = nil }
                    .frame(height: height)
                    .modifier(PanelSlide(offset: isRaised ? 0 : height))
                    .id(mounted.id)
            }
        }
        .ignoresSafeArea()
    }
}

/// The top of a game's chat while it peeks up under the game. It shows the chat's latest
/// message, so it reads as the chat the swipe up opens.
private struct GameChatPeekStrip: View {
    let kind: GameKind

    @Environment(\.threadChatContext) private var context

    private var line: String {
        let subject = context.coupleID.map { ThreadChatSubject.game(GameChatSubject(coupleID: $0, kind: kind)) }
        return subject.flatMap { context.summaries?.summary(for: $0)?.lastMessagePreview }
            ?? String(localized: .gamesConversationStart)
    }

    var body: some View {
        Label(line, systemImage: "bubble.left.and.bubble.right")
            .font(PaeoniaTypography.body)
            .foregroundStyle(.paeoniaTextSecondary)
            .lineLimit(1)
            .padding(.horizontal, PaeoniaSpacing.space24)
            .padding(.top, PaeoniaSpacing.space16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(.paeoniaBackgroundPrimary)
            .clipShape(.rect(topLeadingRadius: PaeoniaRadius.radius28, topTrailingRadius: PaeoniaRadius.radius28))
            .accessibilityHidden(true)
    }
}

/// The chat panel itself. A drag down on it closes it (`GameChatPanelDrag`).
private struct GameChatPanelSurface: View {
    let destination: GameChatDestination
    let close: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ThreadChatScreen(viewModel: destination.viewModel, presentation: .panel, onClose: close)
            .background(.paeoniaBackgroundPrimary)
            .clipShape(.rect(topLeadingRadius: PaeoniaRadius.radius28, topTrailingRadius: PaeoniaRadius.radius28))
            .background {
                GameChatPanelDrag { dragOffset = $0 } onEnded: { closes in
                    if closes {
                        close()
                    } else {
                        withAnimation(reduceMotion ? nil : PaeoniaMotion.stateChange) { dragOffset = 0 }
                    }
                }
            }
            .modifier(PanelSlide(offset: dragOffset))
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape, close)
    }
}

/// Moves a panel down, or right along `.horizontal`, by `offset`. As an `offset` modifier
/// the move of a view with UIKit views inside lands at once instead of animating.
nonisolated struct PanelSlide: GeometryEffect {
    var offset: CGFloat
    var axis = Axis.vertical

    var animatableData: CGFloat {
        get { offset }
        set { offset = newValue }
    }

    func effectValue(size _: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            axis == .vertical
                ? CGAffineTransform(translationX: 0, y: offset) : CGAffineTransform(translationX: offset, y: 0)
        )
    }
}
