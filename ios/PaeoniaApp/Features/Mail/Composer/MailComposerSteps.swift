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
            if text.count > Letter.maxBodyLength - 200 {
                Text(.mailComposerNoteRemaining(Letter.maxBodyLength - text.count))
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
        }
        .onAppear { isFocused = true }
    }
}

/// An optional photo, from Apple's photo picker, so the app never reads the photo library.
struct MailPhotoStep: View {
    let photo: Data?
    let onChange: (Data?) -> Void

    @State private var item: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
            Text(.mailComposerPhotoOptional)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
            if let photo, let image = UIImage(data: photo) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.standard, style: .continuous))
                    .accessibilityLabel(Text(.mailReaderPhoto))
                Button(role: .destructive) {
                    item = nil
                    onChange(nil)
                } label: {
                    Text(.mailComposerPhotoRemove)
                }
                .buttonStyle(PaeoniaSecondaryButtonStyle())
            }
            PhotosPicker(selection: $item, matching: .images) {
                Text(photo == nil ? .mailComposerPhotoChoose : .mailComposerPhotoChange)
            }
            .buttonStyle(PaeoniaSecondaryButtonStyle())
            .accessibilityIdentifier("mail.composer.photo")
        }
        .task(id: item) {
            guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
            onChange(data)
        }
    }
}

/// When the letter arrives: now, at the partner's next 08:00, or at a time the author picks.
struct MailDeliveryPicker: View {
    @Binding var delivery: LetterDelivery
    let partnerName: String
    let partnerTimeZone: TimeZone

    @State private var setTime = Date.now.addingTimeInterval(3_600)

    var body: some View {
        let now = Date.now
        let morning = LetterDelivery.nextMorning(after: now, in: partnerTimeZone)
        VStack(spacing: PaeoniaSpacing.space12) {
            option(.now, title: .mailDeliveryNowTitle, detail: String(localized: .mailDeliveryNowDetail(partnerName)))
            option(.morning, title: .mailDeliveryMorningTitle, detail: morningDetail(morning))
            option(.at(setTime), title: .mailDeliveryAtTitle, detail: nil)
            if case .at = delivery {
                DatePicker(
                    selection: Binding(get: { setTime }, set: {
                        setTime = $0
                        delivery = .at($0)
                    }),
                    in: now.addingTimeInterval(60)...now.addingTimeInterval(365 * 86_400)
                ) {
                    Text(.mailDeliveryAtLabel)
                }
                .accessibilityIdentifier("mail.delivery.at.picker")
            }
        }
        .onAppear {
            if case let .at(date) = delivery { setTime = date }
        }
    }

    private func morningDetail(_ morning: Date) -> String {
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
