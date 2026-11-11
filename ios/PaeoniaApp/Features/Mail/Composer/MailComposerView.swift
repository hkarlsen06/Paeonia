import PhotosUI
import SwiftUI

/// Writing a letter in four steps. Pick a card, write the note, add a photo if you like, and
/// pick when it arrives. Every change is kept on the phone, so leaving or a failed send loses
/// nothing. Nothing can change while the letter is sending.
struct MailComposerView: View {
    typealias Step = LetterComposerStep

    let mail: MailViewModel
    let partnerName: String
    let onSent: () -> Void

    @State private var step: Step
    @State private var isConfirmingDiscard = false
    @Environment(\.dismiss) private var dismiss
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(mail: MailViewModel, partnerName: String, onSent: @escaping () -> Void) {
        self.mail = mail
        self.partnerName = partnerName
        self.onSent = onSent
        _step = State(initialValue: mail.composer.draft?.step ?? .template)
    }

    private var composer: LetterComposer { mail.composer }

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
                        .disabled(composer.isSending)
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
            if composer.draft != nil {
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        isConfirmingDiscard = true
                    } label: {
                        Text(.mailComposerDiscard)
                    }
                    .disabled(composer.isSending)
                }
            }
        }
        .confirmationDialog(
            Text(.mailComposerDiscardTitle), isPresented: $isConfirmingDiscard, titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                composer.discard()
                dismiss()
            } label: {
                Text(.mailComposerDiscard)
            }
        }
        .navigationBarBackButtonHidden(composer.isSending)
        // The letter reached the server, from this send or one whose answer was lost.
        .onChange(of: composer.sentLetterID) {
            if bannerCenter.content?.style == .error { bannerCenter.dismiss() }
            onSent()
        }
        .animation(.default, value: step)
        .onChange(of: step) { composer.updateStep(step) }
        // The stored draft can arrive after this screen, as when Mail opens while the app starts.
        .onChange(of: composer.draft == nil) { _, hasNoDraft in
            if !hasNoDraft, step == .template, let saved = composer.draft?.step { step = saved }
        }
        .task { await mail.loadPartnerTimeZone() }
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
            MailTemplatePicker(selected: composer.draft?.content.templateKey) { template in
                composer.choose(template)
                step = .note
            }
        case .note:
            MailNoteEditor(
                text: Binding(get: { composer.draft?.content.body ?? "" }, set: { composer.updateBody($0) }),
                partnerName: partnerName
            )
        case .photo:
            MailPhotoStep(
                photo: composer.photo,
                isMissing: composer.isPhotoMissing,
                isPreparing: composer.isPreparingPhoto,
                onPick: { await mail.pickPhoto($0) },
                onRemove: composer.removePhoto
            )
        case .delivery:
            MailDeliveryPicker(
                delivery: Binding(
                    get: { composer.draft?.content.delivery ?? .now },
                    set: { composer.updateDelivery($0) }
                ),
                partnerName: partnerName,
                partnerTimeZone: mail.partnerTimeZone,
                movedPastTime: composer.movedPastTime
            )
            .onAppear { composer.moveTimeIfPassed() }
        }
    }

    /// Side by side, or stacked at the accessibility text sizes so neither label is cut off.
    private var actions: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: PaeoniaSpacing.space12))
            : AnyLayout(HStackLayout(spacing: PaeoniaSpacing.space12))
        return layout {
            Button {
                step = Step(rawValue: step.rawValue - 1) ?? .template
            } label: {
                Text(.mailComposerBack)
            }
            .buttonStyle(PaeoniaSecondaryButtonStyle())
            .disabled(composer.isSending)
            .accessibilityIdentifier("mail.composer.back")
            forward
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.vertical, PaeoniaSpacing.space12)
        .background(Color.paeoniaBackgroundPrimary)
    }

    /// Send on the last step, Next or Skip before it.
    @ViewBuilder
    private var forward: some View {
        if step == .delivery {
            Button {
                Task { await mail.send() }
            } label: {
                Text(.mailComposerSend)
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle(isLoading: composer.isSending))
            .disabled(composer.draft?.content.canSend != true || composer.isSending)
            .accessibilityIdentifier("mail.composer.send")
        } else {
            Button {
                step = Step(rawValue: step.rawValue + 1) ?? .delivery
            } label: {
                Text(step == .photo && composer.draft?.content.photo == nil ? .mailComposerSkip : .mailComposerNext)
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())
            .disabled(
                (step == .note && composer.draft?.content.canSend != true)
                    || (step == .photo && (composer.isPhotoMissing || composer.isPreparingPhoto))
            )
            .accessibilityIdentifier("mail.composer.next")
        }
    }
}
