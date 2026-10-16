#if WIDGET_EXTENSION
import SwiftUI
import WidgetKit

struct DailyQuestionLockScreenView: View {
    let entry: LockScreenEntry

    private var state: LockScreenQuestionState? {
        entry.snapshot.flatMap { LockScreenQuestionState($0, at: entry.date) }
    }

    var body: some View {
        if let state {
            VStack(alignment: .leading, spacing: 2) {
                Label { Text(.widgetLockScreenQuestionName) } icon: { Image(systemName: "bubble.left.fill") }
                    .font(.caption.weight(.semibold))
                    .widgetAccentable()
                Text(stateText(state))
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            LockScreenUnavailableView(symbol: "bubble.left", title: .widgetLockScreenQuestionName)
        }
    }

    private func stateText(_ state: LockScreenQuestionState) -> String {
        let name = partnerName
        return switch state {
        case .waiting: String(localized: .widgetLockScreenQuestionWaiting)
        case .partnerAnswered: String(localized: .widgetLockScreenQuestionPartnerAnswered(name))
        case .waitingForPartner: String(localized: .widgetLockScreenQuestionWaitingForPartner(name))
        case .bothAnswered: String(localized: .widgetLockScreenQuestionBothAnswered)
        }
    }

    private var partnerName: String {
        let name = entry.snapshot?.partner?.displayName?.split(separator: " ").first.map(String.init)
        return name ?? String(localized: .widgetLockScreenPartnerFallback)
    }
}
#endif
