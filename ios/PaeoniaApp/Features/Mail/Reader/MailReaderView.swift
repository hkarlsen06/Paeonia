import SwiftUI

/// One letter. A letter that waits to be opened shows as a sealed envelope. Tapping it folds
/// the flap back, opens the letter on the server, and the letter rises out of the pocket.
struct MailReaderView: View {
    let mail: MailViewModel
    let people: MailPeople
    let letterID: UUID
    let onWriteBack: () -> Void

    private static let envelopeWidth: CGFloat = 260

    @State private var opening = DailyPromptEnvelopeOpening.closed
    /// The envelope stays up while it opens, so the letter rises out of it before the page shows.
    @State private var isOpeningEnvelope = false
    @State private var reportTarget: PrivacyReportTarget?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let letter = mail.letter(id: letterID) {
                ScrollView {
                    content(letter)
                        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                        .padding(.vertical, PaeoniaSpacing.screenTopSpacing)
                        .paeoniaReadableWidth(PaeoniaSpacing.readableContentWidth)
                }
                .toolbar {
                    if letter.recipientUserID == people.currentUserID, letter.state == .opened {
                        ToolbarItem(placement: .primaryAction) { reportMenu(letter) }
                    }
                }
            } else {
                PaeoniaEmptyStateView(title: .mailErrorLetterGone, systemImage: "envelope.open") {
                    Button {
                        dismiss()
                    } label: {
                        Text(.mailReaderBackToMailbox)
                    }
                    .buttonStyle(PaeoniaPrimaryButtonStyle())
                    .accessibilityIdentifier("mail.reader.back")
                }
                .padding(PaeoniaSpacing.screenHorizontalPadding)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.paeoniaBackgroundPrimary)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $reportTarget) { target in
            if let partnerUserID = people.partnerUserID {
                ReportAndLeaveView(
                    partnerUserID: partnerUserID,
                    partnerName: people.partnerName,
                    reportTarget: target,
                    onReportedAndLeft: people.onReportedAndLeft
                )
            }
        }
    }

    private func content(_ letter: Letter) -> some View {
        VStack(spacing: PaeoniaSpacing.sectionSpacing) {
            if letter.body == nil || isOpeningEnvelope {
                sealed(letter)
            } else {
                MailLetterPage(letter: letter, people: people)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                if letter.recipientUserID == people.currentUserID {
                    Button(action: onWriteBack) {
                        Text(.mailReaderWriteBack)
                    }
                    .buttonStyle(PaeoniaPrimaryButtonStyle())
                    .accessibilityIdentifier("mail.reader.writeBack")
                }
            }
        }
    }

    private func reportMenu(_ letter: Letter) -> some View {
        Menu {
            Button(role: .destructive) {
                reportTarget = .letter(letterID: letter.id)
            } label: {
                Label {
                    Text(.mailReaderReport)
                } icon: {
                    Image(systemName: "exclamationmark.bubble")
                }
            }
        } label: {
            Label {
                Text(.mailReaderMore)
            } icon: {
                Image(systemName: "ellipsis")
            }
        }
    }

    private func sealed(_ letter: Letter) -> some View {
        VStack(spacing: PaeoniaSpacing.space24) {
            Text(.mailReaderFrom(people.partnerName))
                .font(PaeoniaTypography.title)
                .foregroundStyle(.paeoniaTextPrimary)
                .multilineTextAlignment(.center)
            Button {
                Task { await open(letter) }
            } label: {
                envelope
                    // The open flap reaches above the envelope, so it gets room to fold back without covering the name.
                    .padding(.top, Self.envelopeWidth / PaeoniaEnvelopeLayer.aspect * 0.7)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(mail.openingLetterID != nil)
            .accessibilityLabel(Text(.mailReaderOpenAction))
            .accessibilityIdentifier("mail.reader.envelope")
            Text(.mailReaderTapToOpen)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
                .multilineTextAlignment(.center)
                .accessibilityHidden(true)
        }
    }

    /// The seal comes off as the flap starts to fold back.
    private var envelope: some View {
        DailyPromptEnvelope(width: Self.envelopeWidth, opening: opening)
            .overlay(alignment: .topLeading) {
                Image(.homeWaxSealPink)
                    .resizable()
                    .accessibilityHidden(true)
                    .scaledToFit()
                    .frame(width: Self.envelopeWidth * 0.27)
                    .position(
                        x: Self.envelopeWidth * 0.495,
                        y: Self.envelopeWidth / PaeoniaEnvelopeLayer.aspect * 0.614
                    )
                    .scaleEffect(opening == .closed ? 1 : 1.3)
                    .opacity(opening == .closed ? 1 : 0)
            }
    }

    private func open(_ letter: Letter) async {
        isOpeningEnvelope = true
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) { opening = .flapOpening }
        let opened = await mail.open(letter)
        guard opened != nil else {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { opening = .closed }
            isOpeningEnvelope = false
            return
        }
        withAnimation(reduceMotion ? nil : .spring(duration: 0.5)) { opening = .letterOut }
        if !reduceMotion { try? await Task.sleep(for: .milliseconds(700)) }
        withAnimation(reduceMotion ? nil : PaeoniaMotion.stateChange) { isOpeningEnvelope = false }
    }
}

