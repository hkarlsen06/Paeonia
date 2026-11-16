import SwiftUI

/// The play glyph and length shown on a video's poster, in chat, memories and stories.
struct VideoBadge: View {
    let durationMs: Int?

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space4) {
            Image(systemName: "play.fill")
            if let duration {
                Text(duration.formatted(.time(pattern: .minuteSecond)))
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, PaeoniaSpacing.space8)
        .padding(.vertical, PaeoniaSpacing.space4)
        .background(.black.opacity(0.55), in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: Self.accessibilityLabel(durationMs: durationMs)))
    }

    private var duration: Duration? {
        durationMs.map { .milliseconds($0) }
    }

    /// "Video, 42 seconds", for a poster that speaks as one element. A description
    /// follows as its own sentence.
    static func accessibilityLabel(durationMs: Int?, description: String? = nil) -> String {
        var label = String(localized: .mediaVideoLabel)
        if let durationMs {
            let length = Duration.milliseconds(durationMs)
                .formatted(.units(allowed: [.minutes, .seconds], width: .wide))
            label += ", \(length)"
        }
        guard let description = description?.trimmedNonEmpty else { return label }
        return "\(label). \(description)"
    }
}
