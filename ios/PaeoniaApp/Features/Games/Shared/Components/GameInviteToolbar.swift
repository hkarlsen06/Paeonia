import SwiftUI

extension View {
    /// "Tell [Name] you want to play" as a bell in the leading toolbar, for games
    /// with no room for `GameInviteButton` under their content. It shows only while
    /// the partner is not in the game. A tap asks first, then sends. After a send
    /// the bell fills, and a banner says when the next invite can go. A tap on the
    /// filled bell says it again.
    func gameInviteToolbar(
        invite: GameInviteState,
        partnerName: String,
        send: @escaping () async -> Void,
        identifier: String = "game.invite"
    ) -> some View {
        modifier(GameInviteToolbar(invite: invite, partnerName: partnerName, send: send, identifier: identifier))
    }
}

private struct GameInviteToolbar: ViewModifier {
    let invite: GameInviteState
    let partnerName: String
    let send: () async -> Void
    let identifier: String

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    /// True from a confirmed send until the invite reads as sent.
    @State private var isSending = false
    @State private var confirmsSend = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                if invite != .hidden {
                    ToolbarItem(placement: .topBarLeading) {
                        bell
                    }
                }
            }
            .alert(Text(.gamesInviteConfirmTitle(partnerName)), isPresented: $confirmsSend) {
                Button(role: .cancel) {} label: {
                    Text(.commonCancel)
                }
                Button {
                    isSending = true
                    Task { await send() }
                } label: {
                    Text(.gamesInviteConfirmSend)
                }
                .accessibilityIdentifier("\(identifier).confirm")
            } message: {
                Text(.gamesInviteConfirmMessage(partnerName))
            }
            .onChange(of: invite) { _, invite in
                if isSending, case let .sent(until) = invite {
                    showSent(until: until)
                }
                if invite != .available { isSending = false }
            }
    }

    private var bell: some View {
        let sentUntil: Date? = if case let .sent(until) = invite { until } else { nil }
        return Button {
            PaeoniaHaptics.selection()
            if let sentUntil {
                showSent(until: sentUntil)
            } else {
                confirmsSend = true
            }
        } label: {
            Label {
                Text(sentUntil == nil ? .gamesInviteButton(partnerName) : .gamesInviteSent)
            } icon: {
                Image(systemName: sentUntil == nil ? "bell" : "bell.fill")
                    .symbolEffect(.bounce, value: sentUntil == nil)
            }
        }
        .accessibilityIdentifier(sentUntil == nil ? identifier : "\(identifier).sent")
    }

    private func showSent(until: Date) {
        bannerCenter.show(
            .info(
                message: String(localized: .gamesInviteSentBanner(partnerName, time(until))),
                systemImage: "bell.fill"
            )
        )
    }

    private func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
