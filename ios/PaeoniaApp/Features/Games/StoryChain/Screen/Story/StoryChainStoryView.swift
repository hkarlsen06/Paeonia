import SwiftUI

/// The story page and what sits under it. One view covers writing, waiting,
/// naming and the finished story, so the page stays in place when the turn
/// passes and only the bottom changes.
///
/// - Writing and waiting. The page is anchored to the bottom of its scroll view,
///   so the newest line and the writer's field stay in sight.
/// - Finished. `StoryChainRevealTimeline` plays the reveal: the old bottom fades
///   out, the page scrolls to the top, the title writes itself in and petals burst
///   from it, and the byline, flower, counts and button arrive one after another.
///   A tap jumps to the settled state.
struct StoryChainStoryView: View {
    let viewModel: StoryChainViewModel

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var reveal = StoryChainRevealTimeline()
    @State private var position = ScrollPosition()
    @State private var showsDareSheet = false
    /// A finished story the person opens cold reads from its top. One they just
    /// wrote starts at the bottom, where they were.
    private let opensAtTop: Bool

    init(viewModel: StoryChainViewModel) {
        self.viewModel = viewModel
        if case .finished = viewModel.phase {
            opensAtTop = true
        } else {
            opensAtTop = false
        }
    }

    var body: some View {
        // The tap that skips the reveal is for sighted people. VoiceOver never plays the reveal.
        // swiftlint:disable:next accessibility_trait_for_button
        ScrollView {
            page
                .padding(.top, PaeoniaSpacing.space16)
                .padding(.bottom, PaeoniaSpacing.space24)
        }
        .scrollPosition($position)
        .defaultScrollAnchor(opensAtTop ? .top : .bottom, for: .initialOffset)
        .defaultScrollAnchor(keepsBottom ? .bottom : .top, for: .sizeChanges)
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        // The page moves with the bottom when it changes, instead of jumping to keep
        // its bottom in place before the new bottom has faded in.
        .animation(reduceMotion ? nil : PaeoniaMotion.meaningfulMoment, value: viewModel.bottomPhase)
        // A tap anywhere ends the reveal early. The lines keep their own taps.
        .simultaneousGesture(
            TapGesture().onEnded { reveal.skip() },
            including: reveal.canSkip ? .all : .subviews
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composerBar
        }
        .paeoniaBottomBar(spacing: 0) {
            StoryChainActionBar(viewModel: viewModel, reveal: reveal)
        }
        .toolbar { starItem }
        .gameInviteToolbar(
            invite: isPartnersTurn ? viewModel.invite : .hidden,
            partnerName: viewModel.partnerName,
            send: viewModel.sendInvite,
            identifier: "storyChain.invite"
        )
        .sheet(isPresented: $showsDareSheet) {
            StoryChainDareSheet(viewModel: viewModel)
                .analyticsScreen("story_chain_dare")
        }
        .onChange(of: viewModel.phase, initial: true) { _, new in
            phaseChanged(to: new)
        }
        .onChange(of: reveal.scrolledToTop) { _, isAtTop in
            guard isAtTop else { return }
            // Fast at first, then a long settle onto the title, so the page reads as
            // going back to its start instead of a jump.
            withAnimation(reduceMotion ? nil : Self.scrollToTop) {
                position.scrollTo(edge: .top)
            }
        }
        .onChange(of: viewModel.page.lines.last?.id) { _, _ in
            announceNewPartnerLine()
        }
        .onChange(of: viewModel.stars.notice) { _, notice in
            guard let notice else { return }
            bannerCenter.show(notice.banner)
            viewModel.stars.clearNotice()
        }
        .onDisappear { reveal.stop() }
    }

    private static let scrollToTop = Animation.spring(duration: 0.6, bounce: 0)

    // MARK: Page