/// The letter itself: its card, who it is from or to, the note and the photo.
struct MailLetterPage: View {
    let letter: Letter
    let people: MailPeople

    @ScaledMetric(relativeTo: .title) private var artWidth: CGFloat = 96
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
            header
            if let body = letter.body {
                Text(verbatim: body)
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(.paeoniaTextPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("mail.reader.body")
            }
            if let mediaAssetID = letter.mediaAssetID {
                MailLetterPhoto(mediaAssetID: mediaAssetID)
            }
            if isOwn, let status = sentStatus {
                Text(verbatim: status)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
        }
        .padding(PaeoniaSpacing.cardContentPadding)
        .background(
            RoundedRectangle(cornerRadius: PaeoniaRadius.standard, style: .continuous)
                .fill(Color.paeoniaBackgroundSecondary)
        )
    }

    /// Side by side, or stacked at the accessibility text sizes so the name keeps its width.
    private var header: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: PaeoniaSpacing.space12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: PaeoniaSpacing.space16))
        return layout {
            if let templateKey = letter.templateKey {
                Image(LetterTemplate(templateKey).art)
                    .resizable()
                    .accessibilityHidden(true)
                    .scaledToFit()
                    .frame(width: min(artWidth, 160), height: min(artWidth, 160))
            }
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                Text(isOwn ? .mailReaderTo(people.partnerName) : .mailReaderFrom(people.partnerName))
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)
                if let createdAt = letter.createdAt {
                    Text(.mailReaderWritten(createdAt.formatted(date: .long, time: .shortened)))
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextSecondary)
                }
            }
        }
    }

    private var isOwn: Bool {
        letter.authorUserID == people.currentUserID
    }

    private var sentStatus: String? {
        switch letter.state {
        case .sealed:
            letter.deliverAt.map { date in
                let when = date.formatted(.dateTime.weekday(.wide).day().month().hour().minute())
                return String(localized: .mailStatusArrives(when))
            } ?? String(localized: .mailStatusWaitsForMeeting)
        case .delivered:
            String(localized: .mailStatusDelivered)
        case .opened:
            String(localized: .mailStatusOpened(people.partnerName))
        }
    }
}

/// Where a letter's photo is kept on this phone. It goes through the memory photo download
/// cache, since it is stored the same way, and the decoded image is kept at `maxPixelSize`.
nonisolated enum MailLetterPhotoCache {
    static let maxPixelSize = 2_048

    /// Removes the photos of letters that left this phone's lists.
    static func evict(_ mediaAssetIDs: [UUID]) async {
        await MemoryMediaImageService.shared?.evict(mediaAssetIDs: mediaAssetIDs)
        for mediaAssetID in mediaAssetIDs {
            MemoryImageDecoding.remove(mediaAssetID, maxPixelSize: maxPixelSize)
        }
    }
}

/// The photo in a letter. A failed photo retries on tap.
private struct MailLetterPhoto: View {
    let mediaAssetID: UUID
    @State private var load = ImageLoad<UUID>.loading

    private static let maxPixelSize = MailLetterPhotoCache.maxPixelSize

    var body: some View {
        ZStack {
            if let image = load.image(for: mediaAssetID) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel(Text(.mailReaderPhoto))
            } else if load.hasFailed(for: mediaAssetID) {
                Button {
                    Task { await loadPhoto() }
                } label: {
                    Label {
                        Text(.storiesViewerPhotoFailed)
                    } icon: {
                        Image(systemName: "photo")
                    }
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
                }
                .buttonStyle(.plain)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 160)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.standard, style: .continuous))
        .task(id: mediaAssetID) { await loadPhoto() }
    }

    private func loadPhoto() async {
        if load.image(for: mediaAssetID) != nil { return }
        if let cached = MemoryImageDecoding.cachedImage(for: mediaAssetID, maxPixelSize: Self.maxPixelSize) {
            load = .loaded(mediaAssetID, cached)
            return
        }
        load = .loading
        var decoded: UIImage?
        if let data = await MemoryMediaImageProviderFactory.shared?.imageData(for: mediaAssetID) {
            decoded = await MemoryImageDecoding.downsample(data, maxPixelSize: Self.maxPixelSize)
        }
        guard !Task.isCancelled else { return }
        if let decoded {
            MemoryImageDecoding.store(decoded, for: mediaAssetID, maxPixelSize: Self.maxPixelSize)
        }
        withAnimation(PaeoniaMotion.stateChange) {
            load = ImageLoad(decoded, for: mediaAssetID)
        }
    }
}
