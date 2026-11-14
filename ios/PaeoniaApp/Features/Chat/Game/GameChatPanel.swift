import SwiftUI

extension View {
    /// Shows a game's chat over the lower part of the Games tab.
    func gameChatPanel(_ destination: Binding<GameChatDestination?>) -> some View {
        modifier(GameChatPanel(destination: destination))
    }
}

/// A game's chat as a panel under the game. The game screen shrinks to its stage above the
/// panel (`GameChatStageZoom`), so the board or the drawing stays in view while the couple
/// writes. The keyboard opens inside the panel, so the game does not move again.
///
/// A wide window and a landscape phone have no room above a panel. There the chat is a
/// sheet over the game, which stays where it is.
struct GameChatPanel: ViewModifier {
    /// The share of the screen's height the panel takes.
    private static let panelFraction: CGFloat = 0.68

    @Binding var destination: GameChatDestination?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var screen = CGSize.zero
    /// The bottom of the status bar, in global coordinates.
    @State private var safeTop: CGFloat = 0
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
        let room = CGRect(x: 0, y: safeTop, width: screen.width, height: screen.height - panelHeight - safeTop)
        content
            .environment(\.gameChatStageRoom, isRaised ? room : nil)
            .allowsHitTesting(mounted == nil)
            .accessibilityHidden(mounted != nil)
            .overlay {
                Color.clear
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { safeTop = $0 }
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
                    .modifier(GameChatTransform(offset: CGSize(width: 0, height: isRaised ? 0 : height)))
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
