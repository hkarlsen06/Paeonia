import Foundation
import Testing
@testable import PaeoniaApp

/// How "Our stories" joins the pages it reads.
struct StoryChainHistoryListingTests {
    /// A listing of stories 12 down to 3: the first page, then one older page.
    private func scrolledListing() -> StoryChainHistoryListing {
        var listing = StoryChainHistoryListing()
        listing.refresh(with: storyChainHistoryPage([12, 11, 10, 9, 8], next: 8), pageSize: 5)
        listing.append(storyChainHistoryPage([7, 6, 5, 4, 3], next: 3))
        return listing
    }

    @Test func refreshingAfterScrollingKeepsTheOlderStories() {
        var listing = scrolledListing()
        #expect(listing.items.count == 10)

        // One story finished since: the new first page reaches the stories already here.
        listing.refresh(with: storyChainHistoryPage([13, 12, 11, 10, 9], next: 9), pageSize: 5)

        #expect(listing.items.map(\.storyNumber) == [13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3])
        #expect(listing.nextCursor == 3)
    }

    @Test func refreshingStartsOverWhenTheNewPageDoesNotReachTheOlderStories() {
        var listing = scrolledListing()

        // Many stories finished since, so there would be a gap.
        listing.refresh(with: storyChainHistoryPage([24, 23, 22, 21, 20], next: 20), pageSize: 5)

        #expect(listing.items.map(\.storyNumber) == [24, 23, 22, 21, 20])
        #expect(listing.nextCursor == 20)
    }

    @Test func aStoryNeverAppearsTwiceWhenPagesOverlap() {
        var listing = StoryChainHistoryListing()
        listing.refresh(with: storyChainHistoryPage([5, 4], next: 4), pageSize: 5)

        listing.append(storyChainHistoryPage([4, 3], next: nil))

        #expect(listing.items.map(\.storyNumber) == [5, 4, 3])
        #expect(!listing.hasMore)
    }
}
