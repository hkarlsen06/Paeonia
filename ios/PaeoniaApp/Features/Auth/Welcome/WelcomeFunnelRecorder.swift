import Foundation

/// A signed-out welcome step that is counted. The raw values are the server's step names
/// (`onboarding:record_welcome_step`).
nonisolated enum WelcomeFunnelStep: String, CaseIterable, Sendable {
    case welcomeShown = "welcome_shown"
    case startChosen = "start_chosen"
    case joinerChosen = "joiner_chosen"
    case returningChosen = "returning_chosen"
    case dateSaved = "date_saved"
    case dateSkipped = "date_skipped"
    case drawingSent = "drawing_sent"
    case drawingSkipped = "drawing_skipped"
    case signInShown = "sign_in_shown"
    case signedIn = "signed_in"
}

nonisolated protocol WelcomeFunnelRecording: Sendable {
    /// Counts `step` once for this install. Returns at once and never fails.
    func record(_ step: WelcomeFunnelStep)
}

/// Counts how many installs reach each signed-out welcome step, with nothing that tells
/// people or phones apart. A request carries only the step's name: no session token, even
/// when one exists, no install or user id, and no cookies. The server adds one to that
/// day's count for the step.
///
/// Each step goes out at most once per install. The steps already sent are remembered in
/// `UserDefaults`, which never leaves the phone. A send that fails stays queued and goes
/// out with the next step. It does not go through PostHog.
actor WelcomeFunnelRecorder: WelcomeFunnelRecording {
    static let shared = WelcomeFunnelRecorder(
        deploymentURL: try? PaeoniaConvexClientProvider.deploymentURL(in: .main)
    )

    private let deploymentURL: URL?
    private let defaults: UserDefaults
    private let session: URLSession
    private let queuedKey = "paeonia.welcomeFunnel.queued"
    private let sentKey = "paeonia.welcomeFunnel.sent"
    private var isSending = false

    init(
        deploymentURL: URL?,
        defaults: UserDefaults = .standard,
        session: URLSession = URLSession(configuration: .ephemeral)
    ) {
        self.deploymentURL = deploymentURL
        self.defaults = defaults
        self.session = session
    }

    nonisolated func record(_ step: WelcomeFunnelStep) {
        Task { await queueAndSend(step) }
    }

    private func queueAndSend(_ step: WelcomeFunnelStep) async {
        var queued = steps(forKey: queuedKey)
        if !steps(forKey: sentKey).contains(step), !queued.contains(step) {
            queued.insert(step)
            save(queued, forKey: queuedKey)
        }
        await sendQueued()
    }

    /// Sends the queued steps one at a time, and stops at the first failure.
    private func sendQueued() async {
        guard !isSending, let deploymentURL else {
            return
        }
        isSending = true
        defer { isSending = false }
        while let step = WelcomeFunnelStep.allCases.first(where: steps(forKey: queuedKey).contains) {
            guard await send(step, to: deploymentURL) else {
                return
            }
            var sent = steps(forKey: sentKey)
            sent.insert(step)
            save(sent, forKey: sentKey)
            var queued = steps(forKey: queuedKey)
            queued.remove(step)
            save(queued, forKey: queuedKey)
        }
    }

    private func send(_ step: WelcomeFunnelStep, to deploymentURL: URL) async -> Bool {
        var request = URLRequest(url: deploymentURL.appending(path: "api/mutation"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(
            RequestBody(path: "onboarding:record_welcome_step", args: ["p_step": step.rawValue], format: "json")
        )
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let envelope = try? JSONDecoder().decode(ResponseEnvelope.self, from: data)
        else {
            return false
        }
        return envelope.status == "success"
    }

    private func steps(forKey key: String) -> Set<WelcomeFunnelStep> {
        Set((defaults.stringArray(forKey: key) ?? []).compactMap(WelcomeFunnelStep.init(rawValue:)))
    }

    private func save(_ steps: Set<WelcomeFunnelStep>, forKey key: String) {
        defaults.set(steps.map(\.rawValue).sorted(), forKey: key)
    }

    nonisolated private struct RequestBody: Encodable {
        let path: String
        let args: [String: String]
        let format: String
    }

    nonisolated private struct ResponseEnvelope: Decodable {
        let status: String
    }
}

/// Counts nothing. For developer scenarios and previews.
nonisolated struct NoOpWelcomeFunnelRecorder: WelcomeFunnelRecording {
    func record(_: WelcomeFunnelStep) {}
}
