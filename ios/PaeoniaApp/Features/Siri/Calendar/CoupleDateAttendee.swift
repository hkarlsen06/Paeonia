import AppIntents
import Foundation

/// The calendar schema's attendee. Every couple date is shared by both partners, so Paeonia
/// lists none and ignores attendees Siri passes in.
@AppEntity(schema: .calendar.attendee)
struct CoupleDateAttendee: TransientAppEntity {
    @available(iOS 27.3, *)
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    var person: IntentPerson
    var status: CoupleDateAttendeeStatus?
    var isAttendanceOptional: Bool
    var type: CoupleDateAttendeeType?

    var displayRepresentation: DisplayRepresentation {
        person.displayRepresentation
    }

    init() {}
}

@AppEnum(schema: .calendar.attendeeStatus)
enum CoupleDateAttendeeStatus: String {
    case accepted
    case declined
    case tentative

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .accepted: DisplayRepresentation(
            title: LocalizedStringResource(
                "siri.dates.attendee.accepted",
                table: "Localizable",
                comment: "Siri: a person said yes to a calendar event."
            )
        ),
        .declined: DisplayRepresentation(
            title: LocalizedStringResource(
                "siri.dates.attendee.declined",
                table: "Localizable",
                comment: "Siri: a person said no to a calendar event."
            )
        ),
        .tentative: DisplayRepresentation(
            title: LocalizedStringResource(
                "siri.dates.attendee.tentative",
                table: "Localizable",
                comment: "Siri: a person said maybe to a calendar event."
            )
        ),
    ]
}

@AppEnum(schema: .calendar.attendeeType)
enum CoupleDateAttendeeType: String {
    case person

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .person: DisplayRepresentation(
            title: LocalizedStringResource(
                "siri.dates.attendee.person",
                table: "Localizable",
                comment: "Siri: the kind of attendee of a calendar event, a person."
            )
        ),
    ]
}
