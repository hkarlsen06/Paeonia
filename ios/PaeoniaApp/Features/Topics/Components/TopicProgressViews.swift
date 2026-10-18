import SwiftUI

/// A small ring that fills as the couple answers a topic together.
struct TopicProgressRing: View {
    let progress: Double
    let tint: Color
    var size: CGFloat = 16
    var lineWidth: CGFloat = 2.5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.paeoniaTextPrimary.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(progress, 0.001))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : PaeoniaMotion.meaningfulMoment, value: progress)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The ring and the line under a topic's name: how far the couple has come, or how
/// many questions wait, or that the topic is for adults.
struct TopicProgressLine: View {
    let topic: TopicSummary
    var partnerName = ""
    var ringSize: CGFloat = 16

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            if topic.isOpen {
                TopicProgressRing(progress: topic.progress, tint: TopicStyle.tint(for: topic.id), size: ringSize)
            }
            Text(text)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var text: LocalizedStringResource {
        switch topic.adultState {
        case .locked:
            return .topicsFlirtLocked
        case .waitingForPartner:
            return .topicsFlirtWaiting(partnerName)
        case .open:
            if topic.isFinished { return .topicsProgressFinished }
            if topic.togetherCount == 0 { return .topicsProgressQuestionCount(topic.totalCount) }
            return .topicsProgressTogether(topic.togetherCount, topic.totalCount)
        }
    }
}

/// A capsule on a topic card, such as "2 for you" or "18+".
struct TopicBadge: View {
    let text: LocalizedStringResource
    /// Bright for something waiting, quiet for a label like "18+".
    var isProminent = true

    var body: some View {
        Text(text)
            .font(PaeoniaTypography.caption.weight(.bold))
            .foregroundStyle(isProminent ? .paeoniaTextInverse : .paeoniaTextPrimary)
            .padding(.horizontal, PaeoniaSpacing.space8)
            .padding(.vertical, PaeoniaSpacing.space4)
            .background(
                isProminent ? Color.paeoniaTextPrimary : Color.paeoniaTextPrimary.opacity(0.16),
                in: Capsule()
            )
    }
}
