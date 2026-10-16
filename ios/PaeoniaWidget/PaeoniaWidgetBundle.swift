import WidgetKit
import SwiftUI

@main
struct PaeoniaWidgetBundle: WidgetBundle {
    var body: some Widget {
        PaeoniaWidget()
        DaysTogetherLockScreenWidget()
        NextCountdownLockScreenWidget()
        TheirTimeLockScreenWidget()
        DistanceLockScreenWidget()
        StreakLockScreenWidget()
        DailyQuestionLockScreenWidget()
        YourMoveLockScreenWidget()
    }
}
