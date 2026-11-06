import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct SearchViewModelTests {
    @Test func changingTheQueryDropsEarlierRemoteMatchesDuringTheNextReadAndItsFailure() async {
        let service = GatedSearchService()
        let model = SearchViewModel(service: service, pause: .zero)
        let story = Story(
            id: UUID(), authorUserID: UUID(), mediaAssetID: UUID(),
            caption: "Birthday dinner", createdAt: .now
        )
        await model.begin(query: "train") { SearchLocalContent(stories: [story]) }
        #expect(await waitFor { model.phase == .finished })
        #expect(model.results.byKind[.question]?.first?.title == "A train trip")

        model.query = "birthday"
        #expect(model.results.isEmpty)
        #expect(await waitFor { await service.isWaiting })
        #expect(model.results.byKind[.question] == nil)
        #expect(model.results.byKind[.story]?.first?.destination == .story(story.id))

        await service.failWaitingRead()
        #expect(await waitFor { model.phase == .finished })
        #expect(model.onlineProblem == .other)
        #expect(model.results.byKind[.question] == nil)
        #expect(model.results.byKind[.story]?.first?.destination == .story(story.id))
        model.end()
    }

    private func waitFor(_ condition: () async -> Bool) async -> Bool {
        for _ in 0..<200 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }
}

private actor GatedSearchService {
    private var continuation: CheckedContinuation<Void, any Error>?
    private(set) var isWaiting = false

    func search(_ query: SearchQuery, locale _: Locale) async throws -> RemoteSearchResponse {
        if query.words == ["birthday"] {
            isWaiting = true
            try await withCheckedThrowingContinuation { continuation = $0 }
        }
        return RemoteSearchResponse(
            questions: [.init(questionID: UUID(), prompt: "A train trip", topicTitle: nil, localDate: "2026-11-06")],
            answers: [], messages: [], storyChain: []
        )
    }

    func failWaitingRead() {
        continuation?.resume(throwing: URLError(.badServerResponse))
        continuation = nil
    }
}

extension GatedSearchService: SearchServing {}
