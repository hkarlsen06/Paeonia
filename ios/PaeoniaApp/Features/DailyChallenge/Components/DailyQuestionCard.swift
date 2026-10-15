import SwiftUI

/// The question on an answer screen, set on a raised card with a soft petal glow.
///
/// The card hugs its content. When the keyboard leaves too little room, the question
/// shrinks a little to fit instead of being cut off.
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

        VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
            header

            Text(prompt)
                .font(PaeoniaTypography.heroTitle)
                .foregroundStyle(.paeoniaTextPrimary)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

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
/// Sized to match `DailyAnswerKindPicker`, which takes their place at the bottom of
/// the card when the user can choose, so the card doesn't change height between the two.
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
            EmptyView()
        } footer: {
            DailyAnswerKindBadges(kinds: [.voice])
        }

        DailyQuestionCard(prompt: "What made you smile today?") {
            PaeoniaCardEyebrow(.dailyChallengePartnerRevealEyebrow)
        }
    }
    .padding()
    .background(PaeoniaGlowBackground())
    .preferredColorScheme(.dark)
}
#endif
