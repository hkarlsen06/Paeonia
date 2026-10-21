import WidgetKit
import SwiftUI

@main
struct PaeoniaWidgetBundle: WidgetBundle {
    var body: some Widget {
        PaeoniaWidget()
        DaysTogetherHomeWidget()
        CountdownHomeWidget()
        StreakHomeWidget()
        DailyQuestionHomeWidget()
        DaysTogetherLockScreenWidget()
        NextCountdownLockScreenWidget()
        TheirTimeLockScreenWidget()
        DistanceLockScreenWidget()
        StreakLockScreenWidget()
        DailyQuestionLockScreenWidget()
        YourMoveLockScreenWidget()
    }
}
