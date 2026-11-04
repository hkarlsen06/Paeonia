import SwiftUI

extension View {
    /// "Tell [Name] you want to play" as the first item in the game's "•••" menu,
    /// for games with no room for `GameInviteButton` under their content. It shows
    /// only while the partner is not in the game. A tap asks first, then sends.
    /// After a send the item reads "Sent", and a banner says when the next invite
    /// can go. A tap on "Sent" says it again. The screen that holds the
    /// `GameMenu` applies `gameMenuInviteHost()` outside this.
    func gameMenuInvite(
        invite: GameInviteState,
        partnerName: String,
        send: @escaping () async -> Void,
        identifier: String = "game.invite"
    ) -> some View {
        modifier(GameMenuInviteModifier(invite: invite, partnerName: partnerName, send: send, identifier: identifier))
    }

    /// Hands the invite that a `gameMenuInvite` inside this view publishes to
    /// the `GameMenu` in this view's toolbar.
    func gameMenuInviteHost() -> some View {
        modifier(GameMenuInviteHost())
    }
}

/// The invite as the game's menu shows it.
struct GameMenuInvite: Equatable {
    /// When the next invite can go, once one is sent.
    let sentUntil: Date?
    let partnerName: String
    let identifier: String
    /// Asks before sending, or says again when the next invite can go.
    let tap: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.sentUntil == rhs.sentUntil && lhs.partnerName == rhs.partnerName && lhs.identifier == rhs.identifier
    }
}

extension EnvironmentValues {
    @Entry var gameMenuInviteItem: GameMenuInvite?
}

private struct GameMenuInviteKey: PreferenceKey {
    static var defaultValue: GameMenuInvite? { nil }

    static func reduce(value: inout GameMenuInvite?, nextValue: () -> GameMenuInvite?) {
        value = value ?? nextValue()
    }
}

private struct GameMenuInviteHost: ViewModifier {
    @State private var invite: GameMenuInvite?

    func body(content: Content) -> some View {
        content
            .environment(\.gameMenuInviteItem, invite)
            .onPreferenceChange(GameMenuInviteKey.self) { invite = $0 }
    }
}

private struct GameMenuInviteModifier: ViewModifier {
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
            .preference(key: GameMenuInviteKey.self, value: menuInvite)
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

    private var menuInvite: GameMenuInvite? {
        let sentUntil: Date? = if case let .sent(until) = invite { until } else { nil }
        guard invite != .hidden else { return nil }
        return GameMenuInvite(sentUntil: sentUntil, partnerName: partnerName, identifier: identifier) {
            if let sentUntil {
                showSent(until: sentUntil)
            } else {
                confirmsSend = true
            }
        }
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
