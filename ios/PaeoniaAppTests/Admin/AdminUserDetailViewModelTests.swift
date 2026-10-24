import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct AdminUserDetailViewModelTests {
    private func makeModel(
        gateway: AdminFakeGateway,
        counter: AdminChangeCounter? = nil
    ) -> AdminUserDetailViewModel {
        AdminUserDetailViewModel(
            userID: AdminFixtures.userID,
            gateway: gateway,
            onChanged: { counter?.bump() }
        )
    }

    @Test(arguments: [
        (isSelf: false, isAdmin: false, banned: false, canBan: true, canUnban: false),
        (isSelf: true, isAdmin: false, banned: false, canBan: false, canUnban: false),
        (isSelf: false, isAdmin: true, banned: false, canBan: false, canUnban: false),
        (isSelf: false, isAdmin: false, banned: true, canBan: false, canUnban: true),
        // An admin who is banned anyway, for example by the command line before
        // they were an admin, can still be unbanned.
        (isSelf: false, isAdmin: true, banned: true, canBan: false, canUnban: true),
        (isSelf: true, isAdmin: true, banned: true, canBan: false, canUnban: true)
    ])
    func banAndUnbanButtonsFollowTheServerRules(
        isSelf: Bool,
        isAdmin: Bool,
        banned: Bool,
        canBan: Bool,
        canUnban: Bool
    ) {
        let user = AdminFixtures.detail(
            isSelf: isSelf,
            isAdmin: isAdmin,
            bannedAt: banned ? AdminFixtures.bannedAt : nil
        )

        #expect(user.canBan == canBan)
        #expect(user.canUnban == canUnban)
    }

    @Test func reasonMustBeOneToFiveHundredCharactersAfterTrimming() {
        #expect(!AdminUserDetailViewModel.isValidReason(""))
        #expect(!AdminUserDetailViewModel.isValidReason("  \n "))
        #expect(AdminUserDetailViewModel.isValidReason(" spam "))
        #expect(AdminUserDetailViewModel.isValidReason(String(repeating: "a", count: 500)))
        #expect(!AdminUserDetailViewModel.isValidReason(String(repeating: "a", count: 501)))
    }

    @Test func banSendsTheTrimmedReasonThenRefreshesTheScreenAndTheList() async {
        let banned = AdminFixtures.detail(bannedAt: AdminFixtures.bannedAt)
        let logged = AdminFixtures.entry()
        let gateway = AdminFakeGateway(
            detail: AdminFixtures.detail(),
            detailAfterChange: banned,
            auditEntriesAfterChange: [logged]
        )
        let counter = AdminChangeCounter()
        let model = makeModel(gateway: gateway, counter: counter)
        await model.load()

        let didBan = await model.ban(reason: "  Harassing messages \n")

        #expect(didBan)
        #expect(gateway.bans == [AdminBanCall(userID: AdminFixtures.userID, reason: "Harassing messages")])
        #expect(model.user?.isBanned == true)
        #expect(model.history == [logged])
        #expect(counter.calls == 1)
        #expect(model.notice == .banned)
        #expect(!model.isWorking)
    }

    @Test func banWithoutAReasonNeverReachesTheServer() async {
        let gateway = AdminFakeGateway(detail: AdminFixtures.detail())
        let model = makeModel(gateway: gateway)
        await model.load()

        let didBan = await model.ban(reason: "   ")

        #expect(!didBan)
        #expect(model.notice == .reasonInvalid)
        #expect(gateway.bans.isEmpty)
    }

    @Test(arguments: [
        (isSelf: true, isAdmin: false, banned: false),
        (isSelf: false, isAdmin: true, banned: false),
        (isSelf: false, isAdmin: false, banned: true)
    ])
    func banIsRefusedHereForSelfAdminsAndBannedUsers(
        isSelf: Bool,
        isAdmin: Bool,
        banned: Bool
    ) async {
        let user = AdminFixtures.detail(
            isSelf: isSelf,
            isAdmin: isAdmin,
            bannedAt: banned ? AdminFixtures.bannedAt : nil
        )
        let gateway = AdminFakeGateway(detail: user)
        let model = makeModel(gateway: gateway)
        await model.load()

        let didBan = await model.ban(reason: "Spam")

        #expect(!didBan)
        #expect(gateway.bans.isEmpty)
    }

    @Test func failedBanKeepsTheScreenAsItWasAndSaysSo() async {
        let gateway = AdminFakeGateway(detail: AdminFixtures.detail(), changeError: AdminFakeError.failed)
        let counter = AdminChangeCounter()
        let model = makeModel(gateway: gateway, counter: counter)
        await model.load()

        let didBan = await model.ban(reason: "Spam")

        #expect(!didBan)
        #expect(model.notice == .banFailed(.other))
        #expect(model.user?.isBanned == false)
        #expect(counter.calls == 0)
        #expect(!model.isWorking)
    }
}
