import SwiftUI

nonisolated extension VerticalAlignment {
    private enum ThoughtBubbleBase: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[.bottom]
        }
    }

    /// The bottom edge of a thought bubble's body, above its dots. The body rests on the
    /// avatar there, and the dots reach down into the avatar.
    static let thoughtBubbleBase = VerticalAlignment(ThoughtBubbleBase.self)
}

/// A thought bubble that sits on top of a Home avatar with the person's note. Without a
/// note, your own bubble shows a quiet "Note..." that opens the editor.
struct StoryNoteBubble: View {
    /// Nil shows the placeholder.
    let text: String?

    nonisolated static let maxWidth: CGFloat = 92
    /// A note shows at most this many lines on Home.
    nonisolated static let maxLines = 2

    var body: some View {
        ThoughtBubble(dotSize: ThoughtBubbleMetrics.compactDotSize) {
            Group {
                if let text {
                    Text(text)
                        .foregroundStyle(.paeoniaTextPrimary)
                        .lineLimit(Self.maxLines)
                } else {
                    Text(.storiesNotePlaceholder)
                        .foregroundStyle(.paeoniaTextSecondary)
                        .lineLimit(1)
                }
            }
            .modifier(BodyStyle())
        }
        .frame(maxWidth: Self.maxWidth)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// An empty body as tall as the tallest note, for reserving its room in a layout.
    static var tallestBody: some View {
        // An empty string reserves only one line, so this holds a space.
        Text(verbatim: " ")
            .lineLimit(maxLines, reservesSpace: true)
            .modifier(BodyStyle())
            .hidden()
            .accessibilityHidden(true)
    }

    private struct BodyStyle: ViewModifier {
        func body(content: Content) -> some View {
            content
                .font(PaeoniaTypography.caption)
                .multilineTextAlignment(.center)
                .padding(.horizontal, PaeoniaSpacing.space12)
                .padding(.vertical, PaeoniaSpacing.space8)
        }
    }
}

/// A rounded bubble around `content` with two dots under it, the bigger one near the
/// left edge and the smaller one below it and to the right, leading down to an avatar.
struct ThoughtBubble<Content: View>: View {
    /// The bigger dot's diameter. The rest of the bubble scales with it.
    let dotSize: CGFloat
    @ViewBuilder let content: Content

    /// How much bigger than the Home bubble this one is. Corners scale with it.
    private var scale: CGFloat { dotSize / ThoughtBubbleMetrics.compactDotSize }
    private var smallDotSize: CGFloat { dotSize * ThoughtBubbleMetrics.smallDotRatio }

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
            content
                .background(
                    RoundedRectangle(cornerRadius: PaeoniaRadius.radius16 * scale, style: .continuous)
                        .fill(.paeoniaSurfacePressed)
                )
                .alignmentGuide(.thoughtBubbleBase) { $0[.bottom] }
            // The bigger dot is one dot in from the left edge. The smaller one starts
            // where the bigger one ends, so the pair leads down and to the right.
            Circle()
                .fill(.paeoniaSurfacePressed)
                .frame(width: dotSize, height: dotSize)
                .padding(.leading, dotSize)
            Circle()
                .fill(.paeoniaSurfacePressed)
                .frame(width: smallDotSize, height: smallDotSize)
                .padding(.leading, dotSize * 2)
        }
        // Lifts the bubble off the avatar and the background behind it.
        .compositingGroup()
        .shadow(color: .black.opacity(ThoughtBubbleMetrics.shadowOpacity), radius: PaeoniaSpacing.space4 * scale)
    }
}

/// The sizes every thought bubble shares.
nonisolated enum ThoughtBubbleMetrics {
    /// The bigger dot under a bubble over a Home avatar.
    static let compactDotSize: CGFloat = 9
    /// The smaller dot compared to the bigger one, as in the Instagram note bubble.
    static let smallDotRatio: CGFloat = 0.55
    static let shadowOpacity: Double = 0.3
}

extension View {
    /// Rests `bubble`'s body on top of this avatar, its dots reaching into the avatar.
    /// The bubble takes no room in the layout.
    func storyNoteBubble<Bubble: View>(clearance: CGFloat = 0, @ViewBuilder _ bubble: () -> Bubble) -> some View {
        overlay(alignment: .top) {
            bubble()
                .alignmentGuide(.top) { $0[.thoughtBubbleBase] + clearance }
        }
    }
}

/// Wraps its content at `maxWidth` and takes the width the wrapped lines need, not the
/// whole `maxWidth`, so a bubble hugs a note that wraps. A frame can't do this: it takes
/// the full width as soon as one line is too long.
struct WrappedWidth: Layout {
    let maxWidth: CGFloat

    func sizeThatFits(proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: nil))
    }
}
