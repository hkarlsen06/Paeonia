import Observation
import SwiftUI

/// Authored text stays separate from the drawing and never contains an automatic word or idea hint.
@MainActor
@Observable
final class GameDrawingDescriptionDraftModel {
    private(set) var text = ""
    private(set) var loadFailed = false
    private(set) var saveFailed = false
    private(set) var hasLoaded = false
    private var identity: Identity?
    private var store: (any GameDrawingStoring)?
    private var privacyToken: LocalPrivacyWriteGuard.Token?
    @ObservationIgnored var canEdit: @MainActor () -> Bool = { true }

    private struct Identity: Equatable {
        let owner: UUID
        let couple: UUID
        let round: UUID
    }

    var isTooLong: Bool { text.unicodeScalars.count > 10_000 }
    var canSend: Bool {
        hasLoaded && !loadFailed && !isTooLong && privacyToken.map(LocalPrivacyWriteGuard.shared.isCurrent) == true
    }

    func matches(owner: UUID, couple: UUID, round: UUID) -> Bool {
        identity == Identity(owner: owner, couple: couple, round: round)
    }

    func configure(store: any GameDrawingStoring, owner: UUID, couple: UUID, round: UUID,
                   privacyToken: LocalPrivacyWriteGuard.Token) {
        let next = Identity(owner: owner, couple: couple, round: round)
        guard identity != next else { return }
        identity = next
        self.store = store
        self.privacyToken = privacyToken
        text = ""
        hasLoaded = false
        saveFailed = false
        load()
    }

    func reset() {
        identity = nil
        privacyToken = nil
        text = ""
        hasLoaded = false
        loadFailed = false
        saveFailed = false
    }

    func load() {
        guard let identity, let store else { return }
        do {
            text = try store.draftDescription(ownerUserID: identity.owner, coupleID: identity.couple,
                                              roundID: identity.round) ?? ""
            hasLoaded = true
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }

    func update(_ value: String) {
        guard hasLoaded, !loadFailed, canEdit() else { return }
        text = value
        save()
    }

    func save() {
        guard let identity, let store, let privacyToken else { return }
        do {
            try store.saveDraftDescription(text, ownerUserID: identity.owner, coupleID: identity.couple,
                                            roundID: identity.round, privacyToken: privacyToken)
            saveFailed = false
        } catch {
            // Keep the typed text available for retry and for the durable send payload.
            saveFailed = true
        }
    }
}

struct GameDrawingDescriptionEditor: View {
    let model: GameDrawingDescriptionDraftModel
    var isGuessingGame = false
    var isLocked = false
    @State private var isPresented = false
    @AccessibilityPresentation(.media) private var showsMedia

    var body: some View {
        Group {
            // A successful retry must keep the sheet's presenter until the person closes it.
            if showsMedia || isPresented || model.loadFailed || model.isTooLong || model.saveFailed {
                Button(.mediaAccessibilityDrawingDescription) { isPresented = true }
                    .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
                    .disabled(isLocked)
                    .accessibilityIdentifier("game.drawing.description.open")
            }
        }
        .sheet(isPresented: $isPresented) {
            NavigationStack {
                Form {
                    if model.loadFailed {
                        Text(.mediaAccessibilityLoadFailed)
                            .accessibilityIdentifier("game.drawing.description.failure")
                        Button(.commonTryAgain, action: model.load)
                            .accessibilityIdentifier("game.drawing.description.retryLoading")
                    } else {
                        TextField(text: Binding(get: { model.text }, set: model.update), axis: .vertical) {
                            Text(.mediaAccessibilityDrawingDescription)
                        }
                        .lineLimit(4...12)
                        .disabled(isLocked)
                        .accessibilityIdentifier("game.drawing.description.text")
                        Text(isGuessingGame ? LocalizedStringResource.gamesDrawingDescriptionClueHint
                             : .gamesDrawingDescriptionPartHint)
                        if model.isTooLong { Text(.mediaAccessibilityTooLong).foregroundStyle(.paeoniaErrorText) }
                        if model.saveFailed {
                            Text(.mediaAccessibilitySaveFailed)
                            Button(.commonTryAgain, action: model.save)
                        }
                    }
                }
                .paeoniaGroupedList()
                .keyboardDoneToolbar()
                .navigationTitle(Text(.mediaAccessibilityDrawingDescription))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(.commonDone) { isPresented = false }
                            .accessibilityIdentifier("game.drawing.description.done")
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}
