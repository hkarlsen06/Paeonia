import SwiftUI

/// The star that favorites one item. It fills at once and takes the change back with a
/// banner if the phone can't save it (see `FavoritesStore`, which also says once that
/// favorites are private).
///
/// This is the one star control for every kind of favorite. Put it in a toolbar, or use
/// `favoriteToolbarItem` for the usual spot.
struct FavoriteStarButton: View {
    let target: FavoriteTarget
    var identifier = "favorite.star"
    var store: FavoritesStore = .shared

    var body: some View {
        let isFavorite = store.isFavorite(target)
        let title: LocalizedStringResource = isFavorite ? .favoritesStarred : .favoritesStar
        Button {
            PaeoniaHaptics.selection()
            Task { await store.toggle(target) }
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: isFavorite ? "star.fill" : "star")
            }
        }
        .accessibilityAddTraits(isFavorite ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

/// The same star as a small round glass button on the corner of a picture, such as a drawing.
struct FavoriteStarOverlayButton: View {
    let target: FavoriteTarget
    var identifier = "favorite.star"
    var store: FavoritesStore = .shared

    private static let glyphSize: CGFloat = 32
    private static let hitTarget: CGFloat = 44

    var body: some View {
        let isFavorite = store.isFavorite(target)
        let title: LocalizedStringResource = isFavorite ? .favoritesStarred : .favoritesStar
        Button {
            PaeoniaHaptics.selection()
            Task { await store.toggle(target) }
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.footnote.weight(.bold))
                .foregroundStyle(isFavorite ? Color.paeoniaAccentPrimary : Color.paeoniaTextPrimary)
                .frame(width: Self.glyphSize, height: Self.glyphSize)
                .glassEffect(.regular, in: Circle())
                .frame(width: Self.hitTarget, height: Self.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isFavorite ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

extension View {
    /// The favorite star in the trailing toolbar. Nothing shows while `target` is nil or
    /// `isShown` is false, such as a result screen before the item exists.
    func favoriteToolbarItem(
        _ target: FavoriteTarget?,
        isShown: Bool = true,
        identifier: String = "favorite.star"
    ) -> some View {
        toolbar {
            if isShown, let target {
                ToolbarItem(placement: .topBarTrailing) {
                    FavoriteStarButton(target: target, identifier: identifier)
                }
            }
        }
    }
}
