import SwiftUI

/// The question on an answer screen, set on a raised card with a soft petal glow.
///
/// In the answer flows the caller lets the card take every point of height the
/// composer leaves (`.frame(maxHeight: .infinity)`), so there's no empty gap between
/// the question and the answer. The question sits centered between the header and
/// footer. When the keyboard squeezes the card, the question shrinks a little to fit
/// instead of being cut off. In a scroll view the card simply hugs its content.
struct DailyQuestionCard<Header: View, Footer: View>: View {
    let prompt: String
    private let header: Header
    private let footer: Footer

    init(
        prompt: String,
        @ViewBuilder header: () -> Header,
        @ViewBuilder footer: () -> Footer
    ) {
        self.prompt = prompt
        self.header = header()
        self.footer = footer()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous)

        VStack(alignment: .leading, spacing: 0) {
            header

            Spacer(minLength: PaeoniaSpacing.space16)

            Text(prompt)
                .font(PaeoniaTypography.heroTitle)
                .foregroundStyle(.paeoniaTextPrimary)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

            Spacer(minLength: PaeoniaSpacing.space16)

            footer
        }
        .padding(PaeoniaSpacing.space24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { cardBackground }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(.paeoniaSurfacePressed, lineWidth: PaeoniaRadius.strokeHairline)
        }
    }

    /// A raised plum gradient, a petal glow from the top corner, and a large faint
    /// tilted question mark in the empty top-right corner.
    private var cardBackground: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [.paeoniaSurfacePrimary, .paeoniaSurfaceSecondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [.paeoniaAccentPrimary.opacity(0.22), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 320
            )

            Text(verbatim: "?")
                .font(.system(size: 160, weight: .bold, design: .serif))
                .foregroundStyle(.paeoniaAccentPrimary.opacity(0.1))
                .rotationEffect(.degrees(12))
                .padding(.top, -PaeoniaSpacing.space8)
                .padding(.trailing, PaeoniaSpacing.space24)
        }
        .accessibilityHidden(true)
    }
}

extension DailyQuestionCard where Footer == EmptyView {
    init(prompt: String, @ViewBuilder header: () -> Header) {
        self.init(prompt: prompt, header: header, footer: { EmptyView() })
    }
}

/// Small icon discs naming how a question is answered (voice, photo, writing, pick).
/// Sized to match `DailyAnswerKindPicker`, which takes their place when the user can
/// choose, so the question doesn't move between the two.
struct DailyAnswerKindBadges: View {
    let kinds: [DailyChallengeAnswerKind]

    @ScaledMetric(relativeTo: .caption) private var size: CGFloat = 32

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            ForEach(kinds) { kind in
                Image(systemName: kind.composerIcon)
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaAccentPrimary)
                    .frame(width: size, height: size)
                    .background(.paeoniaAccentPrimary.opacity(0.16), in: Circle())
            }
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview {
    VStack(spacing: PaeoniaSpacing.space16) {
        DailyQuestionCard(
            prompt: "In a short voice note, what sound, place or moment from today is hard to put into words?"
        ) {
            DailyAnswerKindBadges(kinds: [.voice])
        }
        .frame(maxHeight: .infinity)

        DailyQuestionCard(prompt: "What made you smile today?") {
            PaeoniaCardEyebrow(.dailyChallengePartnerRevealEyebrow)
        }
    }
    .padding()
    .background(PaeoniaGlowBackground())
    .preferredColorScheme(.dark)
}
#endif
