import SwiftUI

/// The idea row of the drawing screen, one line at least 44 pt tall. It shows a
/// quiet "Need an idea?" button, or the idea as a chip with a shuffle button and a
/// remove button. Both states are the same height, so nothing below moves.
///
/// The row holds no state. The caller deals the ideas and keeps the current one.
struct ExquisiteCorpseIdeaRow: View {
    /// The idea on the chip. Nil shows the "Need an idea?" button.
    let idea: String?
    let onAsk: () -> Void
    let onShuffle: () -> Void
    let onRemove: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ZStack(alignment: .leading) {
            if let idea {
                chip(idea)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: Self.rise)))
            } else {
                askButton
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.compactButtonHeight, alignment: .leading)
        // Only the chip coming and going. A shuffle changes the text, not this.
        .animation(reduceMotion ? PaeoniaMotion.stateChange : PaeoniaMotion.cardReveal, value: idea != nil)
        .onChange(of: idea) { old, new in
            // Focus is on a button that just changed or went away, so say the idea.
            guard let new, new != old else { return }
            AccessibilityNotification.Announcement(String(localized: .exquisiteCorpseIdeaA11Y(new))).post()
        }
    }

    private var askButton: some View {
        Button {
            PaeoniaHaptics.selection()
            GameSound.tap.play(volume: 0.7)
            onAsk()
        } label: {
            Label {
                Text(.exquisiteCorpseIdeaAsk)
            } icon: {
                Image(systemName: "lightbulb")
                    .accessibilityHidden(true)
            }
            .font(PaeoniaTypography.caption.weight(.semibold))
        }
        .buttonStyle(PaeoniaQuietButtonStyle())
    }

    private func chip(_ idea: String) -> some View {
        HStack(spacing: 0) {
            Text(idea)
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextPrimary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                .minimumScaleFactor(0.8)
                .contentTransition(.opacity)
                .padding(.leading, PaeoniaSpacing.space16)
                .padding(.trailing, PaeoniaSpacing.space4)
                .accessibilityLabel(Text(.exquisiteCorpseIdeaA11Y(idea)))
            iconButton("shuffle", color: .paeoniaAccentPrimary, label: .exquisiteCorpseIdeaShuffle) {
                onShuffle()
            }
            iconButton("xmark", color: .paeoniaTextSecondary, label: .exquisiteCorpseIdeaRemove) {
                onRemove()
            }
        }
        .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
        .background(.paeoniaSurfacePrimary, in: Capsule(style: .continuous))
        // A quick cross-fade of the text on a shuffle, and the chip resizing with it.
        .animation(PaeoniaMotion.buttonPress, value: idea)
    }

    private func iconButton(
        _ systemName: String,
        color: Color,
        label: LocalizedStringResource,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            PaeoniaHaptics.selection()
            GameSound.tap.play(volume: 0.7)
            action()
        } label: {
            Image(systemName: systemName)
                .font(PaeoniaTypography.caption.weight(.bold))
                .foregroundStyle(color)
                .frame(minWidth: PaeoniaSpacing.compactButtonHeight, minHeight: PaeoniaSpacing.compactButtonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    private static let rise: CGFloat = 6
}

#if DEBUG
private struct ExquisiteCorpseIdeaRowPreview: View {
    private static let ideas = ["a grandma", "a robot", "a very tired knight", "frog legs"]
    @State private var index: Int?

    var body: some View {
        ExquisiteCorpseIdeaRow(
            idea: index.map { Self.ideas[$0] },
            onAsk: { index = 0 },
            onShuffle: { index = ((index ?? 0) + 1) % Self.ideas.count },
            onRemove: { index = nil }
        )
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.paeoniaBackgroundSecondary)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ExquisiteCorpseIdeaRowPreview()
}
#endif
