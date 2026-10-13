import SwiftUI

extension View {
    /// A star toggle in the trailing toolbar of a result screen. Stars are private,
    /// so the first one a person sets also says so in a quiet banner.
    func drawAndGuessStarToolbar(_ viewModel: DrawAndGuessViewModel, isShown: Bool) -> some View {
        modifier(DrawAndGuessStarToolbar(viewModel: viewModel, isShown: isShown))
    }
}

private struct DrawAndGuessStarToolbar: ViewModifier {
    let viewModel: DrawAndGuessViewModel
    let isShown: Bool

    @AppStorage("games.drawAndGuess.starHintShown") private var hintShown = false
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    func body(content: Content) -> some View {
        content
            .toolbar {
                if isShown, let roundID = viewModel.round?.id {
                    ToolbarItem(placement: .topBarTrailing) {
                        button(roundID: roundID)
                    }
                }
            }
            .onChange(of: viewModel.stars.notice) { _, notice in
                guard let notice else { return }
                bannerCenter.show(notice.banner)
                viewModel.stars.clearNotice()
            }
    }

    private func button(roundID: UUID) -> some View {
        let isStarred = viewModel.stars.isStarred(roundID)
        let title: LocalizedStringResource =
            isStarred ? .gamesDrawAndGuessHistoryStarred : .gamesDrawAndGuessHistoryStar
        return Button {
            PaeoniaHaptics.selection()
            Task { await viewModel.stars.toggle(roundID: roundID) }
            if !isStarred, !hintShown {
                hintShown = true
                bannerCenter.show(
                    .info(message: String(localized: .gamesDrawAndGuessHistoryStarPrivacy), systemImage: "star.fill")
                )
            }
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: isStarred ? "star.fill" : "star")
            }
        }
        .accessibilityAddTraits(isStarred ? .isSelected : [])
        .accessibilityIdentifier("draw.reveal.star")
    }
}
