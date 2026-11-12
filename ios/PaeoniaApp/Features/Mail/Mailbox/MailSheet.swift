import SwiftUI

struct MailPeople {
    let currentUserID: UUID?
    let partnerUserID: UUID?
    let partnerName: String
    /// After a report of a letter, which also leaves the relationship.
    var onReportedAndLeft: () -> Void = {}
}

extension View {
    /// Shows the Mail sheet while `mail.presentation` is set.
    func mailSheet(_ mail: MailViewModel, people: MailPeople) -> some View {
        modifier(MailSheetModifier(mail: mail, people: people))
    }

    /// Loads the signed-in person's letters, follows the cache for as long as the view lives,
    /// and keeps the couple current.
    func mailLifecycle(_ mail: MailViewModel, ownerUserID: UUID?, coupleID: UUID?) -> some View {
        task(id: ownerUserID) {
            await mail.configure(ownerUserID: ownerUserID, coupleID: coupleID)
            await mail.observeStoreChanges()
        }
        .onChange(of: coupleID) { _, coupleID in
            Task { await mail.updateCoupleID(coupleID) }
        }
    }
}

private struct MailSheetModifier: ViewModifier {
    @Bindable var mail: MailViewModel
    let people: MailPeople

    func body(content: Content) -> some View {
        content.sheet(item: $mail.presentation) { _ in
            MailNavigation(mail: mail, people: people)
        }
    }
}

private struct MailNavigation: View {
    let mail: MailViewModel
    let people: MailPeople
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    var body: some View {
        NavigationStack(path: Binding(get: { mail.presentation?.path ?? [] }, set: { mail.presentation?.path = $0 })) {
            MailboxView(
                mail: mail,
                people: people,
                tab: Binding(get: { mail.presentation?.tab ?? .received }, set: { mail.presentation?.tab = $0 }),
                onOpen: { mail.presentation?.path.append($0) }
            )
            .navigationDestination(for: MailRoute.self) { route in
                switch route {
                case let .reader(letterID):
                    MailReaderView(
                        mail: mail,
                        people: people,
                        letterID: letterID,
                        onWriteBack: { mail.presentation?.path.append(.composer) },
                        onEdit: { mail.presentation?.path.append(.composer) }
                    )
                case .composer:
                    MailComposerView(mail: mail, partnerName: people.partnerName) {
                        mail.presentation?.tab = .sent
                        mail.presentation?.path.removeAll()
                    }
                }
            }
        }
        .paeoniaBanner(bannerCenter)
        .mailNotices(mail, bannerCenter: bannerCenter)
    }
}

extension View {
    /// Shows `mail`'s notices in `bannerCenter`, the one waiting from before too.
    func mailNotices(
        _ mail: MailViewModel, bannerCenter: PaeoniaBannerCenter, when isShowing: Bool = true
    ) -> some View {
        onChange(of: isShowing ? mail.notice?.id : nil, initial: true) { _, id in
            guard let id, let error = mail.takeNotice(id) else { return }
            // The letter went, and the composer clears error banners when one goes, so this
            // one is not an error. It stays until the person has read it.
            if error.isNews {
                bannerCenter.show(.info(message: error.message, timing: .untilDismissed))
            } else {
                bannerCenter.show(.error(message: error.message))
            }
        }
    }
}
