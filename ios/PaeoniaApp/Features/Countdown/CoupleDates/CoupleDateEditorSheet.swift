import SwiftUI

/// Which editor the milestones timeline has open.
enum CoupleDateEditor: Identifiable, Hashable {
    case newCountdown
    case countdown(UUID)
    case birthday(UUID)

    /// The editor for a tapped row. Milestones have none.
    init?(_ event: CoupleDateEvent) {
        switch event.kind {
        case .milestone:
            return nil
        case let .countdown(countdown):
            self = .countdown(countdown.id)
        case let .birthday(userID):
            self = .birthday(userID)
        }
    }

    var id: Self { self }
}

/// Opens the countdown or birthday editor and saves through `CoupleDatesViewModel`.
struct CoupleDateEditorSheet: View {
    let editor: CoupleDateEditor
    let coupleDates: CoupleDatesViewModel
    let names: CoupleDateNames

    var body: some View {
        switch editor {
        case .newCountdown:
            CountdownEditorView(countdown: nil) { title, day in
                await coupleDates.saveCountdown(id: nil, title: title, on: day)
            }
        case let .countdown(id):
            let countdown = coupleDates.dates.countdowns.first { $0.id == id }
            CountdownEditorView(
                countdown: countdown,
                onSave: { title, day in
                    await coupleDates.saveCountdown(id: id, title: title, on: day)
                },
                onDelete: {
                    await coupleDates.deleteCountdown(id: id)
                }
            )
        case let .birthday(userID):
            BirthdayEditorView(
                title: CoupleDateNames.birthdayTitle(for: userID, names: names),
                isOwnBirthday: userID == names.currentUserID,
                partnerName: names.partnerName,
                birthday: coupleDates.dates.birthdays[userID]
                    .flatMap { try? PairingStartDate(rawValue: $0) }?
                    .date(),
                onSave: { day in
                    await coupleDates.setBirthday(day, for: userID)
                }
            )
        }
    }
}
