import SwiftUI

/// The result of a finished game: who won, who claimed the stake, the score
/// counting up, and the button for the next game. The panel rises from the
/// bottom when it appears. The chevron collapses it to the title and the button,
/// so the board shows above it. A tap while the count runs jumps to the final
/// number. With Reduce Motion the panel shows its settled state at once.
struct BoardGameResultPanel: View {
    let content: BoardGameResultContent
    let me: BoardGamePlayerInfo
    let partner: BoardGamePlayerInfo
    @Binding var isCollapsed: Bool
    let onPrimary: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var isTitleFocused: Bool
    @State private var hasRisen = false
    @State private var isCounting = false
    /// The count has finished or a tap ended it.
    @State private var isSettled = false
    @State private var wasSkipped = false
    @State private var infoHeight: CGFloat = 0

    private static let riseDistance: CGFloat = 24
    /// The panel waits for its rise before the count starts.
    private static let countDelay: TimeInterval = 0.45
    private static let countDuration: TimeInterval = 0.7
    /// The title and score scroll inside this height at accessibility text sizes.
    private static let maxScrollHeight: CGFloat = 320

    private var isRisen: Bool { hasRisen || reduceMotion }
    private var showsCount: Bool { isCounting || reduceMotion }
    private var animatesCount: Bool { !reduceMotion && !wasSkipped }
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous)
    }

    var body: some View {
        // A tap on the panel ends the count early. That is a shortcut for sighted
        // people, since VoiceOver already reads the final numbers, so the panel
        // gets no button trait.
        // swiftlint:disable:next accessibility_trait_for_button
        VStack(spacing: PaeoniaSpacing.space16) {
            info
            Button(action: onPrimary) {
                Text(primaryTitle)
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())
            .accessibilityIdentifier("boardGames.result.primary")
        }
        .frame(maxWidth: .infinity)
        .padding(PaeoniaSpacing.space20)
        .background(.paeoniaSurfacePrimary, in: shape)
        .overlay {
            shape.strokeBorder(.paeoniaSurfacePressed, lineWidth: PaeoniaRadius.strokeHairline)
        }
        .opacity(isRisen ? 1 : 0)
        .offset(y: isRisen ? 0 : Self.riseDistance)
        .animation(reduceMotion ? nil : PaeoniaMotion.meaningfulMoment, value: isCollapsed)
        .simultaneousGesture(TapGesture().onEnded { skipCount() })
        .task { await play() }
    }

    private var primaryTitle: LocalizedStringResource {
        content.isMissedEnding ? .boardGamesResultContinue : .boardGamesResultPlayAgain
    }

    // MARK: Info

    /// The title and, unless collapsed, the stake and the score. At
    /// accessibility text sizes it scrolls, so the button stays on screen.
    @ViewBuilder
    private var info: some View {
        if dynamicTypeSize.isAccessibilitySize {
            ScrollView {
                infoContent
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { infoHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: infoHeight > 0 ? min(infoHeight, Self.maxScrollHeight) : nil)
        } else {
            infoContent
        }
    }

    private var infoContent: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            titleRow
            if !isCollapsed {
                details
                    .transition(.opacity)
            }
        }
    }

    private var titleRow: some View {
        HStack(alignment: .top, spacing: PaeoniaSpacing.space8) {
            Text(content.title(partnerName: partner.name))
                .font(PaeoniaTypography.heroTitle)
                .foregroundStyle(.paeoniaTextPrimary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.compactButtonHeight, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($isTitleFocused)
                .accessibilityIdentifier("boardGames.result.title")
            collapseButton
        }
    }

    private var collapseButton: some View {
        let label: LocalizedStringResource = isCollapsed ? .boardGamesResultShow : .boardGamesResultHide
        return Button {
            isCollapsed.toggle()
        } label: {
            Image(systemName: isCollapsed ? "chevron.up" : "chevron.down")
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaTextSecondary)
                .frame(width: PaeoniaSpacing.compactButtonHeight, height: PaeoniaSpacing.compactButtonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityIdentifier("boardGames.result.collapse")
    }

    private var details: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            if let line = content.stakeLine(partnerName: partner.name) {
                stakeLine(line)
            }
            switch content.playStyle {
            case .against:
                againstScore
            case .together:
                togetherScore
            }
        }
    }

    private func stakeLine(_ line: LocalizedStringResource) -> some View {
        Label {
            Text(line)
        } icon: {
            Image(systemName: "gift")
                .foregroundStyle(.paeoniaAccentPrimary)
                .accessibilityHidden(true)
        }
        .font(PaeoniaTypography.body)
        .foregroundStyle(.paeoniaTextPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("boardGames.result.stake")
    }

    // MARK: Score

    /// One column for each partner. The winner's number counts up.
    @ViewBuilder
    private var againstScore: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: PaeoniaSpacing.space24))
            : AnyLayout(HStackLayout(alignment: .top, spacing: PaeoniaSpacing.space24))
        layout {
            column(player: me, name: Text(.boardGamesPlayerYou), count: content.myCount)
            column(player: partner, name: Text(verbatim: partner.name), count: content.partnerCount)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(content.score.spoken(partnerName: partner.name)))
        .accessibilityIdentifier("boardGames.result.score")
    }

    private func column(player: BoardGamePlayerInfo, name: Text, count: BoardGameCount) -> some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            BoardGameAvatar(player: player, size: 44)
            name
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
            countingNumber(count)
        }
        .frame(maxWidth: .infinity)
    }

    /// The couple's finished games, counting up by one.
    private var togetherScore: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            HStack(spacing: PaeoniaSpacing.space12) {
                BoardGameAvatar(player: me, size: 44)
                PaeoniaHeartDivider(width: 72)
                BoardGameAvatar(player: partner, size: 44)
            }
            countingNumber(content.gamesCount)
            Text(content.gamesFinished == 1 ? .boardGamesResultGameTogether : .boardGamesResultGamesTogether)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(content.score.spoken(partnerName: partner.name)))
        .accessibilityIdentifier("boardGames.result.score")
    }

    /// A big number with "+1" at its top trailing corner when it goes up. A tap
    /// builds the number again in its final state, which ends a count in flight.
    private func countingNumber(_ count: BoardGameCount) -> some View {
        DrawAndGuessCountingNumber(
            from: count.before,
            to: count.after,
            isCounting: showsCount,
            animates: animatesCount
        )
        .id(wasSkipped)
        .font(PaeoniaTypography.countdownNumber)
        .foregroundStyle(.paeoniaTextPrimary)
        .overlay(alignment: .topTrailing) {
            // The guide sits outside the `if`. Inside it, SwiftUI ignores the guide
            // and puts "+1" on top of the number.
            Group {
                if count.added > 0 {
                    DrawAndGuessAddedPoints(points: count.added, isShown: showsCount, animates: animatesCount)
                        .font(PaeoniaTypography.bodyEmphasis)
                }
            }
            .alignmentGuide(.trailing) { $0[.leading] - PaeoniaSpacing.space4 }
        }
    }

    // MARK: Timeline

    /// Rises and counts. The board's bloom marks a win. Reduce Motion skips all of it
    /// and keeps the haptic.
    private func play() async {
        announce()
        guard !reduceMotion else {
            if content.countsUp {
                PaeoniaHaptics.streakTick(intensity: 0.6)
            }
            isSettled = true
            return
        }
        withAnimation(PaeoniaMotion.celebrationReveal) {
            hasRisen = true
        }
        guard content.countsUp else {
            isSettled = true
            return
        }
        try? await Task.sleep(for: .seconds(Self.countDelay))
        guard !Task.isCancelled, !wasSkipped else { return }
        isCounting = true
        PaeoniaHaptics.streakTick(intensity: 0.6)
        try? await Task.sleep(for: .seconds(Self.countDuration))
        guard !Task.isCancelled else { return }
        isSettled = true
    }

    /// A tap jumps to the final numbers, without another haptic.
    private func skipCount() {
        guard !isSettled, content.countsUp else { return }
        wasSkipped = true
        isCounting = true
        isSettled = true
    }

    /// Reads the whole result once and moves VoiceOver to the title.
    private func announce() {
        if UIAccessibility.isVoiceOverRunning {
            isTitleFocused = true
        }
        AccessibilityNotification.Announcement(content.spokenSummary(partnerName: partner.name)).post()
    }
}

#if DEBUG
private struct BoardGameResultPreview: View {
    let content: BoardGameResultContent
    @State private var isCollapsed = false

    var body: some View {
        BoardGameResultPanel(
            content: content,
            me: BoardGamePreviewData.me,
            partner: BoardGamePreviewData.partner,
            isCollapsed: $isCollapsed,
            onPrimary: {}
        )
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .background(.paeoniaBackgroundSecondary)
        .preferredColorScheme(.dark)
    }
}

#Preview("You won") {
    BoardGameResultPreview(content: BoardGamePreviewData.result())
}

#Preview("Partner won, no stake") {
    BoardGameResultPreview(content: BoardGamePreviewData.result(winner: .partner, stake: nil))
}

#Preview("Draw") {
    BoardGameResultPreview(content: BoardGamePreviewData.result(winner: .draw))
}

#Preview("Together") {
    BoardGameResultPreview(content: BoardGamePreviewData.result(playStyle: .together))
}

#Preview("Missed ending") {
    BoardGameResultPreview(content: BoardGamePreviewData.result(winner: .partner, isMissedEnding: true))
}

#Preview("Accessibility size") {
    BoardGameResultPreview(content: BoardGamePreviewData.result())
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
