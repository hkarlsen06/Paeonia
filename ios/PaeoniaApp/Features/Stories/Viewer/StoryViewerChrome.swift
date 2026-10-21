import SwiftUI

/// One bar per story at the top of the viewer. Bars before the current one are full.
struct StoryProgressBars: View {
    let count: Int
    let index: Int
    /// How far through the current story, 0 to 1.
    let progress: Double

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space4) {
            ForEach(0..<count, id: \.self) { position in
                GeometryReader { proxy in
                    Capsule()
                        .fill(.white.opacity(0.3))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(.white)
                                .frame(width: proxy.size.width * fill(at: position))
                        }
                }
                .frame(height: 3)
            }
        }
        .accessibilityHidden(true)
    }

    private func fill(at position: Int) -> Double {
        if position < index { return 1 }
        if position > index { return 0 }
        return progress
    }
}

/// Who shared the story, when, and the close button.
struct StoryViewerHeader: View {
    let story: Story
    let people: StoryPeople
    let mode: StoryViewerContent.Mode
    let onShare: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            PaeoniaProfilePhotoAvatar(
                mediaAssetID: people.photoAssetID(of: story),
                name: people.name(of: story),
                tint: people.tint(of: story),
                size: 32
            )
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(people.name(of: story))
                    .font(PaeoniaTypography.bodyEmphasis)
                    .lineLimit(1)
                Text(subtitle)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            shareButton
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(.commonClose))
        }
    }

    /// Your own story opens Share. A story from your partner opens Save to Photos, since
    /// only its author can send it on.
    private var shareButton: some View {
        let canShare = people.isOwn(story)
        return Button(action: onShare) {
            Image(systemName: canShare ? "square.and.arrow.up" : "square.and.arrow.down")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(canShare ? .commonShare : .shareSave))
        .accessibilityIdentifier("story.share")
    }

    /// On Home: when it was shared and how long it stays. In the archive: the date.
    private var subtitle: String {
        switch mode {
        case .home:
            let posted = story.createdAt.formatted(.relative(presentation: .named))
            let left = Duration.seconds(max(story.expiresAt.timeIntervalSinceNow, 60))
                .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated, maximumUnitCount: 1))
            return String(localized: .storiesViewerHomeSubtitle(posted, left))
        case .archive:
            return story.createdAt.formatted(date: .abbreviated, time: .shortened)
        }
    }
}
