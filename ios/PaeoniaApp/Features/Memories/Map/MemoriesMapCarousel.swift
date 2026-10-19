import SwiftUI

/// The cards under the map. Each card is one placed memory, newest first. Swiping moves
/// the selection, and the map follows. Tapping a card opens the memory.
struct MemoriesMapCarousel: View {
    let entries: [MemoryMapEntry]
    @Binding var selectedID: UUID?
    let onOpen: (UUID) -> Void

    @State private var scrolledID: UUID?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: PaeoniaSpacing.space12) {
                ForEach(entries) { entry in
                    card(entry)
                        .containerRelativeFrame(.horizontal) { width, _ in
                            min(width - 2 * PaeoniaSpacing.space32, 420)
                        }
                        .id(entry.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrolledID, anchor: .center)
        .contentMargins(.horizontal, PaeoniaSpacing.space32, for: .scrollContent)
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        // A horizontal scroll view takes all the height it is offered.
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { scrolledID = selectedID }
        .onChange(of: selectedID) { _, id in
            guard let id, id != scrolledID else { return }
            withAnimation(PaeoniaMotion.stateChange) { scrolledID = id }
        }
        .onChange(of: scrolledID) { _, id in
            guard let id, id != selectedID else { return }
            PaeoniaHaptics.selection()
            selectedID = id
        }
    }

    /// The title, then the place without its city (the map shows where it is), then
    /// the date. A Guess my spot round shows its place, then "From Guess my spot", then
    /// the date. Nothing is cut off: long text wraps, and at the largest text sizes the
    /// photo moves above the text.
    private func card(_ entry: MemoryMapEntry) -> some View {
        let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.radius20, style: .continuous)
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: PaeoniaSpacing.space12))
            : AnyLayout(HStackLayout(spacing: PaeoniaSpacing.space12))
        return Button {
            onOpen(entry.id)
        } label: {
            layout {
                MemoryMapThumbnail(photoAssetID: entry.photoAssetID, size: 56)
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
                    Text(entry.title)
                        .font(PaeoniaTypography.bodyEmphasis)
                        .foregroundStyle(.paeoniaTextPrimary)
                    Text(entry.kind == .memory ? entry.place.name : String(localized: .memoriesMapFromGuessMySpot))
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaMemory)
                    if let date = MemoryMapText.date(entry.memoryDate) {
                        Text(date)
                            .font(PaeoniaTypography.caption)
                            .foregroundStyle(.paeoniaTextSecondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(PaeoniaSpacing.space12)
            .background(.paeoniaSurfacePrimary, in: shape)
            .overlay { shape.stroke(.paeoniaSurfacePressed, lineWidth: PaeoniaRadius.strokeDefault) }
            .shadow(color: .black.opacity(0.3), radius: 14, y: 8)
            .contentShape(shape)
        }
        .buttonStyle(.paeoniaPressableCard)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text(entry.kind == .guessMySpotRound ? .memoriesMapRoundCardHint : .memoriesMapCardHint))
    }
}

/// A memory's first photo in a small rounded tile, or the heart tile without one.
struct MemoryMapThumbnail: View {
    let photoAssetID: UUID?
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let photoAssetID {
                MemoryMediaImageView(
                    mediaAssetID: photoAssetID,
                    height: size,
                    cornerRadius: PaeoniaRadius.radius12,
                    allowsViewing: false
                )
            } else {
                RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous)
                    .fill(.paeoniaSurfaceSecondary)
                    .overlay {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.paeoniaMemory)
                    }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

enum MemoryMapText {
    /// "14 Feb 2026 · Bryggen, Bergen", or "14 Feb 2026 · From Guess my spot" for a round.
    static func dateAndPlace(_ entry: MemoryMapEntry) -> String {
        let second = entry.kind == .guessMySpotRound
            ? String(localized: .memoriesMapFromGuessMySpot)
            : entry.place.nameAndCity
        return [date(entry.memoryDate), second].compactMap(\.self).joined(separator: " · ")
    }

    /// "3 memories", or "3 places" when Guess my spot rounds are among them.
    static func count(_ entries: [MemoryMapEntry]) -> String {
        let mixed = entries.contains { $0.kind == .guessMySpotRound }
        if entries.count == 1 {
            return String(localized: mixed ? .memoriesMapPlaceCountOne : .memoriesMapMemoryCountOne)
        }
        let count = entries.count.formatted()
        return String(localized: mixed ? .memoriesMapPlaceCount(count) : .memoriesMapMemoryCount(count))
    }

    static func date(_ memoryDate: String) -> String? {
        MemoryTimeline.parseLocalDate(memoryDate).map { $0.formatted(MemoryDateStyle.short) }
    }
}
