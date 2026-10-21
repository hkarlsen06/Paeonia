import Foundation
import Testing
@testable import PaeoniaApp

struct PartnerNameTests {
    @Test func theNicknameWinsOverThePartnersOwnName() {
        let name = PartnerName(accountName: "Elena", nickname: "Babe")

        #expect(name.display == "Babe")
    }

    @Test func clearingTheNicknameBringsBackThePartnersOwnName() {
        #expect(PartnerName(accountName: "Elena", nickname: nil).display == "Elena")
        #expect(PartnerName(accountName: "Elena", nickname: "   ").display == "Elena")
    }

    @Test func noNameAtAllIsNilSoCopyCanSayYourPartner() {
        #expect(PartnerName(accountName: " ", nickname: nil).display == nil)
    }

    @Test func nicknamesAreTrimmedAndWhitespaceIsCollapsed() {
        #expect(PartnerName.normalizedNickname("  Ellie \n 🌸 ") == "Ellie 🌸")
        #expect(PartnerName.normalizedNickname("   ") == nil)
    }

    @Test func nicknameLengthIsCountedLikeTheServerCountsIt() {
        #expect(PartnerName.isValidNickname(String(repeating: "🌸", count: PartnerName.maxNicknameLength)))
        #expect(!PartnerName.isValidNickname(String(repeating: "a", count: PartnerName.maxNicknameLength + 1)))
    }

    @Test func theRelationshipStateAppliesTheNickname() throws {
        let json = """
        {"couple_id":"11111111-1111-1111-1111-111111111111","pair_id":"22222222-2222-2222-2222-222222222222",
         "relationship_status":"active","member_status":"active","accepted_invite":false,
         "partner_user_id":"33333333-3333-3333-3333-333333333333","partner_account_name":"Elena",
         "partner_nickname":"Babe","partner_profile_photo_asset_id":null,"started_on":null,"ended_at":null,
         "delete_after":null,"ended_notice_seen_at":null}
        """
        let state = try PaeoniaConvexClient.decoder.decode(RemoteRelationshipState.self, from: Data(json.utf8))

        #expect(state.partnerName.display == "Babe")
    }
}
