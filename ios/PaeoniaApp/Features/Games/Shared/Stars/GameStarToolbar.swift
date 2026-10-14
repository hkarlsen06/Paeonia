import SwiftUI

extension View {
    /// A star toggle in the trailing toolbar of a result screen. Stars are private,
    /// so the first one a person sets also says so in a quiet banner. `hintKey` is
    /// the `AppStorage` key that remembers the banner was shown, one per game.
    func gameStarToolbar(
        stars: GameStars,
        id: UUID?,
        isShown: Bool,
        hintKey: String,
        identifier: String = "game.star"
    ) -> some View {
        modifier(GameStarToolbar(stars: stars, id: id, isShown: isShown, hintKey: hintKey, identifier: identifier))
    }
}

private struct GameStarToolbar: ViewModifier {
    let stars: GameStars
    let id: UUID?
    let isShown: Bool
    let identifier: String

    @AppStorage private var hintShown: Bool
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    init(stars: GameStars, id: UUID?, isShown: Bool, hintKey: String, identifier: String) {
        self.stars = stars
        self.id = id
        self.isShown = isShown
        self.identifier = identifier
        _hintShown = AppStorage(wrappedValue: false, hintKey)
    }

    func body(content: Content) -> some View {
        content
            .toolbar {
                if isShown, let id {
                    ToolbarItem(placement: .topBarTrailing) {
                        button(id: id)
                    }
                }
            }
            .onChange(of: stars.notice) { _, notice in
                guard let notice else { return }
                bannerCenter.show(notice.banner)
                stars.clearNotice()
            }
    }

    private func button(id: UUID) -> some View {
        let isStarred = stars.isStarred(id)
        let title: LocalizedStringResource = isStarred ? .gamesStarButtonStarred : .gamesStarButton
        return Button {
            PaeoniaHaptics.selection()
            Task { await stars.toggle(id: id) }
            if !isStarred, !hintShown {
                hintShown = true
                bannerCenter.show(
                    .info(message: String(localized: .gamesStarPrivacy), systemImage: "star.fill")
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
        .accessibilityIdentifier(identifier)
    }
}
