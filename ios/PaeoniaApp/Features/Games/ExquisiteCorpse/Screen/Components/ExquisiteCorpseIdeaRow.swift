import SwiftUI

/// The part heading and idea button, with a selected idea below them.
struct ExquisiteCorpseIdeaRow: View {
    let title: LocalizedStringResource
    let idea: String?
    let canAsk: Bool
    let onAsk: () -> Void
    let onShuffle: () -> Void
    let onRemove: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            HStack(spacing: PaeoniaSpacing.space8) {
                Text(title)
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .accessibilityIdentifier("corpse.partTitle")
                Spacer(minLength: 0)
                if canAsk && idea == nil {
                    askButton
                }
            }
            .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
            if let idea {
                chip(idea)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: Self.rise)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            HStack(spacing: PaeoniaSpacing.space4) {
                Image(systemName: "lightbulb")
                Text(verbatim: "?")
            }
            .font(PaeoniaTypography.caption.weight(.semibold))
        }
        .buttonStyle(PaeoniaQuietButtonStyle())
        .accessibilityLabel(Text(.exquisiteCorpseIdeaAsk))
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
            title: .exquisiteCorpseDrawHead,
            idea: index.map { Self.ideas[$0] },
            canAsk: true,
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
