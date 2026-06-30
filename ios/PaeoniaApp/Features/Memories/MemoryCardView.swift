import SwiftUI

/// Shared date formatting for memories. Formatted in UTC so the shown day matches the
/// couple-local `memoryDate` exactly, regardless of where the viewer currently is.
nonisolated enum MemoryDateStyle {
    private static let utc = TimeZone(identifier: "UTC") ?? .gmt
    static let short = Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: utc)
    static let long = Date.FormatStyle(date: .long, time: .omitted, timeZone: utc)
}

/// A single memory in the timeline. One contained, private surface per moment: the
/// date, a title, a short preview of the first note, a small photo strip, and a quiet
/// "saved on this phone" line while the memory is still on its way to the partner.
struct MemoryCardView: View {
    let record: MemoryRecord

    var body: some View {
        PaeoniaCard {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
                header

                if !photoAssetIDs.isEmpty {
                    photoStrip
                }

                if let preview = notePreview {
                    Text(preview)
                        .font(PaeoniaTypography.body)
                        .foregroundStyle(.paeoniaTextSecondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if record.syncStatus == .dirty {
                    savedHint
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
            Text(dayStartUTC, format: MemoryDateStyle.short)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaMemory)

            Text(record.snapshot.title ?? "")
                .font(PaeoniaTypography.title)
                .foregroundStyle(.paeoniaTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var photoStrip: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            ForEach(Array(visiblePhotoAssetIDs.enumerated()), id: \.offset) { index, assetID in
                ZStack {
                    MemoryMediaImageView(
                        mediaAssetID: assetID,
                        height: 96,
                        cornerRadius: PaeoniaRadius.radius12,
                        allowsViewing: false
                    )

                    if index == visiblePhotoAssetIDs.count - 1, overflowCount > 0 {
                        RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous)
                            .fill(.black.opacity(0.45))
                        Text("+\(overflowCount)")
                            .font(PaeoniaTypography.title)
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var savedHint: some View {
        Label {
            Text(.syncStatusSavedLocally)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
        } icon: {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.paeoniaSuccess)
                .accessibilityHidden(true)
        }
        .labelStyle(.titleAndIcon)
    }

    private var dayStartUTC: Date {
        MemoryTimeline.parseLocalDate(record.snapshot.memoryDate) ?? record.snapshot.createdAt
    }

    private var photoAssetIDs: [UUID] {
        record.snapshot.visibleMediaAssetIDs
    }

    /// At most three thumbnails; if there are more, the third shows a "+N" overlay.
    private var visiblePhotoAssetIDs: [UUID] {
        Array(photoAssetIDs.prefix(3))
    }

    private var overflowCount: Int {
        max(0, photoAssetIDs.count - visiblePhotoAssetIDs.count)
    }

    /// The first available note body — the user's own if present, otherwise the
    /// partner's — for a short preview on the card.
    private var notePreview: String? {
        if let own = record.snapshot.ownNote, own.isVisible, let body = own.body, !body.isEmpty {
            return body
        }
        if let partner = record.snapshot.partnerNote, partner.isVisible, let body = partner.body, !body.isEmpty {
            return body
        }
        return nil
    }
}
