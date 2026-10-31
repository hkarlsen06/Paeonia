import SwiftUI

struct StoryViewerIconButton: View {
    let systemImage: String
    let label: LocalizedStringResource
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.15), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

struct StoryNavigationControls: View {
    let canGoBack: Bool
    let automaticAdvanceAvailable: Bool
    @Binding var isPaused: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            control("chevron.left", label: .storiesViewerPrevious, action: onPrevious)
                .disabled(!canGoBack)
                .accessibilityIdentifier("story.viewer.previous")
            Spacer(minLength: 0)
            if automaticAdvanceAvailable {
                control(
                    isPaused ? "play.fill" : "pause.fill",
                    label: isPaused ? .storiesViewerResume : .storiesViewerPause
                ) { isPaused.toggle() }
                .accessibilityIdentifier("story.viewer.pause")
            }
            Spacer(minLength: 0)
            control("chevron.right", label: .storiesViewerNext, action: onNext)
                .accessibilityIdentifier("story.viewer.next")
        }
        .padding(.horizontal, PaeoniaSpacing.space8)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius16))
    }

    private func control(_ image: String, label: LocalizedStringResource, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

struct StoryViewerTopBar: View {
    let story: Story
    let people: StoryPeople
    let mode: StoryViewerContent.Mode
    let count: Int
    let index: Int
    let progress: Double
    let onShare: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            if mode == .home {
                StoryProgressBars(count: count, index: index, progress: progress)
            }
            StoryViewerHeader(story: story, people: people, mode: mode, onShare: onShare, onClose: onClose)
        }
        .padding(PaeoniaSpacing.space8)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius16))
    }
}

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
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
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
            .accessibilityIdentifier("story.viewer.close")
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
