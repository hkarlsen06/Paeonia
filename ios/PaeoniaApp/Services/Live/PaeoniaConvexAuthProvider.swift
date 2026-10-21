import ClerkKit
@preconcurrency import ConvexMobile
import Foundation

nonisolated enum PaeoniaConvexAuthError: Error {
    case clerkNotLoaded
    case noActiveSession
    case noToken
    /// The Clerk session changed or signed out while the token was on its way.
    case sessionChanged
}

/// Signs the live socket in with a token from Clerk's `convex` JWT template, which lasts
/// 15 minutes.
///
/// Every new token makes Convex re-run all of the phone's subscribed queries. Clerk's
/// session token lasts 60 seconds, so with it every open app re-ran all of its live
/// queries about every 50 seconds. This provider fetches a template token a minute
/// before the current one expires, so that happens about every 14 minutes instead.
/// `scripts/deploy-backend` creates the template on every deploy, through
/// `scripts/ensure-clerk-jwt-template`, with the claim `"aud": "convex"` that
/// `backend/convex/auth.config.ts` expects.
///
/// It follows the Clerk session: a new active session logs the client in, and a removed
/// session logs it out. Clerk's clerk-convex-swift package did this before, with the
/// session token.
/// `logout()` signs out of Clerk, so never call `logout()` on the client.
@MainActor
final class PaeoniaConvexAuthProvider: ConvexMobile.AuthProvider {
    static let tokenTemplate = "convex"

    private var onIdToken: (@Sendable (String?) -> Void)?
    /// Changes with every logout. A token fetched before a logout, or for a session
    /// that is no longer Clerk's current one, is thrown away, so a slow fetch can never
    /// sign the socket in as the previous account or back in after a logout. Two
    /// logins for the same session may overlap and both succeed.
    private var generation: UInt64 = 0
    private var refreshTask: Task<Void, Never>?
    private var sessionSyncTask: Task<Void, Never>?
    private weak var client: ConvexClientWithAuth<String>?

    /// Starts following the Clerk session. Call once, right after creating the client.
    func bind(client: ConvexClientWithAuth<String>) {
        self.client = client
        startSessionSync()
    }

    func login(onIdToken: @Sendable @escaping (String?) -> Void) async throws -> String {
        try await authenticate(onIdToken: onIdToken)
    }

    func loginFromCache(onIdToken: @Sendable @escaping (String?) -> Void) async throws -> String {
        try await authenticate(onIdToken: onIdToken)
    }

    func logout() async throws {
        generation &+= 1
        refreshTask?.cancel()
        refreshTask = nil
        onIdToken = nil
        try await Clerk.shared.auth.signOut()
    }

    nonisolated func extractIdToken(from authResult: String) -> String {
        authResult
    }

    private func authenticate(onIdToken: @Sendable @escaping (String?) -> Void) async throws -> String {
        let requestedGeneration = generation
        let session = try Self.activeSession()
        self.onIdToken = onIdToken
        let token = try await Self.fetchToken(for: session, skipCache: false)
        // A failed login is tried again by LiveConvexConnection, as the current account.
        guard isCurrent(requestedGeneration, sessionID: session.id) else {
            throw PaeoniaConvexAuthError.sessionChanged
        }
        scheduleRefresh(after: token, sessionID: session.id, generation: requestedGeneration)
        return token
    }

    /// Whether no logout happened since a fetch started, and Clerk still has the
    /// same active session.
    private func isCurrent(_ requestedGeneration: UInt64, sessionID: String) -> Bool {
        requestedGeneration == generation
            && Clerk.shared.session?.id == sessionID
            && Clerk.shared.session?.status == .active
    }

    private static func activeSession() throws -> Session {
        guard Clerk.shared.isLoaded else {
            throw PaeoniaConvexAuthError.clerkNotLoaded
        }
        guard let session = Clerk.shared.session, session.status == .active else {
            throw PaeoniaConvexAuthError.noActiveSession
        }
        return session
    }

    /// The cached template token while it has more than a minute left, otherwise a new one.
    private static func fetchToken(for session: Session, skipCache: Bool) async throws -> String {
        let options = Session.GetTokenOptions(
            template: tokenTemplate,
            expirationBuffer: ConvexTokenSchedule.refreshLead,
            skipCache: skipCache
        )
        guard let token = try await session.getToken(options) else {
            throw PaeoniaConvexAuthError.noToken
        }
        return token
    }

    /// Hands the socket a new token shortly before the current one expires. A failed
    /// fetch, for example offline, is tried again after `ConvexTokenSchedule.minimumDelay`.
    /// If the token runs out first, the socket drops its sign-in and
    /// `LiveConvexConnection` logs in again.
    private func scheduleRefresh(after token: String, sessionID: String, generation requestedGeneration: UInt64) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            var current = token
            while !Task.isCancelled {
                let delay = ConvexTokenSchedule.refreshDelay(forToken: current, now: .now)
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    return
                }
                guard let self, isCurrent(requestedGeneration, sessionID: sessionID),
                      let session = Clerk.shared.session
                else {
                    return
                }
                if let fresh = try? await Self.fetchToken(for: session, skipCache: true) {
                    guard !Task.isCancelled, isCurrent(requestedGeneration, sessionID: sessionID) else {
                        return
                    }
                    current = fresh
                    onIdToken?(fresh)
                }
            }
        }
    }

    private func startSessionSync() {
        sessionSyncTask?.cancel()
        sessionSyncTask = Task { [weak self] in
            await self?.syncSession(oldSession: nil, newSession: Clerk.shared.session)
            for await event in Clerk.shared.auth.events {
                guard !Task.isCancelled else {
                    break
                }
                if case let .sessionChanged(oldSession, newSession) = event {
                    await self?.syncSession(oldSession: oldSession, newSession: newSession)
                }
            }
        }
    }

    /// Logs in when a session becomes active or a different one takes over, and logs
    /// out when the session goes away.
    private func syncSession(oldSession: Session?, newSession: Session?) async {
        guard let client else {
            return
        }

        if newSession?.status == .active,
           oldSession?.status != .active || oldSession?.id != newSession?.id {
            _ = await client.loginFromCache()
        } else if oldSession?.id != nil, newSession == nil {
            generation &+= 1
            refreshTask?.cancel()
            refreshTask = nil
            await client.logout()
        }
    }
}
