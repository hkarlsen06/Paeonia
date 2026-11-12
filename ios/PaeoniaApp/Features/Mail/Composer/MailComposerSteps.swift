import PhotosUI
import SwiftUI

struct MailTemplatePicker: View {
    let selected: LetterTemplate.Key?
    let onPick: (LetterTemplate) -> Void

    @ScaledMetric(relativeTo: .body) private var artSize: CGFloat = 72
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let columns = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: PaeoniaSpacing.space12), count: columns),
            spacing: PaeoniaSpacing.space12
        ) {
            ForEach(LetterTemplate.all) { template in
                Button {
                    onPick(template)
                } label: {
                    VStack(spacing: PaeoniaSpacing.space8) {
                        Image(template.art)
                            .resizable()
                            .accessibilityHidden(true)
                            .scaledToFit()
                            .frame(width: artSize, height: artSize)
                        Text(template.name)
                            .font(PaeoniaTypography.bodyEmphasis)
                            .foregroundStyle(.paeoniaTextPrimary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(PaeoniaSpacing.space16)
                    .background(
                        RoundedRectangle(cornerRadius: PaeoniaRadius.standard, style: .continuous)
                            .fill(Color.paeoniaBackgroundSecondary)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: PaeoniaRadius.standard, style: .continuous)
                            .strokeBorder(selected == template.key ? Color.paeoniaAccentPrimary : .clear, lineWidth: 2)
                    )
                }
                .buttonStyle(.paeoniaPressableCard)
                .accessibilityAddTraits(selected == template.key ? .isSelected : [])
                .accessibilityIdentifier("mail.template.\(template.key.rawValue)")
            }
        }
    }
}

struct MailNoteEditor: View {
    @Binding var text: String
    let partnerName: String

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            TextEditor(text: $text)
                .focused($isFocused)
                .font(.system(.title3, design: .serif))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 220)
                .padding(PaeoniaSpacing.space12)
                .background(
                    RoundedRectangle(cornerRadius: PaeoniaRadius.standard, style: .continuous)
                        .fill(Color.paeoniaBackgroundSecondary)
                )
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(.mailComposerNotePlaceholder(partnerName))
                            .font(.system(.title3, design: .serif))
                            .foregroundStyle(.paeoniaTextTertiary)
                            .padding(PaeoniaSpacing.space20)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityLabel(Text(.mailComposerNotePlaceholder(partnerName)))
                .accessibilityIdentifier("mail.composer.note")
            let used = LetterBody.length(text)
            if used > LetterBody.maxLength - 200 {
                Text(.mailComposerNoteRemaining(LetterBody.maxLength - used))
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
        }
        .onAppear { isFocused = true }
    }
}

/// An optional photo, from Apple's photo picker, so the app never reads the photo library.
/// `photo` is already compressed, and decodes again only when it changes.
struct MailPhotoStep: View {
    let photo: Data?
    let isMissing: Bool
    let isPreparing: Bool
    let onPick: (Data?) async -> Void
    let onRemove: () -> Void

    @State private var item: PhotosPickerItem?
    @State private var image: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
            Text(.mailComposerPhotoOptional)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
            preview
            if photo != nil || isMissing {
                Button(role: .destructive) {
                    item = nil
                    onRemove()
                } label: {
                    Text(.mailComposerPhotoRemove)
                }
                .buttonStyle(PaeoniaSecondaryButtonStyle())
            }
            PhotosPicker(selection: $item, matching: .images) {
                Text(photo == nil ? .mailComposerPhotoChoose : .mailComposerPhotoChange)
            }
            .buttonStyle(PaeoniaSecondaryButtonStyle())
            .disabled(isPreparing)
            .accessibilityIdentifier("mail.composer.photo")
        }
        .task(id: item) {
            guard let item else { return }
            await onPick(try? await item.loadTransferable(type: Data.self))
        }
        .task(id: photo) {
            image = photo.flatMap(UIImage.init(data:))
        }
    }

    @ViewBuilder
    private var preview: some View {
        if isPreparing {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 120)
        } else if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.standard, style: .continuous))
                .accessibilityLabel(Text(.mailReaderPhoto))
        } else if isMissing {
            Text(.mailErrorPhotoMissing)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextPrimary)
        }
    }
}

/// When the letter arrives. Now, at the partner's next 08:00, when the two next meet, or at a
/// time the author picks.
struct MailDeliveryPicker: View {
    @Binding var delivery: LetterDelivery
    let partnerName: String
    /// Nil until the server answered. Until then the morning option names no time, and the
    /// option for the next meeting shows only when the draft already chose it.
    let options: MailDeliveryOptions?
    /// Why the options could not be read. Nil while they load or once they did.
    let optionsFailure: PaeoniaFailure?
    let retryOptions: () -> Void
    /// The saved time had passed and the composer moved it, so the picker says so.
    let movedPastTime: Bool

    @State private var setTime = Date.now.addingTimeInterval(3_600)
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let now = Date.now
        VStack(spacing: PaeoniaSpacing.space12) {
            option(.now, title: .mailDeliveryNowTitle, detail: String(localized: .mailDeliveryNowDetail(partnerName)))
            option(.morning, title: .mailDeliveryMorningTitle, detail: morningDetail(now: now))
            nextMeeting
            option(.at(setTime), title: .mailDeliveryAtTitle, detail: nil)
            if case let .at(date) = delivery {
                timePicker(now: now)
                if movedPastTime {
                    let when = date.formatted(.dateTime.weekday(.wide).day().month().hour().minute())
                    Text(.mailDeliveryAtMoved(when))
                        .font(PaeoniaTypography.body)
                        .foregroundStyle(.paeoniaAccentPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("mail.delivery.at.moved")
                }
            }
        }
        .onChange(of: delivery, initial: true) { _, delivery in
            if case let .at(date) = delivery { setTime = date }
        }
    }

