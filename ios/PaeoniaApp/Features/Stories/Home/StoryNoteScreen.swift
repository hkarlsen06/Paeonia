import SwiftUI

/// A note, full screen. The person's avatar flies from its place on Home to the middle of
/// the screen with the bubble above it, and closing flies it back.
///
/// Editing your own note, the bubble is the text field and the row on the keyboard says
/// who sees it and shares it. A failed save keeps the text here, and the error shows in
/// the banner. Reading your partner's note, the bubble shows all of it and the row says
/// when it was shared.
///
/// Present it with animations turned off and a clear background, so this view runs the
/// whole move itself: see `HomeStoriesStrip`.
struct StoryNoteScreen: View {
    enum Mode {
        /// Your note, which starts as the one on Home now, if any.
        case edit(current: StoryNote?)
        /// Your partner's note.
        case read(StoryNote)
    }

    let mode: Mode
    let viewModel: StoriesViewModel
    let people: StoryPeople
    /// Where the avatar sits on Home, ring included, in global coordinates.
    let sourceFrame: CGRect
    /// Removes the cover once the avatar is back on Home.
    let onClose: () -> Void

    @State private var text: String
    @State private var isOpen = false
    /// Where the avatar rests when open, in global coordinates, measured from the layout.
    @State private var restingCenter: CGPoint?
    /// The field's text wrapped at `bubbleTextWidth`, measured, which sets the bubble's width.
    @State private var textWidth: CGFloat = 0
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    private static let avatarSize: CGFloat = 112
    /// The widest the text in the bubble gets before it wraps.
    private static let bubbleTextWidth: CGFloat = 200
    private static let bubbleDotSize: CGFloat = 14
    private static let maxLines = 3
    /// Room for one more character, the widest common one.
    private static let spareCharacter = "W"

    init(
        mode: Mode,
        viewModel: StoriesViewModel,
        people: StoryPeople,
        sourceFrame: CGRect,
        onClose: @escaping () -> Void
    ) {
        self.mode = mode
        self.viewModel = viewModel
        self.people = people
        self.sourceFrame = sourceFrame
        self.onClose = onClose
        _text = State(initialValue: Self.startText(mode))
    }

