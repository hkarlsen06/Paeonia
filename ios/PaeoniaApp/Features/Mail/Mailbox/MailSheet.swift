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
            mail.updateCoupleID(coupleID)
        }
    }
}

private struct MailSheetModifier: ViewModifier {
    @Bindable var mail: MailViewModel
    let people: MailPeople

    func body(content: Content) -> some View {
        content.sheet(item: $mail.presentation) { presentation in
            MailNavigation(mail: mail, people: people, presentation: presentation)
        }
    }
}

private struct MailNavigation: View {
    let mail: MailViewModel
    let people: MailPeople
    @State private var path: [MailRoute]
    @State private var tab: MailboxTab
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    init(mail: MailViewModel, people: MailPeople, presentation: MailPresentation) {
        self.mail = mail
        self.people = people
        _path = State(initialValue: presentation.path)
        _tab = State(initialValue: presentation.tab)
    }

    var body: some View {
        NavigationStack(path: $path) {
            MailboxView(mail: mail, people: people, tab: $tab, onOpen: { path.append($0) })
                .navigationDestination(for: MailRoute.self) { route in
                    switch route {
                    case let .reader(letterID):
                        MailReaderView(
                            mail: mail,
                            people: people,
                            letterID: letterID,
                            onWriteBack: { path.append(.composer) }
                        )
                    case .composer:
                        MailComposerView(mail: mail, partnerName: people.partnerName) {
                            tab = .sent
                            path.removeAll()
                        }
                    }
                }
        }
        .paeoniaBanner(bannerCenter)
        .onChange(of: mail.error) { _, error in
            guard let error else { return }
            bannerCenter.show(.error(message: error.message))
            mail.clearError()
        }
    }
}
