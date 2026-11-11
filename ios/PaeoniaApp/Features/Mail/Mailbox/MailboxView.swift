import SwiftUI

/// The letters this person received and the ones they sent. A letter they sent that has not
/// arrived yet says when it will.
struct MailboxView: View {
    let mail: MailViewModel
    let people: MailPeople
    @Binding var tab: MailboxTab
    let onOpen: (MailRoute) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var letterToDelete: Letter?

    var body: some View {
        let page = mail.list(tab)
        let letters = page.letters
        List {
            Section {
                Picker(selection: $tab) {
                    Text(.mailMailboxReceived).tag(MailboxTab.received)
                    Text(.mailMailboxSent).tag(MailboxTab.sent)
                } label: {
                    Text(.mailMailboxTitle)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            if letters.isEmpty {
                emptyState
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(letters, content: row)
                    if page.nextBefore != nil {
                        olderButton
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.paeoniaBackgroundPrimary)
        .navigationTitle(Text(.mailMailboxTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Text(.mailDone)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    onOpen(.composer)
                } label: {
                    Label {
                        Text(.mailCardWrite)
                    } icon: {
                        Image(systemName: "square.and.pencil")
                    }
                }
                .accessibilityIdentifier("mail.mailbox.write")
            }
        }
        .task(id: tab) {
            // The Sent list shows that the partner opened a letter, so its push has been seen.
            if tab == .sent { await DeliveredNotifications.clear(types: ["letter_opened"]) }
        }
        .confirmationDialog(
            Text(letterToDelete?.state == .sealed ? .mailDeleteSealedTitle : .mailDeleteTitle),
            isPresented: Binding(get: { letterToDelete != nil }, set: { if !$0 { letterToDelete = nil } }),
            titleVisibility: .visible,
            presenting: letterToDelete
        ) { letter in
            Button(role: .destructive) {
                Task { _ = await mail.delete(letter) }
            } label: {
                Text(deleteTitle(for: letter))
            }
        } message: { letter in
            Text(letter.state == .sealed ? .mailDeleteSealedMessage(people.partnerName) : .mailDeleteMessage)
        }
    }

    private func row(_ letter: Letter) -> some View {
        Button {
            onOpen(.reader(letter.id))
        } label: {
            MailboxRow(letter: letter, isSent: tab == .sent, partnerName: people.partnerName)
        }
        .accessibilityIdentifier("mail.mailbox.row")
        .listRowBackground(Color.paeoniaBackgroundSecondary)
        .swipeActions {
            if tab == .sent {
                Button(role: .destructive) {
                    letterToDelete = letter
                } label: {
                    Label(deleteTitle(for: letter), systemImage: "trash")
                }
            }
        }
    }

    private var olderButton: some View {
        Button {
            Task { await mail.loadOlder(tab) }
        } label: {
            HStack(spacing: PaeoniaSpacing.space8) {
                Text(.mailMailboxOlder)
                if mail.loadingOlder.contains(tab) {
                    ProgressView()
                }
            }
            .font(PaeoniaTypography.bodyEmphasis)
            .foregroundStyle(.paeoniaAccentPrimary)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .disabled(mail.loadingOlder.contains(tab))
        .listRowBackground(Color.clear)
        .accessibilityIdentifier("mail.mailbox.older")
    }

    private func deleteTitle(for letter: Letter) -> LocalizedStringResource {
        letter.state == .sealed ? .mailDeleteSealedAction : .mailDeleteAction
    }

    @ViewBuilder
    private var emptyState: some View {
        if tab == .sent {
            PaeoniaEmptyStateView(
                title: .mailMailboxEmptySentTitle,
                message: .mailMailboxEmptySentMessage(people.partnerName),
                illustration: .mailTemplateBlank
            ) {
                Button {
                    onOpen(.composer)
                } label: {
                    Text(.mailCardWrite)
                }
                .buttonStyle(PaeoniaPrimaryButtonStyle())
                .accessibilityIdentifier("mail.mailbox.empty.write")
            }
        } else {
            PaeoniaEmptyStateView(
                title: .mailMailboxEmptyReceivedTitle,
                message: .mailMailboxEmptyReceivedMessage(people.partnerName),
                illustration: .homeEnvelopeSealed
            ) {
                Button {
                    tab = .sent
                    onOpen(.composer)
                } label: {
                    Text(.mailCardWrite)
                }
                .buttonStyle(PaeoniaPrimaryButtonStyle())
            }
        }
    }
}

/// One letter in the mailbox: its card, its first line once it can be read, and where it is.
private struct MailboxRow: View {
    let letter: Letter
    let isSent: Bool
    let partnerName: String

    @ScaledMetric(relativeTo: .body) private var artWidth: CGFloat = 48
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: PaeoniaSpacing.space8))
            : AnyLayout(HStackLayout(spacing: PaeoniaSpacing.space12))
        let size = min(artWidth, 96)
        layout {
            Group {
                if let templateKey = letter.templateKey {
                    Image(LetterTemplate(templateKey).art)
                        .resizable()
                        .accessibilityHidden(true)
                        .scaledToFit()
                } else {
                    MailSealedEnvelope(width: size)
                }
            }
            .frame(width: size, height: size)
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                Text(headline)
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .lineLimit(2)
                Text(status)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(waitsForMe ? .paeoniaAccentPrimary : .paeoniaTextSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, PaeoniaSpacing.space4)
        .accessibilityElement(children: .combine)
    }

    private var waitsForMe: Bool {
        letter.state == .delivered && !isSent
    }

    private var headline: String {
        if let body = letter.body?.split(separator: "\n").first {
            return String(body)
        }
        return String(localized: .mailReaderFrom(partnerName))
    }

    private var status: String {
        if isSent {
            switch letter.state {
            case .sealed:
                let when = letter.deliverAt?.formatted(.dateTime.weekday(.wide).day().month().hour().minute()) ?? ""
                return String(localized: .mailStatusArrives(when))
            case .delivered:
                return String(localized: .mailStatusDelivered)
            case .opened:
                return String(localized: .mailStatusOpened(partnerName))
            }
        }
        return letter.state == .opened
            ? String(localized: .mailReaderFrom(partnerName))
            : String(localized: .mailStatusSealed)
    }
}
