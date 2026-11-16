import SwiftUI

/// The round white shutter button every camera app has. A tap takes a photo, and holding
/// it records a video. While a video records, a red ring fills over the longest video a
/// story takes and the disc turns into a red square.
///
/// VoiceOver can't hold, so the button has an action that starts a video, and activating
/// it while a video records stops it.
struct StoryShutterButton: View {
    let shutter: StoryComposerModel.Shutter
    let isDisabled: Bool
    let onPressBegan: () -> Void
    let onPressEnded: () -> Void
    let onTakePhoto: () -> Void
    let onRecord: () -> Void
    let onStopRecording: () -> Void

    @GestureState private var isTouching = false

    /// The camera app's shutter size.
    private static let size: CGFloat = 78
    private static let ringWidth: CGFloat = 4
    /// The disc shrinks this much while the photo is taken.
    private static let pressedScale: CGFloat = 0.85
    /// The red square is this much of the disc while a video records.
    private static let recordingScale: CGFloat = 0.5
    private static let maxDuration = Double(Story.maxVideoDurationMs) / 1_000

    private var recordingStart: Date? {
        if case let .recording(since) = shutter { since } else { nil }
    }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(.white.opacity(recordingStart == nil ? 1 : 0.5), lineWidth: Self.ringWidth)
            if let recordingStart {
                recordingRing(since: recordingStart)
            }
            // The disc sits inside the ring with a gap as wide as the ring.
            RoundedRectangle(cornerRadius: recordingStart == nil ? Self.size / 2 : PaeoniaRadius.radius8)
                .fill(recordingStart == nil ? .white : .paeoniaError)
                .padding(Self.ringWidth * 2)
                .scaleEffect(discScale)
        }
        .frame(width: Self.size, height: Self.size)
        .contentShape(Circle())
        .shadow(color: .black.opacity(ThoughtBubbleMetrics.shadowOpacity), radius: PaeoniaSpacing.space8)
        .animation(PaeoniaMotion.buttonPress, value: shutter)
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isTouching) { _, touching, _ in touching = true }
        )
        .onChange(of: isTouching) { _, touching in
            touching ? onPressBegan() : onPressEnded()
        }
        .allowsHitTesting(!isDisabled)
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(recordingStart == nil ? .storiesComposerTakePhoto : .storiesComposerStopRecording))
        .accessibilityAction {
            if recordingStart == nil { onTakePhoto() } else { onStopRecording() }
        }
        .accessibilityActions {
            if recordingStart == nil {
                Button(action: onRecord) { Text(.storiesComposerRecordVideo) }
            }
        }
        .accessibilityIdentifier("story.composer.shutter")
    }

    private var discScale: CGFloat {
        switch shutter {
        case .recording: Self.recordingScale
        case .pressed, .takingPhoto, .startingVideo: Self.pressedScale
        case .idle: 1
        }
    }

    private func recordingRing(since start: Date) -> some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(start)
            Circle()
                .inset(by: Self.ringWidth / 2)
                .trim(from: 0, to: min(max(elapsed / Self.maxDuration, 0), 1))
                .stroke(.paeoniaError, style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityHidden(true)
    }
}
