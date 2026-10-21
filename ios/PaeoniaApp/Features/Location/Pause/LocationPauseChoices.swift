import SwiftUI

extension LocationPauseOption {
    var title: LocalizedStringResource {
        switch self {
        case .oneHour:
            .settingsLocationPauseOneHour
        case .fourHours:
            .settingsLocationPauseFourHours
        case .untilMorning:
            .settingsLocationPauseUntilMorning
        }
    }
}

/// The pause lengths as buttons. The map card shows them in a menu and Location
/// settings shows them in a dialog. Both get the same choices and the same end times.
struct LocationPauseChoices: View {
    let onChoose: (Date) -> Void

    var body: some View {
        ForEach(LocationPauseOption.allCases) { option in
            Button {
                onChoose(option.end(from: Date()))
            } label: {
                Text(option.title)
            }
        }
    }
}