    private static func startText(_ mode: Mode) -> String {
        switch mode {
        case let .edit(current): current?.text ?? ""
        case let .read(note): note.text
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var current: StoryNote? {
        switch mode {
        case let .edit(current): current
        case let .read(note): note
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            ZStack {
                Color.paeoniaBackgroundSecondary
                    .opacity(isOpen ? 1 : 0)
                avatarAndBubble
                    .scaleEffect(avatarScale)
                    // Under Reduce Motion the avatar waits where it rests and only fades.
                    .opacity(reduceMotion && !isOpen ? 0 : 1)
                    .position(local(avatarCenter, from: origin))
            }
        }
        // The flying avatar ignores the keyboard. Where it rests comes from `controls`,
        // which makes room for the keyboard.
        .ignoresSafeArea()
        .overlay { controls }
        .keyboardDismissable()
        .paeoniaTopBanner(bannerCenter)
        .preferredColorScheme(.dark)
    }

    // MARK: - Avatar and bubble

    private var sourceCenter: CGPoint {
        CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)
    }

    private var avatarCenter: CGPoint {
        guard let restingCenter, isOpen || reduceMotion else { return sourceCenter }
        return restingCenter
    }

    /// The avatar is drawn at full size and scaled to its size on Home, so the photo, the
    /// initials and the bubble shrink together instead of being laid out again.
    private var avatarScale: CGFloat {
        guard !isOpen, !reduceMotion else { return 1 }
        return max(sourceFrame.width - StoryRingAvatar.ringGap * 2, 1) / Self.avatarSize
    }

    private func local(_ point: CGPoint, from origin: CGPoint) -> CGPoint {
        CGPoint(x: point.x - origin.x, y: point.y - origin.y)
    }

    private var avatarAndBubble: some View {
        PaeoniaProfilePhotoAvatar(
            mediaAssetID: isEditing ? people.currentPhotoAssetID : people.partnerPhotoAssetID,
            name: isEditing ? people.currentName : people.partnerName,
            tint: isEditing ? .paeoniaPartnerOne : .paeoniaPartnerTwo,
            size: Self.avatarSize
        )
        .accessibilityHidden(true)
        .storyNoteBubble {
            ThoughtBubble(dotSize: Self.bubbleDotSize) {
                if isEditing {
                    bubbleField
                } else {
                    WrappedWidth(maxWidth: Self.bubbleTextWidth) {
                        Text(verbatim: text)
                            .foregroundStyle(.paeoniaTextPrimary)
                    }
                        .modifier(BubbleTextStyle())
                        .accessibilityLabel(Text(.storiesNotePartnerAccessibility(people.partnerName, text)))
                }
            }
            .opacity(isOpen ? 1 : 0)
        }
        .overlay(alignment: .bottom) {
            // Under the avatar: the button's top sits a little below the avatar's bottom.
            // The guide wraps the condition, because a guide inside an `if` is lost.
            removeButtonIfNeeded
                .opacity(isOpen ? 1 : 0)
                .alignmentGuide(.bottom) { $0[.top] - PaeoniaSpacing.space8 }
        }
    }

    /// The field takes the width its text needs, wrapped at `bubbleTextWidth`, and grows
    /// in height as it wraps, so the bubble hugs what is written. A text field reports no
    /// width of its own, so a hidden copy of the text is measured. The copy holds one
    /// character more, so the caret and the next typed character fit before the bubble
    /// grows instead of wrapping.
    private var bubbleField: some View {
        TextField(text: $text, prompt: Text(.storiesNoteFieldPrompt), axis: .vertical) {
            Text(.storiesNoteFieldPrompt)
        }
        .focused($isFocused)
        .lineLimit(1...Self.maxLines)
        .foregroundStyle(.paeoniaTextPrimary)
        .onChange(of: text) { _, newText in
            if newText.count > StoryNote.maxLength {
                text = String(newText.prefix(StoryNote.maxLength))
            }
        }
        .frame(width: textWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background(alignment: .topLeading) {
            WrappedWidth(maxWidth: Self.bubbleTextWidth) {
                Text(verbatim: (text.isEmpty ? String(localized: .storiesNoteFieldPrompt) : text) + Self.spareCharacter)
            }
            .hidden()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
        }
        .modifier(BubbleTextStyle())
    }

    private struct BubbleTextStyle: ViewModifier {
        func body(content: Content) -> some View {
            // Leading, so the caret starts where the text starts. The bubble hugs the
            // text, so a line still sits in its middle.
            content
                .font(PaeoniaTypography.bodyEmphasis)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, PaeoniaSpacing.space20)
                .padding(.vertical, PaeoniaSpacing.space12)
        }
    }

    @ViewBuilder
    private var removeButtonIfNeeded: some View {
        if isEditing, current != nil {
            StoryNoteRemoveButton { Task { await save("") } }
                .disabled(viewModel.isSavingNote)
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 0) {
            HStack {
                StoryNoteCloseButton { Task { await close() } }
                    .disabled(viewModel.isSavingNote)
                Spacer()
            }
            Spacer(minLength: 0)
            restingPlace
            Spacer(minLength: 0)
            HStack(spacing: PaeoniaSpacing.space12) {
                bottomLabel
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaTextSecondary)
                Spacer(minLength: 0)
                if isEditing {
                    StoryNoteShareButton(isEnabled: canShare, isSaving: viewModel.isSavingNote) {
                        Task { await save(text) }
                    }
                }
            }
            .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
            .padding(.bottom, PaeoniaSpacing.space8)
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .opacity(isOpen ? 1 : 0)
    }

    @ViewBuilder
    private var bottomLabel: some View {
        if isEditing {
            Label {
                Text(.storiesNoteAudience(people.partnerName))
            } icon: {
                Image(systemName: "heart.fill").accessibilityHidden(true)
            }
        } else if let current {
            Label {
                Text(current.createdAt, format: .relative(presentation: .named))
            } icon: {
                Image(systemName: "clock").accessibilityHidden(true)
            }
        }
    }

    /// An empty copy of the open layout: room for the tallest note, then the avatar. It
    /// centers the two between the close button and the bottom row, and the flying
    /// avatar rests where its avatar is.
    private var restingPlace: some View {
        VStack(spacing: 0) {
            // An empty string reserves only one line, so this holds a space.
            Text(verbatim: " ")
                .lineLimit(Self.maxLines, reservesSpace: true)
                .modifier(BubbleTextStyle())
            Color.clear
                .frame(width: Self.avatarSize, height: Self.avatarSize)
                .onGeometryChange(for: CGPoint.self) { proxy in
                    let frame = proxy.frame(in: .global)
                    return CGPoint(x: frame.midX, y: frame.midY)
                } action: { center in
                    // The first measure starts the flight. A keyboard opening moves it along.
                    if restingCenter == nil {
                        restingCenter = center
                        open()
                    } else {
                        withAnimation(motion) { restingCenter = center }
                    }
                }
        }
        .hidden()
        .accessibilityHidden(true)
    }

    private var canShare: Bool {
        let note = StoriesViewModel.cleanNote(text)
        return note != nil && note != current?.text
    }

    // MARK: - Actions

    private var motion: Animation {
        reduceMotion ? PaeoniaMotion.stateChange : PaeoniaMotion.heroMorph
    }

    private func open() {
        withAnimation(motion) { isOpen = true }
        if isEditing { isFocused = true }
    }

    private func close() async {
        isFocused = false
        await withCheckedContinuation { continuation in
            withAnimation(motion) {
                isOpen = false
            } completion: {
                continuation.resume()
            }
        }
        onClose()
    }

    private func save(_ note: String) async {
        if await viewModel.setNote(note) {
            await close()
        }
    }
}
