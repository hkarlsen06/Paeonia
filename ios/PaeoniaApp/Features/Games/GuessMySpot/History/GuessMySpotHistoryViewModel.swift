import Foundation
import Observation
import UIKit

/// "Our guesses": every guessed round as a pin at its real spot, and each partner's
/// record as a guesser. It shows what the Guess my spot cache holds first, so the
/// screen opens offline, then reads the server.
@MainActor
@Observable
final class GuessMySpotHistoryViewModel {
    private(set) var rounds: [RemoteGuessMySpotRound] = []
    private(set) var records: RemoteGuessMySpotRecords?
    private(set) var playStyle: GamePlayStyle = .together
    private(set) var isLoading = true
    private(set) var loadFailure: PaeoniaFailure?
    private(set) var me: GamePlayer
    private(set) var partner: GamePlayer
    /// The drawn marks from the board games cache, nil until read or when not drawn.
    private(set) var myMark: UIImage?
    private(set) var partnerMark: UIImage?

    @ObservationIgnored let dependencies: GamesDependencies
    @ObservationIgnored private var participants: GameParticipants
    @ObservationIgnored private var hasReadCache = false
    @ObservationIgnored private var hasLoaded = false
    /// Rounds this person deleted that the server may not know about yet.
    @ObservationIgnored private var deleted: Set<UUID> = []
    @ObservationIgnored private var syncAfterLocalChange: (@MainActor @Sendable () async -> Void)?

    init(dependencies: GamesDependencies, participants: GameParticipants = GameParticipants()) {
        self.dependencies = dependencies
        self.participants = participants
        (me, partner) = participants.players
    }

    var currentUserID: UUID? {
        participants.currentUserID
    }

    var partnerName: String {
        partner.name
    }

    /// The pin of whoever sent or guessed: their color with their drawn mark, or their initial.
    func style(of userID: UUID) -> BoardPieceStyle {
        let isMine = userID == currentUserID
        return BoardPieceStyle(
            color: isMine ? .boardGameMine : .boardGamePartner,
            mark: isMine ? myMark : partnerMark,
            initial: BoardPieceStyle.initial(of: isMine ? me.name : partner.name)
        )
    }

    func configure(participants newParticipants: GameParticipants) {
        let identityChanged = participants.currentUserID != newParticipants.currentUserID
            || participants.coupleID != newParticipants.coupleID
        participants = newParticipants
        (me, partner) = newParticipants.players
        if identityChanged {
            rounds = []
            records = nil
            myMark = nil
            partnerMark = nil
            isLoading = true
            loadFailure = nil
            hasReadCache = false
            hasLoaded = false
        }
    }

    // MARK: - Reading

    func setLocalChangeSyncHandler(_ handler: (@MainActor @Sendable () async -> Void)?) {
        syncAfterLocalChange = handler
    }

    /// The score as the play style shows it, once records are here.
    var score: GuessMySpotScore? {
        records.map { GuessMySpotScore(records: $0, playStyle: playStyle) }
    }

    /// Shows the cache, then reads the server. A failed read keeps what is on screen.
    func load() async {
        guard let userID = currentUserID else { return }
        playStyle = await dependencies.cache.document(ownerUserID: userID).overview?.settings?.playStyle ?? .together
        await readDeletes(for: userID)
        await readCache(for: userID)
        await readMarks(for: userID)
        let ticket = await dependencies.guessMySpotCache.historyTicket()
        do {
            let history = try await dependencies.guessMySpotGateway.loadGuessMySpotHistory()
            guard !Task.isCancelled, currentUserID == userID else { return }
            apply(history)
            // Dropped when a purge, such as a sign-out, came after the read started.
            await dependencies.guessMySpotCache.saveHistory(history, ownerUserID: userID, ticket: ticket)
        } catch {
            guard !error.isCancellation, currentUserID == userID else { return }
            // The saved map again, so a refused delete comes back even offline.
            if hasLoaded, let cached = await dependencies.guessMySpotCache.document(ownerUserID: userID).history,
               currentUserID == userID {
                apply(cached)
            }
            loadFailure = rounds.isEmpty && !hasLoaded ? PaeoniaFailure(error) : nil
        }
        isLoading = false
    }

