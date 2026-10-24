import SwiftUI

/// The fixed bottom action bar, shared by the daily challenge flow and the
/// Questions-tab partner-answer flow. Skip is optional (off for partner answers).
///
/// It is a single row of three equal-width slots: Close, Send, and Shuffle or Done,
/// whose height never changes. While the keyboard is up the trailing slot's *content*
/// swaps from Shuffle to Done, but the row stays exactly the same size, so the only
/// thing that ever moves the composer above it is the keyboard itself. Nothing folds
/// or resizes here on focus, which is what keeps the composer tracking the keyboard
/// 1:1 instead of overshooting (an earlier version folded the Send button away on
/// focus; that height change raced the keyboard's own animation and bounced).
struct DailyChallengeAnswerActionBar: View {
    let primaryTitle: LocalizedStringResource
    let isPrimaryBusy: Bool
    let isPrimaryDisabled: Bool
    /// Whether the composer is focused (keyboard up). Only swaps the trailing slot
    /// from Shuffle to Done. It never changes the bar's height.
    var isComposing = false
    var canSkip = false
    /// A text label for Skip instead of the shuffle icon. A topic's Skip puts the
    /// question aside, which isn't the daily swap the icon stands for.
    var skipTitle: LocalizedStringResource?
    var isSkipBusy = false
    var isSkipDisabled = false
    let onPrimary: () -> Void
    /// Leaves the flow. Close always closes now. It is no longer overloaded to also
    /// mean "put the keyboard away", since Done owns that while composing.
    let onClose: () -> Void
    var onSkip: () -> Void = {}
    /// Puts the keyboard away. Backs the Done button that occupies the trailing slot
    /// while composing.
    var onDone: () -> Void = {}

    /// Width of the row's slot area (the three buttons plus the two gaps), measured so
    /// the primary can be floored at a third of it.
    @State private var slotsWidth: CGFloat = 0

    /// At least a third of the row, so a short title like "Neste" still reads as a real
    /// button instead of collapsing to its text width. The primary grows past this for
    /// longer titles; the side icons take whatever is left, split evenly.
    private var primaryMinWidth: CGFloat {
        max(0, (slotsWidth - PaeoniaSpacing.space12 * 2) / 3)
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // Send sits in the middle at least a third wide (growing with its title); the
        // side actions are compact icons centered in the even slots either side of it.
        // Only the row's *height* must stay constant to keep the composer bounce-free;
        // width is free to vary.
        HStack(spacing: PaeoniaSpacing.space12) {
            closeButton
                .frame(maxWidth: .infinity)
            primaryButton
                .frame(minWidth: primaryMinWidth)
                .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
            trailingButton
                .frame(maxWidth: .infinity)
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.size.width, initial: true) { _, width in
                        slotsWidth = width
                    }
            }
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.top, PaeoniaSpacing.space12)
        .padding(.bottom, PaeoniaSpacing.space8)
        .background(.paeoniaBackgroundPrimary)
    }

    private var primaryButton: some View {
        Button(action: onPrimary) {
            // The title keeps its width while busy (hidden, spinner overlaid) so the
            // content-hugging pill doesn't shrink to the spinner the moment Send is
            // tapped.
            Text(primaryTitle)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .multilineTextAlignment(.center)
                .opacity(isPrimaryBusy ? 0 : 1)
                .overlay {
                    if isPrimaryBusy {
                        ProgressView().tint(.paeoniaTextInverse)
                    }
                }
        }
        .buttonStyle(PaeoniaPrimaryButtonStyle())
        .disabled(isPrimaryDisabled || isPrimaryBusy)
        .accessibilityIdentifier("daily.flow.primary")
    }

    /// The trailing icon. Done while composing (put the keyboard away); otherwise
    /// Shuffle when the flow allows skipping, and empty for the partner-answer flow
    /// that has none. Swapping content here cannot change the row height, and the swap
    /// is instant (no cross-fade) so Done/Shuffle don't morph into each other.
    @ViewBuilder
    private var trailingButton: some View {
        Group {
            if isComposing {
                doneButton
                    .id("daily-answer-action-done")
            } else if canSkip {
                skipButton
                    .id("daily-answer-action-skip")
            } else {
                Color.clear
                    .frame(width: 1, height: PaeoniaSpacing.compactButtonHeight)
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    // The side actions are icon-only so Send's title owns the row's width. Each carries
    // an accessibility label since the glyph alone carries the meaning.
    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
        }
        .buttonStyle(PaeoniaQuietButtonStyle())
        .accessibilityLabel(Text(.dailyChallengeFlowClose))
    }

    private var doneButton: some View {
        Button(action: onDone) {
            Image(systemName: "keyboard.chevron.compact.down")
        }
        .buttonStyle(PaeoniaQuietButtonStyle())
        .accessibilityLabel(Text(.dailyChallengeFlowDoneButton))
    }

    private var skipButton: some View {
        Button(action: onSkip) {
            if isSkipBusy {
                ProgressView().controlSize(.small)
            } else if let skipTitle {
                Text(skipTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Image(systemName: "shuffle")
                    .accessibilityLabel(Text(.dailyChallengeSkipButton))
            }
        }
        .buttonStyle(PaeoniaQuietButtonStyle())
        .disabled(isSkipDisabled)
    }
}
