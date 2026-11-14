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

    @Binding var destination: GameChatDestination?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var screen = CGSize.zero
    /// The screen inside its safe area, in global coordinates.
    @State private var safeFrame = CGRect.zero
    /// The top of the game's bottom controls, such as its action bar, in global coordinates.
    @State private var controlsTop: CGFloat?
    /// The chat in the panel. It stays from before the panel rises until the panel is down
    /// again, so the chat is there for both slides.
    @State private var mounted: GameChatDestination?
    @State private var isRaised = false

    private var isPanel: Bool {
        horizontalSizeClass == .compact && verticalSizeClass == .regular
    }

    private var slide: Animation? {
        reduceMotion ? nil : .spring(duration: PaeoniaMotion.motionMorph, bounce: 0)
    }

    func body(content: Content) -> some View {
        let panel = isPanel ? destination : nil
        let panelHeight = screen.height * Self.panelFraction
        content
            // Here, before the panel joins in with its own composer.
            .onPreferenceChange(PaeoniaBannerBottomEdgeKey.self) { edge in
                if mounted == nil { controlsTop = edge }
            }
            .environment(\.gameChatShrink, isRaised ? shrink(above: panelHeight) : nil)
            .allowsHitTesting(mounted == nil)
            .accessibilityHidden(mounted != nil)
            // Shows around the small game.
            .background { if mounted != nil { Color.black.ignoresSafeArea() } }
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

    /// The screen as large as it can be with its top under the status bar and the top of
    /// its bottom controls at the panel. The panel covers those controls, which nobody can
    /// use while it is open, so the rest of the game shows larger. A screen that reports no
    /// bottom controls shows whole.
    private func shrink(above panelHeight: CGFloat) -> GameChatShrink? {
        let top = safeFrame.minY + Self.gamePadding
        // Down to the panel itself, so nothing of what it covers shows above it.
        let room = screen.height - panelHeight - top
        guard room > 0, safeFrame.height > 0, screen.width > 0 else { return nil }
        // At least the upper half of the screen stays in view.
        let bottom = controlsTop.map { min(max($0, safeFrame.midY), safeFrame.maxY) } ?? safeFrame.maxY
        let scale = min(room / (bottom - safeFrame.minY), (screen.width - 2 * Self.gamePadding) / screen.width, 1)
        return GameChatShrink(
            scale: scale,
            origin: CGPoint(x: (screen.width - scale * screen.width) / 2, y: top - scale * safeFrame.minY)
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
    }

    /// The panel at the bottom of the whole screen, where it keeps its place when the
    /// keyboard opens inside it.
    private func panelLayer(height: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .onGeometryChange(for: CGSize.self) { $0.size } action: { screen = $0 }
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

/// The chat panel itself. Its handle drags it down to close it.
private struct GameChatPanelSurface: View {
    private static let closeDistance: CGFloat = 120

    let destination: GameChatDestination
    let close: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ThreadChatScreen(viewModel: destination.viewModel, presentation: .panel, onClose: close)
            .overlay(alignment: .top) { handle }
            .background(.paeoniaBackgroundPrimary)
            .clipShape(.rect(topLeadingRadius: PaeoniaRadius.radius28, topTrailingRadius: PaeoniaRadius.radius28))
            .offset(y: dragOffset)
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape, close)
    }

    private var handle: some View {
        Capsule()
            .fill(.paeoniaTextSecondary.opacity(0.5))
            .frame(width: 36, height: 5)
            .padding(.top, PaeoniaSpacing.space8)
            // Narrower than the panel, so it leaves the close button in the corner alone.
            .frame(width: 160, height: 28, alignment: .top)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { dragOffset = max(0, $0.translation.height) }
                    .onEnded { value in
                        if max(value.translation.height, value.predictedEndTranslation.height) > Self.closeDistance {
                            close()
                        } else {
                            withAnimation(reduceMotion ? nil : PaeoniaMotion.stateChange) { dragOffset = 0 }
                        }
                    }
            )
            .accessibilityHidden(true)
    }
}

/// Moves the panel down by `offset`. As an `offset` modifier the move of a view with UIKit
/// views inside lands at once instead of animating.
private nonisolated struct PanelSlide: GeometryEffect {
    var offset: CGFloat

    var animatableData: CGFloat {
        get { offset }
        set { offset = newValue }
    }

    func effectValue(size _: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 0, y: offset))
    }
}
