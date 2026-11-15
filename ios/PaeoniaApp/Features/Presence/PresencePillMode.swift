import SwiftUI

/// How the avatar is drawn, with the notice it shows or keeps for later.
nonisolated enum PresencePillMode: Equatable, Sendable {
    /// The partner's face in its corner, with a notice beside it for a moment.
    case avatar(notice: PresenceNotice?)
    /// The toolbar is open: Call, Message, and Join while the partner is in a game. A notice that
    /// arrives meanwhile waits until it closes.
    case expanded(pending: PresenceNotice?)
    /// Thrown past an edge, or put away while a sheet or cover is up. Only a small tab sticks out,
    /// with a dot while a notice waits.
    case tucked(edge: HorizontalEdge, pending: PresenceNotice?)

    /// The notice beside the avatar.
    var shownNotice: PresenceNotice? {
        if case let .avatar(notice) = self { notice } else { nil }
    }

    var isExpanded: Bool {
        if case .expanded = self { true } else { false }
    }

    /// The newest notice shows beside the avatar, or waits for the toolbar to close or the avatar
    /// to come back from the edge.
    func receiving(_ notice: PresenceNotice) -> Self {
        switch self {
        case .avatar: .avatar(notice: notice)
        case .expanded: .expanded(pending: notice)
        case let .tucked(edge, _): .tucked(edge: edge, pending: notice)
        }
    }

    /// A tap on the avatar opens the toolbar and puts the notice away, or closes the toolbar.
    var toggled: Self {
        switch self {
        case .avatar: .expanded(pending: nil)
        case .expanded, .tucked: collapsed
        }
    }

    /// The toolbar closes, and the notice that waited shows.
    var collapsed: Self {
        if case let .expanded(pending) = self { .avatar(notice: pending) } else { self }
    }

    func tucked(at edge: HorizontalEdge) -> Self {
        switch self {
        case .avatar: .tucked(edge: edge, pending: nil)
        case let .expanded(pending), let .tucked(_, pending): .tucked(edge: edge, pending: pending)
        }
    }

    /// Back from the edge, with the notice that waited.
    var untucked: Self {
        if case let .tucked(_, pending) = self { .avatar(notice: pending) } else { self }
    }

    var withoutNotice: Self {
        if case .avatar = self { .avatar(notice: nil) } else { self }
    }

    /// The same mode, without a notice that is no longer true.
    func keepingNotice(where isCurrent: (PresenceNotice) -> Bool) -> Self {
        func keep(_ notice: PresenceNotice?) -> PresenceNotice? {
            notice.flatMap { isCurrent($0) ? $0 : nil }
        }
        switch self {
        case let .avatar(notice): return .avatar(notice: keep(notice))
        case let .expanded(pending): return .expanded(pending: keep(pending))
        case let .tucked(edge, pending): return .tucked(edge: edge, pending: keep(pending))
        }
    }

    /// The partner left. Their notices go with them, and a tucked avatar stays tucked.
    var partnerLeft: Self {
        switch self {
        case .avatar, .expanded: .avatar(notice: nil)
        case let .tucked(edge, _): .tucked(edge: edge, pending: nil)
        }
    }
}

/// The avatar as the person left it, and whether a sheet or cover over the app puts it away for a
/// while. A sheet's or cover's own controls sit where the avatar would, and its preferences can't
/// reach the overlay window to move it, so the avatar shows as a tab at its side until the person
/// brings it out or the cover closes.
nonisolated struct PresencePill: Equatable, Sendable {
    nonisolated enum Cover: Equatable, Sendable {
        case none
        /// The avatar waits as a tab at this edge.
        case tucksAvatar(HorizontalEdge)
        /// The person brought the avatar out for this cover. The next one puts it away again.
        case broughtOut
    }

    /// The avatar as the person left it. It shows again when the covers close.
    private(set) var chosen: PresencePillMode
    private(set) var cover = Cover.none

    init(chosen: PresencePillMode) {
        self.chosen = chosen
    }

    /// How the avatar is drawn. A notice that arrives while a cover puts it away waits as the tab's
    /// dot, and shows when the avatar comes out or the cover closes.
    var mode: PresencePillMode {
        guard case let .tucksAvatar(edge) = cover else { return chosen }
        switch chosen {
        case let .avatar(notice), let .expanded(notice): return .tucked(edge: edge, pending: notice)
        case .tucked: return chosen
        }
    }

    func choosing(_ chosen: PresencePillMode) -> Self {
        var next = self
        next.chosen = chosen
        return next
    }

    /// A sheet or cover opened over the app. An open toolbar closes, and the avatar goes to `edge`.
    func covered(tuckingAt edge: HorizontalEdge) -> Self {
        guard cover == .none else { return self }
        var next = choosing(chosen.collapsed)
        next.cover = .tucksAvatar(edge)
        return next
    }

    var uncovered: Self {
        var next = self
        next.cover = .none
        return next
    }

    /// A tap on the tab brings the avatar back. Over a cover it stays out until that cover closes.
    var untucked: Self {
        var next = choosing(chosen.untucked)
        if case .tucksAvatar = cover { next.cover = .broughtOut }
        return next
    }
}
