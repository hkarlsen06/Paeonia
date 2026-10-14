import SwiftUI

extension View {
    /// Shows a partner's answer blurred behind a lock until `isClear` turns true. The
    /// caller flips `isClear` inside `withAnimation`, so the blur melts and the lock
    /// fades out together. With Reduce Motion there is no blur or lock, and the answer
    /// fades in.
    func partnerAnswerUnlock(isClear: Bool) -> some View {
        modifier(PartnerAnswerUnlock(isClear: isClear))
    }
}

private struct PartnerAnswerUnlock: ViewModifier {
    let isClear: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let blurRadius: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .blur(radius: isClear || reduceMotion ? 0 : Self.blurRadius)
            .opacity(isClear || !reduceMotion ? 1 : 0)
            .overlay {
                if !isClear && !reduceMotion {
                    Image(systemName: "lock.fill")
                        .font(PaeoniaTypography.title)
                        .foregroundStyle(.paeoniaAccentPrimary)
                        .transition(.opacity.combined(with: .scale(scale: 1.2)))
                        .accessibilityHidden(true)
                }
            }
    }
}
