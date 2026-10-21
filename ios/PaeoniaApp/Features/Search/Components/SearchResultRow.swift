import SwiftUI

extension StoryPeople {
    /// "You" for the person using the app, else the partner's name. Search rows use it for who wrote a match.
    func name(ofUser id: UUID?) -> String? {
        guard let id else { return nil }
        return id == currentUserID ? String(localized: .pairingCelebrationYouName) : partnerName
    }
}

/// One match. The matched words are marked in the lines.
struct SearchResultRow: View {
    let result: SearchResult
    let words: [String]
    let people: StoryPeople

    private static let tileSize: CGFloat = 44

    var body: some View {
        HStack(alignment: .top, spacing: PaeoniaSpacing.space12) {
            tile
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
                Text(SearchText.highlighted(titleText, words: words))
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .lineLimit(3)
                if let detail = result.detail, !detail.isEmpty {
                    Text(SearchText.highlighted(detail, words: words))
                        .font(PaeoniaTypography.body)
                        .foregroundStyle(.paeoniaTextSecondary)
                        .lineLimit(2)
                }
                if let caption {
                    Text(caption)
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var titleText: String {
        if let title = result.title, !title.isEmpty { return title }
        return result.kind == .memory ? String(localized: .searchMemoryUntitled) : ""
    }

    /// A photo for memories and stories, and the kind's symbol for text.
    @ViewBuilder
    private var tile: some View {
        switch result.kind {
        case .memory, .story:
            MemoryMapThumbnail(photoAssetID: result.photoAssetID, size: Self.tileSize)
        case .question, .answer, .message, .storyChain, .drawing, .round, .creature:
            RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous)
                .fill(.paeoniaSurfaceSecondary)
                .frame(width: Self.tileSize, height: Self.tileSize)
                .overlay {
                    Image(systemName: result.kind.systemImage)
                        .foregroundStyle(.paeoniaAccentPrimary)
                        .accessibilityHidden(true)
                }
        }
    }

    /// "You · 3 Oct 2026 · Flirt".
    private var caption: String? {
        let parts = [people.name(ofUser: result.authorUserID), dateText, result.label].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var dateText: String? {
        guard let date = result.date else { return nil }
        return result.dateIsCalendarDay
            ? date.formatted(MemoryDateStyle.short)
            : date.formatted(date: .abbreviated, time: .omitted)
    }
}