    /// The label beside the date and time, or above them at the accessibility text sizes, where
    /// the date and the time each take a line so no word is broken.
    @ViewBuilder
    private func timePicker(now: Date) -> some View {
        let selection = Binding(get: { setTime }, set: {
            setTime = $0
            delivery = .at($0)
        })
        let range = now.addingTimeInterval(60)...now.addingTimeInterval(365 * 86_400)
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
                Text(.mailDeliveryAtLabel)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextPrimary)
                DatePicker(selection: selection, in: range, displayedComponents: .date) {
                    Text(.mailDeliveryAtLabel)
                }
                .labelsHidden()
                .accessibilityIdentifier("mail.delivery.at.picker")
                DatePicker(selection: selection, in: range, displayedComponents: .hourAndMinute) {
                    Text(.mailDeliveryAtLabel)
                }
                .labelsHidden()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            DatePicker(selection: selection, in: range) {
                Text(.mailDeliveryAtLabel)
            }
            .accessibilityIdentifier("mail.delivery.at.picker")
        }
    }

    /// The option, when the two can meet, or one line that says why it is missing.
    @ViewBuilder
    private var nextMeeting: some View {
        let meeting = options?.nextMeeting()
        if meeting?.offersLetter == true || (meeting == nil && delivery == .together) {
            option(.together, title: .mailDeliveryTogetherTitle, detail: meeting.map(meetingLine) ?? uncheckedLine)
            if meeting == nil, optionsFailure != nil {
                Button(action: retryOptions) {
                    Text(.mailDeliveryTogetherRetry)
                        .font(PaeoniaTypography.bodyEmphasis)
                        .foregroundStyle(.paeoniaAccentPrimary)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .padding(.horizontal, PaeoniaSpacing.space16)
                .accessibilityIdentifier("mail.delivery.together.retry")
            }
        } else if let meeting {
            Text(verbatim: meetingLine(meeting))
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, PaeoniaSpacing.space16)
                .accessibilityIdentifier("mail.delivery.together.missing")
        }
    }

    /// Why a draft that chose the next meeting can't be sent while the options are missing.
    private var uncheckedLine: String? {
        switch optionsFailure {
        case .offline: String(localized: .mailDeliveryTogetherUncheckedOffline)
        case .other: String(localized: .mailDeliveryTogetherUnchecked)
        case nil: nil
        }
    }

    private func meetingLine(_ meeting: MailDeliveryOptions.NextMeeting) -> String {
        switch meeting {
        case let .visit(start, byLocation):
            let day = start.formatted(.dateTime.weekday(.wide).day().month(.wide))
            return byLocation
                ? String(localized: .mailDeliveryTogetherVisitOrNear(partnerName, day))
                : String(localized: .mailDeliveryTogetherVisit(day))
        case .location:
            return String(localized: .mailDeliveryTogetherNear(partnerName))
        case .togetherNow:
            return String(localized: .mailDeliveryTogetherTogetherNow)
        case .visitTooSoon:
            return String(localized: .mailDeliveryTogetherTooSoon)
        case .unplanned:
            return String(localized: .mailDeliveryTogetherUnplanned)
        }
    }

    private func morningDetail(now: Date) -> String {
        guard let partnerTimeZone = options?.partnerTimeZoneID.flatMap(TimeZone.init(identifier:)) else {
            return String(localized: .mailDeliveryMorningDetailUnknownZone(partnerName))
        }
        let morning = LetterDelivery.nextMorning(after: now, in: partnerTimeZone)
        var style = Date.FormatStyle(date: .complete, time: .omitted)
        style.timeZone = partnerTimeZone
        let line = String(localized: .mailDeliveryMorningDetail(partnerName, morning.formatted(style)))
        guard partnerTimeZone.secondsFromGMT(for: morning) != TimeZone.current.secondsFromGMT(for: morning) else {
            return line
        }
        let yours = morning.formatted(.dateTime.weekday(.wide).hour().minute())
        return line + "\n" + String(localized: .mailDeliveryMorningYourTime(yours))
    }

    private func option(_ value: LetterDelivery, title: LocalizedStringResource, detail: String?) -> some View {
        let isSelected = value.kind == delivery.kind
        return Button {
            delivery = value
        } label: {
            HStack(alignment: .top, spacing: PaeoniaSpacing.space12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? .paeoniaAccentPrimary : .paeoniaTextTertiary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                    Text(title)
                        .font(PaeoniaTypography.bodyEmphasis)
                        .foregroundStyle(.paeoniaTextPrimary)
                    if let detail {
                        Text(verbatim: detail)
                            .font(PaeoniaTypography.body)
                            .foregroundStyle(.paeoniaTextSecondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(PaeoniaSpacing.space16)
            .background(
                RoundedRectangle(cornerRadius: PaeoniaRadius.standard, style: .continuous)
                    .fill(Color.paeoniaBackgroundSecondary)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("mail.delivery.\(value.kind.rawValue)")
    }
}
