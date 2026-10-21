#if WIDGET_EXTENSION
import SwiftUI
import WidgetKit

/// Today's question on the Home Screen. It says who has answered and what to do
/// next. It never shows the question or an answer.
struct DailyQuestionHomeView: View {
    @Environment(\.widgetFamily) private var family

    let entry: LockScreenEntry

    private var state: LockScreenQuestionState? {
        entry.snapshot.flatMap { LockScreenQuestionState($0, at: entry.date) }
    }

    private var partnerName: String {
        entry.snapshot?.partnerFirstName ?? ""
    }

    var body: some View {
        if let state {
            content(state)
                .accessibilityElement(children: .combine)
                .widgetURL(LockScreenURL.dailyQuestion)
        } else {
            HomeWidgetUnavailableView(
                symbol: "bubble.left.and.bubble.right.fill",
                title: .widgetLockScreenQuestionName,
                message: .widgetPlaceholderAction
            )
        }
    }

    @ViewBuilder
    private func content(_ state: LockScreenQuestionState) -> some View {
        if family == .systemSmall {
            status(state)
        } else {
            HStack(alignment: .top, spacing: 14) {
                status(state)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                people(state)
                    .frame(width: 112)
            }
        }
    }

    private func status(_ state: LockScreenQuestionState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HomeWidgetHeader(
                symbol: "bubble.left.and.bubble.right.fill",
                title: Text(.widgetLockScreenQuestionName)
            )
            Text(state.text(partnerName: partnerName))
                .font(family == .systemSmall ? .subheadline.weight(.semibold) : .title3.weight(.semibold))
                .foregroundStyle(.paeoniaWidgetTextPrimary)
                .lineLimit(4)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            if let action = action(state) {
                HomeWidgetActionPill(title: action)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Who has answered, for the medium size.
    private func people(_ state: LockScreenQuestionState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            person(name: String(localized: .widgetHomeQuestionYou), answered: state.meAnswered)
            person(name: partnerName, answered: state.partnerAnswered)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.paeoniaWidgetTextPrimary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private func person(name: String, answered: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: answered ? "checkmark.circle.fill" : "circle.dotted")
                .font(.body)
                .foregroundStyle(answered ? Color.paeoniaWidgetAccentPrimary : Color.paeoniaWidgetTextSecondary)
                .widgetAccentable(answered)
                .accessibilityHidden(true)
            Text(name)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.paeoniaWidgetTextPrimary)
                .lineLimit(1)
        }
    }

    private func action(_ state: LockScreenQuestionState) -> LocalizedStringResource? {
        switch state {
        case .waiting, .partnerAnswered: .widgetHomeQuestionAnswer
        case .bothAnswered: .widgetHomeQuestionSeeAnswers
        case .waitingForPartner: nil
        }
    }
}
#endif
