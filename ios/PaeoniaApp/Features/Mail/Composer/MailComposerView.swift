import PhotosUI
import SwiftUI

/// Writing a letter in four steps: pick a card, write the note, add a photo if you like, and
/// pick when it arrives. Every change is kept on the phone, so leaving or a failed send loses nothing.
struct MailComposerView: View {
    enum Step: Int, CaseIterable {
        case template
        case note
        case photo
        case delivery
    }

    let mail: MailViewModel
    let partnerName: String
    let onSent: () -> Void

    @State private var step: Step
    @State private var isConfirmingDiscard = false
    @Environment(\.dismiss) private var dismiss

    init(mail: MailViewModel, partnerName: String, onSent: @escaping () -> Void) {
        self.mail = mail
        self.partnerName = partnerName
        self.onSent = onSent
        _step = State(initialValue: mail.draft == nil ? .template : .note)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space20) {
                    Text(.mailComposerStep(step.rawValue + 1, Step.allCases.count))
                        .paeoniaEyebrowStyle(foreground: .paeoniaAccentPrimary)
                    Text(title)
                        .font(PaeoniaTypography.title)
                        .foregroundStyle(.paeoniaTextPrimary)
                        .accessibilityAddTraits(.isHeader)
                    content
                }
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                .padding(.vertical, PaeoniaSpacing.screenTopSpacing)
                .paeoniaReadableWidth(PaeoniaSpacing.readableContentWidth)
            }
            .scrollDismissesKeyboard(.interactively)
            if step != .template {
                actions
            }
        }
        .background(Color.paeoniaBackgroundPrimary)
        .navigationTitle(Text(.mailComposerTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if mail.draft != nil {
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        isConfirmingDiscard = true
                    } label: {
                        Text(.mailComposerDiscard)
                    }
                }
            }
        }
        .confirmationDialog(
            Text(.mailComposerDiscardTitle), isPresented: $isConfirmingDiscard, titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                mail.discardDraft()
                dismiss()
            } label: {
                Text(.mailComposerDiscard)
            }
        }
        .animation(.default, value: step)
    }

    private var title: LocalizedStringResource {
        switch step {
        case .template: .mailComposerTemplateTitle
        case .note: .mailComposerNoteTitle
        case .photo: .mailComposerPhotoTitle
        case .delivery: .mailComposerDeliveryTitle
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .template:
            MailTemplatePicker(selected: mail.draft?.content.templateKey) { template in
                mail.choose(template)
                step = .note
            }
        case .note:
            MailNoteEditor(
                text: Binding(get: { mail.draft?.content.body ?? "" }, set: { mail.updateBody($0) }),
                partnerName: partnerName
            )
        case .photo:
            MailPhotoStep(photo: mail.draftPhoto) { mail.updatePhoto($0) }
        case .delivery:
            MailDeliveryPicker(
                delivery: Binding(get: { mail.draft?.content.delivery ?? .now }, set: { mail.updateDelivery($0) }),
                partnerName: partnerName,
                partnerTimeZone: mail.partnerTimeZone ?? .current
            )
        }
    }

    private var actions: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            Button {
                step = Step(rawValue: step.rawValue - 1) ?? .template
            } label: {
                Text(.mailComposerBack)
            }
            .buttonStyle(PaeoniaSecondaryButtonStyle())
            .accessibilityIdentifier("mail.composer.back")
            if step == .delivery {
                Button {
                    Task {
                        if await mail.send() { onSent() }
                    }
                } label: {
                    Text(.mailComposerSend)
                }
                .buttonStyle(PaeoniaPrimaryButtonStyle(isLoading: mail.isSending))
                .disabled(mail.draft?.content.canSend != true)
                .accessibilityIdentifier("mail.composer.send")
            } else {
                Button {
                    step = Step(rawValue: step.rawValue + 1) ?? .delivery
                } label: {
                    Text(step == .photo && mail.draftPhoto == nil ? .mailComposerSkip : .mailComposerNext)
                }
                .buttonStyle(PaeoniaPrimaryButtonStyle())
                .disabled(step == .note && mail.draft?.content.canSend != true)
                .accessibilityIdentifier("mail.composer.next")
            }
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.vertical, PaeoniaSpacing.space12)
        .background(Color.paeoniaBackgroundPrimary)
    }
}
