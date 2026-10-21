import SwiftUI

/// What the viewer shows under a story for reactions: the emoji row on the partner's story,
/// and what the partner reacted with on your own.
struct StoryReactionBar: View {
    let story: Story
    let people: StoryPeople

    var body: some View {
        if people.isOwn(story) {
            PartnerReactionLine(target: .story(story.id))
        } else {
            ReactionPickerRow(target: .story(story.id))
        }
    }
}
