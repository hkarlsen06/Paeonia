#if DEBUG
  import SwiftUI

  /// The admin area with made-up reports and correction requests. The real one needs an admin
  /// account on the server.
  nonisolated extension DeveloperScenario {
    static let admin: [DeveloperScenario] = [adminHub, adminOpenCases]

    static let adminHub = DeveloperScenario(
      "admin-hub", "Admin · hub", "The admin screen, with the row for reports and requests", .settings
    ) { _ in DeveloperAdminScenarioView { AdminHubView(gateway: $0) } }
    static let adminOpenCases = DeveloperScenario(
      "admin-open-cases", "Admin · reports and requests",
      "Two open reports and one correction request that wait for an admin", .settings
    ) { _ in DeveloperAdminScenarioView { AdminOpenCasesView(gateway: $0) } }
  }

  struct DeveloperAdminScenarioView<Content: View>: View {
    @ViewBuilder let content: (any AdminGateway) -> Content

    var body: some View {
      NavigationStack {
        content(DeveloperAdminGateway())
      }
      .environment(PaeoniaBannerCenter())
    }
  }

  // The gateway protocol is async, and this one answers at once.
  // swiftlint:disable async_without_await

  /// Answers the admin calls from fixed data. Bans change nothing, and a case marked as handled
  /// leaves the list until the screen loads again.
  nonisolated struct DeveloperAdminGateway: AdminGateway {
    private static let reporterID = DeveloperScenarioFixture.partnerUserID
    private static let reportedID = DeveloperScenarioFixture.currentUserID

    func loadIsAdmin() async throws -> Bool { true }
    func searchUsers(query _: String?, bannedOnly _: Bool) async throws -> [AdminUserSummary] { [] }
    func loadUser(id _: UUID) async throws -> AdminUserDetail? { nil }
    func banUser(id _: UUID, reason _: String) async throws {}
    func unbanUser(id _: UUID) async throws {}
    func loadAuditLog(targetUserID _: UUID?) async throws -> [AdminAuditEntry] { [] }
    func close(_: AdminOpenCase) async throws {}

    func loadOpenReports() async throws -> [AdminOpenReport] {
      [
        AdminOpenReport(
          id: UUID(uuidString: "c0000000-0000-4000-8000-000000000001") ?? UUID(),
          reasonCode: PrivacyReportReason.harassment.rawValue,
          note: "He keeps sending me messages after I asked him to stop.",
          reporterUserID: Self.reporterID, reporterDisplayName: "Maja",
          reportedUserID: Self.reportedID, reportedDisplayName: "Jonas",
          createdAt: DeveloperScenarioFixture.now.addingTimeInterval(-2 * 86_400)
        ),
        AdminOpenReport(
          id: UUID(uuidString: "c0000000-0000-4000-8000-000000000002") ?? UUID(),
          reasonCode: PrivacyReportReason.sexualContent.rawValue,
          note: nil,
          reporterUserID: Self.reportedID, reporterDisplayName: "Ingrid",
          reportedUserID: Self.reporterID, reportedDisplayName: nil,
          createdAt: DeveloperScenarioFixture.now.addingTimeInterval(-3 * 3_600)
        ),
      ]
    }

    func loadOpenCorrectionRequests() async throws -> [AdminCorrectionRequest] {
      [
        AdminCorrectionRequest(
          id: UUID(uuidString: "c0000000-0000-4000-8000-000000000003") ?? UUID(),
          userID: Self.reporterID, userDisplayName: "Sofie",
          requesterNote: "My birthday is saved as the wrong year. It should be 2001.",
          requestedAt: DeveloperScenarioFixture.now.addingTimeInterval(-86_400)
        ),
      ]
    }
  }
  // swiftlint:enable async_without_await
#endif
