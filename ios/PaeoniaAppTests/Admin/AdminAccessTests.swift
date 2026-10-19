import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct AdminAccessModelTests {
    @Test func showsTheRowOnlyWhenTheServerSaysAdmin() async {
        let admin = AdminAccessModel(gateway: AdminFakeGateway(isAdmin: true))
        let regular = AdminAccessModel(gateway: AdminFakeGateway(isAdmin: false))

        await admin.refresh()
        await regular.refresh()

        #expect(admin.isAdmin)
        #expect(!regular.isAdmin)
    }

    @Test func anyErrorHidesTheRow() async {
        let model = AdminAccessModel(gateway: AdminFakeGateway(error: AdminFakeError.failed))

        await model.refresh()

        #expect(!model.isAdmin)
    }
}

@MainActor
struct AdminFailureTests {
    @Test func readsTheServerErrors() {
        #expect(AdminFailure(AdminFixtures.serverError("admin access required")) == .notAdmin)
        #expect(AdminFailure(AdminFixtures.serverError("you can't ban yourself")) == .cannotBan)
        #expect(AdminFailure(AdminFixtures.serverError("admins can't be banned")) == .cannotBan)
        #expect(
            AdminFailure(AdminFixtures.serverError("ban reason must be 1 to 500 characters", code: "23514"))
                == .reasonInvalid
        )
        #expect(AdminFailure(AdminFixtures.serverError("user not found", code: "P0002")) == .userNotFound)
        #expect(AdminFailure(PaeoniaConvexError.notAuthenticated) == .other)
        #expect(AdminFailure(CancellationError()) == .cancelled)
        #expect(AdminFailure(URLError(.cancelled)) == .cancelled)
    }
}

@MainActor
struct AdminModelDecodingTests {
    @Test func decodesAUserRowWithTheServerKeys() throws {
        let json = """
        {"user_id": "11111111-1111-1111-1111-111111111111", "display_name": null,
         "auth_provider": "google", "created_at": "2026-03-01T10:00:00.000Z",
         "is_admin": false, "banned_at": "2026-03-02T10:00:00.000Z"}
        """

        let user = try PaeoniaConvexClient.decoder.decode(AdminUserSummary.self, from: Data(json.utf8))

        #expect(user.userID == AdminFixtures.userID)
        #expect(user.displayName == nil)
        #expect(user.authProvider == .google)
        #expect(user.isBanned)
    }

    @Test func readsPairedSinceAsADateOrATimestamp() throws {
        func detail(pairedSince: String) throws -> AdminUserDetail {
            let json = """
            {"user_id": "11111111-1111-1111-1111-111111111111", "display_name": "Maja",
             "auth_provider": "apple", "created_at": "2026-03-01T10:00:00.000Z",
             "is_admin": false, "banned_at": null, "is_self": false, "ban_reason": null,
             "banned_by_display_name": null, "onboarding_completed_at": null,
             "time_zone_id": null, "is_entitled": false, "couple_id": null,
             "paired_since": "\(pairedSince)", "partner_user_id": null,
             "partner_display_name": null, "reports_against_count": 2, "reports_by_count": 0}
            """
            return try PaeoniaConvexClient.decoder.decode(AdminUserDetail.self, from: Data(json.utf8))
        }

        #expect(try detail(pairedSince: "2025-06-14").pairedSinceDate != nil)
        #expect(try detail(pairedSince: "2025-06-14T08:30:00.000Z").pairedSinceDate != nil)
        #expect(try detail(pairedSince: "2025-06-14").reportsAgainstCount == 2)
    }

    @Test func anActionThisVersionDoesNotKnowDecodesAsOther() throws {
        let json = """
        {"id": "33333333-3333-3333-3333-333333333333", "action": "user_renamed",
         "admin_user_id": null, "admin_display_name": null, "operator_identifier": "hjalmar",
         "target_user_id": "11111111-1111-1111-1111-111111111111", "target_display_name": null,
         "reason": null, "created_at": "2026-03-01T10:00:00.000Z"}
        """

        let entry = try PaeoniaConvexClient.decoder.decode(AdminAuditEntry.self, from: Data(json.utf8))

        #expect(entry.action == .other)
        #expect(entry.operatorIdentifier == "hjalmar")
    }
}
