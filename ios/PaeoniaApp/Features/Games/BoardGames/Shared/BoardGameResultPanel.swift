import SwiftUI

/// The result of a finished game: who won, and the button for the next game. The
/// score counts up in the players row above the board. The panel rises from the
/// bottom when it appears. With Reduce Motion it shows at once.
struct BoardGameResultPanel: View {
    let content: BoardGameResultContent
    let partner: BoardGamePlayerInfo
    let onPrimary: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var isTitleFocused: Bool
    @State private var hasRisen = false

    private static let riseDistance: CGFloat = 24

    private var isRisen: Bool { hasRisen || reduceMotion }
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous)
    }

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            Text(content.title(partnerName: partner.name))
                .font(PaeoniaTypography.heroTitle)
                .foregroundStyle(.paeoniaTextPrimary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($isTitleFocused)
                .accessibilityIdentifier("boardGames.result.title")
            Button(action: onPrimary) {
                GameContinueLabel(
                    title: content.isMissedEnding ? .boardGamesResultContinue : .boardGamesResultPlayAgain,
                    partnerName: partner.name,
                    continuation: content.continuation
                )
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())
            .accessibilityIdentifier("boardGames.result.primary")
        }
        .frame(maxWidth: .infinity)
        .padding(PaeoniaSpacing.space20)
        .background(.paeoniaSurfacePrimary, in: shape)
        .overlay {
            shape.strokeBorder(.paeoniaBorder, lineWidth: PaeoniaRadius.strokeHairline)
        }
        .opacity(isRisen ? 1 : 0)
        .offset(y: isRisen ? 0 : Self.riseDistance)
        .task { appear() }
    }

    /// Reads the whole result once, moves VoiceOver to the title and rises.
    private func appear() {
        if UIAccessibility.isVoiceOverRunning {
            isTitleFocused = true
        }
        AccessibilityNotification.Announcement(content.spokenSummary(partnerName: partner.name)).post()
        guard !reduceMotion else { return }
        withAnimation(PaeoniaMotion.celebrationReveal) {
            hasRisen = true
        }
    }
}

#if DEBUG
private struct BoardGameResultPreview: View {
    let content: BoardGameResultContent

    var body: some View {
        BoardGameResultPanel(content: content, partner: BoardGamePreviewData.partner, onPrimary: {})
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .background(.paeoniaBackgroundSecondary)
        .preferredColorScheme(.dark)
    }
}

#Preview("You won") {
    BoardGameResultPreview(content: BoardGamePreviewData.result())
}

#Preview("Partner won") {
    BoardGameResultPreview(content: BoardGamePreviewData.result(winner: .partner))
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