    /// A round's photo, from the shared media cache.
    func photo(of round: RemoteGuessMySpotRound) async -> UIImage? {
        guard let data = await dependencies.memoryPhotos?.imageData(for: round.photoMediaAssetID) else { return nil }
        return await MemoryImageDecoding.downsample(data, maxPixelSize: GuessMySpotViewModel.displayPixelSize)
    }

    private func readCache(for userID: UUID) async {
        guard !hasReadCache else { return }
        hasReadCache = true
        let history = await dependencies.guessMySpotCache.document(ownerUserID: userID).history
        guard currentUserID == userID, !hasLoaded, let history else { return }
        apply(history)
        isLoading = false
    }

    // MARK: - Deleting

    /// Deletes a round this person sent, for both partners. It leaves the map at once
    /// and goes to the server through the pending operations. Points stay.
    func delete(_ round: RemoteGuessMySpotRound) async -> Bool {
        guard round.canDelete == true, round.senderUserID == currentUserID, let userID = currentUserID,
              let data = try? JSONEncoder().encode(
                  GuessMySpotDeletePayload(roundID: round.id, createdAt: dependencies.now())
              )
        else { return false }
        do {
            try await dependencies.pendingOperationStore.enqueue(PendingSyncOperationRequest(
                ownerUserID: userID,
                operation: dependencies.operationProvider.makeOperation(),
                operationKind: .guessMySpotDeleteRound,
                idempotencyScope: "guess-my-spot-delete:\(round.id.uuidString.lowercased())",
                requestData: data
            ))
        } catch {
            return false
        }
        deleted.insert(round.id)
        rounds.removeAll { $0.id == round.id }
        if let sync = syncAfterLocalChange {
            Task { await sync() }
        }
        return true
    }

    private func readDeletes(for userID: UUID) async {
        deleted = await queuedDeletes(for: userID)
    }

    /// The rounds whose delete still waits in the pending operations.
    func queuedDeletes(for userID: UUID) async -> Set<UUID> {
        let queued = (try? await dependencies.pendingOperationStore.inFlightOperations(
            ownerUserID: userID,
            kind: .guessMySpotDeleteRound
        )) ?? []
        return Set(queued.compactMap { snapshot in
            snapshot.requestData.flatMap { try? JSONDecoder().decode(GuessMySpotDeletePayload.self, from: $0) }?.roundID
        })
    }

    /// Whether a delete hidden here has left the queue. The server then took it or
    /// refused it, and only a read shows which.
    var hasSettledDeletes: Bool {
        get async {
            guard let userID = currentUserID, !deleted.isEmpty else { return false }
            return await !deleted.isSubset(of: queuedDeletes(for: userID))
        }
    }

    private func apply(_ history: RemoteGuessMySpotHistory) {
        rounds = history.rounds.filter { $0.spot != nil && $0.guess != nil && !deleted.contains($0.id) }
        records = history.records
        hasLoaded = true
        loadFailure = nil
    }

    /// The marks both partners drew for the board games.
    private func readMarks(for userID: UUID) async {
        let marks = await dependencies.boardGamesCache.document(ownerUserID: userID).marks
        let mine = await Self.image(of: marks?.mine, key: "\(userID.uuidString):mine")
        let theirs = await Self.image(of: marks?.partner, key: "\(userID.uuidString):partner")
        guard currentUserID == userID else { return }
        myMark = mine
        partnerMark = theirs
    }

    /// `key` names the owner. The drawing's date makes a redrawn mark a new image.
    private static func image(of mark: RemoteBoardGameMark?, key: String) async -> UIImage? {
        guard let mark, let data = BoardMarkRenderer.data(fromBase64: mark.drawing) else { return nil }
        return await BoardMarkRenderer.image(from: data, cacheKey: "\(key):\(mark.updatedAt.timeIntervalSince1970)")
    }
}
