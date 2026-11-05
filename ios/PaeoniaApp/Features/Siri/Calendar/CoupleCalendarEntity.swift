import AppIntents
import CoreSpotlight
import Foundation

/// Paeonia's one calendar: the couple's countdowns and both partners' birthdays.
@AppEntity(schema: .calendar.calendar)
struct CoupleCalendarEntity: IndexedEntity, OwnershipProvidingEntity {
    @available(iOS 27.3, *)
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let defaultQuery = Query()

    static let shared = CoupleCalendarEntity()

    let id: String
    var title: String

    var ownership: EntityOwnership { .shared }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", image: .init(systemName: "calendar.badge.clock"))
    }

    private init() {
        id = "couple-dates"
        title = String(localized: .siriDatesCalendarTitle)
    }

    struct Query: EnumerableEntityQuery {
        func entities(for identifiers: [String]) async throws -> [CoupleCalendarEntity] {
            try await allEntities().filter { identifiers.contains($0.id) }
        }

        func allEntities() async throws -> [CoupleCalendarEntity] {
            await SiriAppContext.shared.access().couple == nil ? [] : [.shared]
        }

        func suggestedEntities() async throws -> [CoupleCalendarEntity] {
            try await allEntities()
        }
    }
}
