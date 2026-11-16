import SwiftUI

/// Shared date formatting for memories. Formatted in UTC so the shown day matches the
/// couple-local `memoryDate` exactly, regardless of where the viewer currently is.
nonisolated enum MemoryDateStyle {
    private static let utc = TimeZone(identifier: "UTC") ?? .gmt
    static let short = Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: utc)
    static let long = Date.FormatStyle(date: .long, time: .omitted, timeZone: utc)
    /// "October 2026", for the timeline's month headers.
    static let month = Date.FormatStyle(timeZone: utc, capitalizationContext: .beginningOfSentence)
        .month(.wide)
        .year()
}

struct MemoryCardView: View {
    let record: MemoryRecord
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var dateShadowFeather = PaeoniaSpacing.space20

    var body: some View {
        PaeoniaCard {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
                content
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: contentAccessibilityLabel))

                StoredReactionBadge(target: .memory(record.snapshot.memoryID))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: PaeoniaRadius.standard, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var content: some View {
        if cover != nil, !dynamicTypeSize.isAccessibilitySize {
            HStack(alignment: .top, spacing: PaeoniaSpacing.space16) {
                textContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                photo
                    .frame(maxWidth: .infinity)
            }
        } else {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
                textContent
                if cover != nil { photo }
            }
        }
    }

    private var textContent: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            title
                .font(PaeoniaTypography.title)
                .fixedSize(horizontal: false, vertical: true)
            if notePreview != nil {
                note
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let place = record.snapshot.place {
                Text(place.shortName)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaMemory)
            }
            if cover == nil {
                date
                    .foregroundStyle(.paeoniaMemory)
            }
        }
    }

    private var title: some View {
        Text(record.snapshot.title ?? "")
            .foregroundStyle(.paeoniaTextPrimary)
            .multilineTextAlignment(.leading)
    }

    private var note: some View {
        Text(notePreview ?? "")
            .font(PaeoniaTypography.body)
            .foregroundStyle(.paeoniaTextSecondary)
            .multilineTextAlignment(.leading)
    }

    private var date: some View {
        Text(dayStartUTC, format: MemoryDateStyle.short)
            .font(PaeoniaTypography.caption)
            .multilineTextAlignment(.trailing)
    }

    private var photo: some View {
        GeometryReader { geometry in
            MemoryMediaImageView(
                media: cover?.media,
                height: geometry.size.width,
                cornerRadius: PaeoniaRadius.radius12,
                allowsViewing: false
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay(alignment: .topTrailing) {
            date
                .foregroundStyle(.white)
                .padding(PaeoniaSpacing.space8)
                .background {
                    Rectangle()
                        .fill(.black.opacity(0.65))
                        .padding([.leading, .bottom], -dateShadowFeather)
                        // Extend beyond the crop so only the left and bottom edges fade.
                        .padding([.top, .trailing], -dateShadowFeather * 2)
                        .blur(radius: dateShadowFeather)
                }
        }
        .overlay(alignment: .bottomTrailing) {
            if media.count > 1 {
                Text("+\(media.count - 1)")
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(PaeoniaSpacing.space8)
                    .background(.black.opacity(0.6), in: Capsule())
                    .padding(PaeoniaSpacing.space8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous))
        .accessibilityHidden(true)
    }

    private var contentAccessibilityLabel: String {
        var parts = [record.snapshot.title ?? "", dayStartUTC.formatted(MemoryDateStyle.short)]
        if let preview = notePreview {
            parts.append(preview)
        }
        let videoCount = media.count { $0.isVideo }
        let photoCount = media.count - videoCount
        if photoCount > 0 {
            parts.append(photoCount == 1
                ? String(localized: .memoriesCardPhotoCountOne)
                : String(localized: .memoriesCardPhotoCount(photoCount.formatted())))
        }
        if videoCount > 0 {
            parts.append(videoCount == 1
                ? String(localized: .memoriesCardVideoCountOne)
                : String(localized: .memoriesCardVideoCount(videoCount.formatted())))
        }
        if let place = record.snapshot.place {
            parts.append(place.shortName)
        }
        return parts.joined(separator: ", ")
    }

    private var dayStartUTC: Date {
        MemoryTimeline.parseLocalDate(record.snapshot.memoryDate) ?? record.snapshot.createdAt
    }

    private var media: [MemoryMediaSnapshot] {
        record.snapshot.visibleMedia
    }

    private var cover: MemoryMediaSnapshot? {
        record.snapshot.cover
    }

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