    private var page: some View {
        StoryChainPageView(
            content: viewModel.page,
            eyebrow: eyebrow,
            title: viewModel.finished?.title,
            titleProgress: reveal.titleProgress,
            titleBloomStart: reveal.bloomStart,
            byline: byline,
            isBylineShown: reveal.bylineShown,
            youLabel: String(localized: .storyChainPageYou),
            openingLabel: String(localized: .storyChainPageOpening),
            onArrivalFinished: { viewModel.arrivalFinished(lineID: $0) },
            lineInfo: { line in lineInfo(for: line) },
            trailing: {
                StoryChainStoryBottom(viewModel: viewModel, reveal: reveal, departingPhase: departingPhase)
            }
        )
    }

    private var eyebrow: Text {
        guard let number = viewModel.story?.story.storyNumber else { return Text(verbatim: "") }
        return Text(.storyChainStoryNumber(number))
    }

    private var byline: Text? {
        viewModel.finished.map { finished in
            Text(.storyChainFinishedByline(
                viewModel.partnerName,
                finished.finishedAt.formatted(.dateTime.month(.abbreviated).day())
            ))
        }
    }

    @ViewBuilder
    private func lineInfo(for line: StoryChainPageLine) -> some View {
        if let info = viewModel.lineInfo(for: line.id) {
            let participants = viewModel.participants
            StoryChainLineInfoPopover(
                name: info.isMine ? String(localized: .storyChainPageYou) : info.authorName,
                isMine: info.isMine,
                mediaAssetID: info.isMine ? participants.currentPhotoAssetID : participants.partnerPhotoAssetID,
                createdAt: info.createdAt,
                usedDare: info.usedDare
            )
        }
    }

    // MARK: Composer bar

    /// The bar rides up with the keyboard, so it is a plain safe area inset.
    private var composerBar: some View {
        ZStack {
            if viewModel.bottomPhase == .writing {
                StoryChainComposerBar(viewModel: viewModel) {
                    showsDareSheet = true
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(reduceMotion ? nil : PaeoniaMotion.cardReveal, value: viewModel.bottomPhase == .writing)
    }

    // MARK: Star

    /// The star arrives with the button, at the end of the reveal.
    @ToolbarContentBuilder
    private var starItem: some ToolbarContent {
        if case let .finished(storyID) = viewModel.phase, reveal.actionsShown {
            ToolbarItem(placement: .topBarTrailing) {
                StoryChainStarButton(stars: viewModel.stars, storyID: storyID, showsPrivacyHint: true)
            }
        }
    }

    /// The invite shows while the partner writes a line or names the story.
    private var isPartnersTurn: Bool {
        viewModel.phase == .waitingForLine || viewModel.phase == .waitingForName
    }

    // MARK: Anchoring

    /// The page grows at the bottom while the story is written. Once the reveal
    /// scrolled to the top, it grows downward from there.
    private var keepsBottom: Bool {
        guard case .finished = viewModel.phase else { return true }
        return !reveal.scrolledToTop
    }

    // MARK: VoiceOver

    /// A line from the partner writes itself into the page. VoiceOver reads it out
    /// as it lands, because the focus is on the field or the controls.
    private func announceNewPartnerLine() {
        guard voiceOverEnabled, let line = viewModel.page.lines.last, !line.isMine else { return }
        AccessibilityNotification.Announcement(
            StoryChainPageText.spokenText(for: line, youLabel: String(localized: .storyChainPageYou))
        ).post()
    }

    // MARK: Reveal

    /// The bottom a finished story replaces, which stays until the reveal scrolls
    /// to the top. The person who named the story had the title field, and the
    /// one who wrote the last line had the wait. A story opened cold has none.
    private var departingPhase: StoryChainPhase? {
        guard !opensAtTop, let finished = viewModel.finished else { return nil }
        return finished.isNamer ? .naming : .waitingForName
    }

    private func phaseChanged(to phase: StoryChainPhase) {
        guard case let .finished(storyID) = phase else { return }
        reveal.begin(storyID: storyID, reduceMotion: reduceMotion || voiceOverEnabled)
    }
}
