import Foundation
import Observation

/// What the paywall's private topics switch needs from the server.
protocol PaywallPrivateTopicsGateway: Sendable {
    /// Whether the signed-in person said yes to answering private topics, and what
    /// those topics are called.
    func ownPrivateTopicsConsent() async throws -> OwnPrivateTopicsConsent
    func setPrivateTopicsConsent(_ consents: Bool, notice: String) async throws
}

nonisolated struct OwnPrivateTopicsConsent: Decodable, Equatable, Sendable {
    nonisolated struct Topic: Decodable, Equatable, Sendable {
        let titleEN: String
        let titleNB: String

        enum CodingKeys: String, CodingKey {
            case titleEN = "title_en"
            case titleNB = "title_nb"
        }
    }

    let consented: Bool
    let topics: [Topic]

    enum CodingKeys: String, CodingKey {
        case consented = "private_topics_consented"
        case topics
    }

    /// The private topics' names as one phrase, such as "Flirt".
    func name(locale: Locale = .current) -> String {
        let norwegian = locale.prefersNorwegianTopicCopy
        return ListFormatter.localizedString(byJoining: topics.map { norwegian ? $0.titleNB : $0.titleEN })
    }
}

/// The private topics switch (Flirt) on the paywall, where Privacy and safety is
/// out of reach. Someone whose subscription ended can still take back their yes,
/// which deletes their answers there. The paywall has no topic shelf, so this asks
/// the server whether the yes stands. Saying yes belongs to the topic itself, so
/// the switch only goes off here.
@Observable
final class PaywallPrivateTopicsModel {
    enum State: Equatable {
        case loading
        case loadFailed
        /// The person has given no yes, so there is nothing to take back.
        case notConsented
        case loaded(name: String, isOn: Bool)
    }

    private(set) var state = State.loading
    private(set) var isSaving = false
    /// Why the last try to take the yes back failed. The sheet shows it once.
    private(set) var failure: PaeoniaFailure?

    private let gateway: (any PaywallPrivateTopicsGateway)?

    init(gateway: (any PaywallPrivateTopicsGateway)?) {
        self.gateway = gateway
    }

    func load() async {
        guard !isSaving else {
            return
        }
        guard let gateway else {
            state = .loadFailed
            return
        }
        do {
            let consent = try await gateway.ownPrivateTopicsConsent()
            guard !isSaving else {
                return
            }
            state = consent.consented ? .loaded(name: consent.name(), isOn: true) : .notConsented
        } catch {
            if state == .loading {
                state = .loadFailed
            }
        }
    }

    /// Takes the yes back. Returns true once the server has deleted the answers.
    func turnOff() async -> Bool {
        guard let gateway, case let .loaded(name, true) = state, !isSaving else {
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await gateway.setPrivateTopicsConsent(false, notice: TopicsViewModel.privateTopicsNoticeVersion)
            state = .loaded(name: name, isOn: false)
            return true
        } catch {
            failure = PaeoniaFailure(error)
            return false
        }
    }

    func clearFailure() {
        failure = nil
    }
}

enum PaywallPrivateTopicsGatewayFactory {
    static func makeDefault() -> (any PaywallPrivateTopicsGateway)? {
        (try? PaeoniaConvexClientProvider.shared.client()).map { LiveTopicsGateway(client: $0) }
    }
}
