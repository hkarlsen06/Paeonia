import SwiftUI

/// What a screen shows when a reaction could not be saved.
enum ReactionFailureBanner {
    /// Only a phone without a connection is told to check it.
    static func content(for failure: PaeoniaFailure) -> PaeoniaBannerContent {
        .error(
            title: String(localized: .reactionsErrorTitle),
            message: failure == .offline
                ? String(localized: .reactionsErrorOffline)
                : String(localized: .reactionsErrorFailed)
        )
    }
}

/// The row of emoji for reacting to `target`: the ones this person used last first, filled up
/// with the usual ones. Choosing an emoji puts it on `target`, choosing it again takes it back,
/// and the change shows at once. A refusal puts the earlier reaction back and says so in the
/// top banner. Nothing shows where no `ReactionStore` is in the environment.
struct ReactionPickerRow: View {
    let target: ReactionTarget
    /// Shown on its own glass capsule. A popover brings its own background, so it turns this off.
    var isFramed = true
    /// Runs when an emoji is chosen, for example to close the popover the row is in.
    var onPicked: () -> Void = {}

    @Environment(ReactionStore.self) private var store: ReactionStore?
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    private let palette = ReactionPalette.shared

    var body: some View {
        if let store {
            let own = store.ownReaction(on: target)
            row(own: own)
                .padding(PaeoniaSpacing.space4)
                .modifier(PickerFrame(isFramed: isFramed))
                .animation(PaeoniaMotion.buttonPress, value: own)
                // A row that outgrows a narrow screen would run off its edges.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .accessibilityElement(children: .contain)
        }
    }

    private func row(own: String?) -> some View {
        HStack(spacing: PaeoniaSpacing.space2) {
            ForEach(palette.emojis, id: \.self) { emoji in
                let isOwn = own == emoji
                let label: LocalizedStringResource = isOwn ? .reactionsRemove : .reactionsAdd(emoji)
                Button {
                    pick(emoji)
                } label: {
                    Text(verbatim: emoji)
                        .font(.title2)
                        .frame(minWidth: 44, minHeight: 44)
                        .background {
                            if isOwn {
                                Circle().fill(.paeoniaSurfacePressed)
                            }
                        }
                        .scaleEffect(isOwn ? 1.12 : 1)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(label))
                .accessibilityAddTraits(isOwn ? .isSelected : [])
            }
        }
    }

    private func pick(_ emoji: String) {
        onPicked()
        guard let store else { return }
        Task {
            if let failure = await store.toggle(emoji, on: target) {
                bannerCenter.show(ReactionFailureBanner.content(for: failure))
            }
        }
    }

    private struct PickerFrame: ViewModifier {
        let isFramed: Bool

        func body(content: Content) -> some View {
            if isFramed {
                content.glassEffect(.regular, in: Capsule())
            } else {
                content
            }
        }
    }
}

/// A small round button for tight places: it shows the user's own reaction, or a smiling face
/// before they react, and opens `ReactionPickerRow` in a popover.
struct ReactionPickerButton: View {
    enum Style {
        /// A round glass button, for a corner of a card or a row.
        case floating
        /// The bare glyph, for the navigation bar, which draws the button's glass itself.
        case toolbar
    }

    let target: ReactionTarget
    var style: Style = .floating

    @Environment(ReactionStore.self) private var store: ReactionStore?
    @State private var isPickerOpen = false

    private static let glyphSize: CGFloat = 32
    private static let hitTarget: CGFloat = 44

    var body: some View {
        if let store {
            Button {
                isPickerOpen = true
            } label: {
                label(own: store.ownReaction(on: target))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(.reactionsButton))
            .popover(isPresented: $isPickerOpen) {
                ReactionPickerRow(target: target, isFramed: false) { isPickerOpen = false }
                    .padding(PaeoniaSpacing.space4)
                    .presentationCompactAdaptation(.popover)
            }
        }
    }

    @ViewBuilder
    private func label(own: String?) -> some View {
        switch style {
        case .floating:
            glyph(own: own)
                .frame(width: Self.glyphSize, height: Self.glyphSize)
                .glassEffect(.regular, in: Circle())
                .frame(width: Self.hitTarget, height: Self.hitTarget)
                .contentShape(Rectangle())
        case .toolbar:
            glyph(own: own)
        }
    }

    @ViewBuilder
    private func glyph(own: String?) -> some View {
        if let own {
            Text(verbatim: own)
                .font(.callout)
        } else {
            Image(systemName: "face.smiling")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.paeoniaTextPrimary)
                .accessibilityHidden(true)
        }
    }
}

/// The reactions on `target` and, where the user may react, the button for adding one. Used
/// where a row, a card or a header has little room.
struct ReactionControl: View {
    let target: ReactionTarget
    var canReact = true

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space4) {
            StoredReactionBadge(target: target)
            if canReact {
                ReactionPickerButton(target: target)
            }
        }
    }
}
