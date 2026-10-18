import SwiftUI

/// A memory in the map's lists: photo, date, and title.
struct MemoryMapRow<Trailing: View>: View {
    let photoAssetID: UUID?
    let caption: String?
    let title: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            MemoryMapThumbnail(photoAssetID: photoAssetID, size: 44)
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
                if let caption {
                    Text(caption)
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaMemory)
                }
                Text(title)
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)
            }
            // Long titles wrap instead of being cut off.
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
    }
}

/// Memories without a place, each with an "Add place" button that opens the place sheet.
struct MemoriesUnplacedList: View {
    let viewModel: MemoriesViewModel
    let records: [MemoryRecord]

    @State private var placing: PlacingMemory?

    private struct PlacingMemory: Identifiable {
        let id: UUID
    }

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(records, id: \.snapshot.memoryID) { record in
                MemoryMapRow(
                    photoAssetID: record.snapshot.visibleMediaAssetIDs.first,
                    caption: MemoryMapText.date(record.snapshot.memoryDate),
                    title: record.snapshot.title ?? ""
                ) {
                    Button {
                        placing = PlacingMemory(id: record.snapshot.memoryID)
                    } label: {
                        Text(.memoriesMapAddPlace)
                            .font(PaeoniaTypography.caption.weight(.semibold))
                            .foregroundStyle(.paeoniaTextInverse)
                            .padding(.horizontal, PaeoniaSpacing.space12)
                            .frame(minHeight: 32)
                            .background(.paeoniaAccentPrimary, in: Capsule())
                            .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, PaeoniaSpacing.space4)
                .transition(.opacity)
                if record.snapshot.memoryID != records.last?.snapshot.memoryID {
                    Divider().overlay(Color.paeoniaTextPrimary.opacity(0.08))
                }
            }
        }
        .animation(PaeoniaMotion.stateChange, value: records.map(\.snapshot.memoryID))
        .sheet(item: $placing) { placing in
            MemoryPlaceSheet(
                photoCoordinates: [],
                knownPlaces: viewModel.knownPlaces,
                isChanging: false
            ) { place in
                Task { await viewModel.setPlace(place, forMemory: placing.id) }
            }
        }
    }
}

/// Shown over the map while no memory has a place, so the screen does a job instead of
/// showing an empty map.
struct MemoriesMapEmptyPanel: View {
    let viewModel: MemoriesViewModel
    let records: [MemoryRecord]
    let maxHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
            Text(.memoriesMapEmptyTitle)
                .font(PaeoniaTypography.title)
                .foregroundStyle(.paeoniaTextPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(.memoriesMapEmptyMessage)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, PaeoniaSpacing.space8)
            ScrollView {
                MemoriesUnplacedList(viewModel: viewModel, records: records)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding([.horizontal, .top], PaeoniaSpacing.space20)
        .padding(.bottom, PaeoniaSpacing.space8)
        .frame(maxHeight: maxHeight, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: PaeoniaRadius.radius28,
                topTrailingRadius: PaeoniaRadius.radius28,
                style: .continuous
            )
            .fill(.paeoniaSurfacePrimary)
            .ignoresSafeArea(edges: .bottom)
        }
        .paeoniaReadableWidth()
    }
}

/// "Not on the map yet": the memories still without a place.
struct MemoriesUnplacedSheet: View {
    let viewModel: MemoriesViewModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let records = viewModel.mapContent.unplaced
        NavigationStack {
            ScrollView {
                MemoriesUnplacedList(viewModel: viewModel, records: records)
                    .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            }
            .navigationTitle(Text(.memoriesMapUnplacedTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(.commonDone) }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.paeoniaBackgroundPrimary)
        .onChange(of: records.isEmpty) { _, isEmpty in
            if isEmpty { dismiss() }
        }
    }
}

/// Memories at about the same spot, which zooming can't separate.
struct MemoriesMapClusterSheet: View {
    let entries: [MemoryMapEntry]
    /// About 60% of the screen. Longer lists scroll.
    let maxHeight: CGFloat
    let onOpen: (UUID) -> Void

    /// One row's height at the current text size. The sheet's height is set before it
    /// opens, because a presented sheet doesn't follow a detent that changes later.
    @ScaledMetric private var rowHeight: CGFloat = 70

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: PaeoniaSpacing.space8) {
                    ForEach(entries, content: row)
                }
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                .padding(.bottom, PaeoniaSpacing.space16)
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle(Text(verbatim: title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if sharedCity != nil {
                    ToolbarItem(placement: .principal) { cityTitle }
                }
            }
        }
        // As tall as its rows, so two memories don't sit in a half-empty sheet.
        // As tall as its rows, so two memories don't sit in a half-empty sheet.
        .presentationDetents([.height(fittedHeight)])
        .presentationBackground(.paeoniaBackgroundPrimary)
    }

    private func row(_ entry: MemoryMapEntry) -> some View {
        Button {
            onOpen(entry.id)
        } label: {
            MemoryMapRow(
                photoAssetID: entry.photoAssetID,
                caption: MemoryMapText.dateAndPlace(entry),
                title: entry.title
            ) {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.paeoniaTextTertiary)
                    .accessibilityHidden(true)
            }
            .padding(PaeoniaSpacing.space12)
            .background(
                .paeoniaSurfacePrimary,
                in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.paeoniaPressableRow)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text(.memoriesMapCardHint))
    }

    /// "Oslo" over "2 memories".
    private var cityTitle: some View {
        VStack(spacing: 0) {
            Text(verbatim: title).font(PaeoniaTypography.sectionTitle)
            Text(verbatim: countText)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// The rows plus the title bar, the grabber, and the bottom padding.
    private var fittedHeight: CGFloat {
        let rows = CGFloat(entries.count) * (rowHeight + PaeoniaSpacing.space8)
        return min(rows + 88, maxHeight)
    }

    /// The city every memory here shares, if there is one.
    private var sharedCity: String? {
        let cities = Set(entries.map(\.place.shortName))
        return cities.count == 1 ? cities.first : nil
    }

    private var title: String {
        sharedCity ?? countText
    }

    private var countText: String {
        entries.count == 1
            ? String(localized: .memoriesMapMemoryCountOne)
            : String(localized: .memoriesMapMemoryCount(entries.count.formatted()))
    }
}
