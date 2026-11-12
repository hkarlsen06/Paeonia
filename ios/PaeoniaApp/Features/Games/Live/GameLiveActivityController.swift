import ActivityKit

/// Ends this phone's activities about the partner's game once they stop helping. The server
/// ends them with a push, and these cover what a push cannot: the activity went stale because
/// its pushes stopped reaching the phone, or the sign-in it was for ended. The ones that return
/// ids end on the phone's own judgment, and `LiveActivityTokenService` tells the server about them.
enum GameLiveActivityController {
    /// The app came to the front. A stale or ended activity no longer says anything true about
    /// the partner. Returns the server ids of the activities it ended.
    static func endStaleActivities() async -> [String] {
        await end { $0.activityState == .stale || $0.content.state.phase == .ended }
    }

    /// The server will not keep the activity with ActivityKit id `id` up to date.
    static func end(activityWithID id: String) async {
        _ = await end { $0.id == id }
    }

    /// Nobody is signed in for these activities anymore, or the relationship they show ended.
    static func endAll() async {
        _ = await end { _ in true }
    }

    private static func end(where matches: (Activity<GameLiveActivityAttributes>) -> Bool) async -> [String] {
        var ended: [String] = []
        for activity in Activity<GameLiveActivityAttributes>.activities where matches(activity) {
            await activity.end(nil, dismissalPolicy: .immediate)
            ended.append(activity.attributes.activityID)
        }
        return ended
    }
}
