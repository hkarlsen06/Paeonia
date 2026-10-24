import SwiftUI

/// The screen an entitled but unpaired user sees. It shows their invite code, lets
/// them enter a partner's code instead, and offers their first questions to answer
/// while they wait.
///
/// The default view models are built once after the view appears. Building it in `init`
/// would repeat its setup (service creation, reading saved data) on every parent redraw.
struct PairingInviteView: View {
    @State private var viewModel: PairingInviteViewModel?
    @State private var firstDayModel: InviterFirstDayModel?

    private let userID: String?
    private let displayName: String?
    private let onSubmitJoinCode: (String) async -> Bool
    private let onRefreshAccess: () -> Void

    /// - Parameters:
    ///   - onSubmitJoinCode: Checks a partner's code typed in the code sheet. If it
    ///     works the root saves it and shows the join screen. Returns false to keep
    ///     the sheet open.
    ///   - onRefreshAccess: Called when access should be checked again.
    init(
        session: AuthSession?,
        viewModel: PairingInviteViewModel? = nil,
        firstDayModel: InviterFirstDayModel? = nil,
        onSubmitJoinCode: @escaping (String) async -> Bool,
        onRefreshAccess: @escaping () -> Void
    ) {
        userID = session?.id
        displayName = session?.displayName
        _viewModel = State(initialValue: viewModel)
        _firstDayModel = State(initialValue: firstDayModel)
        self.onSubmitJoinCode = onSubmitJoinCode
        self.onRefreshAccess = onRefreshAccess
    }

    var body: some View {
        ZStack {
            if let viewModel {
                PairingInviteContent(
                    viewModel: viewModel,
                    firstDay: firstDayModel,
                    onSubmitJoinCode: { await onSubmitJoinCode($0) },
                    onRefreshAccess: onRefreshAccess
                )
            } else {
                ProgressView()
                    .tint(.paeoniaAccentPrimary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            if viewModel == nil {
                viewModel = PairingInviteViewModel(userID: userID)
            }
            if firstDayModel == nil {
                firstDayModel = InviterFirstDayModel(
                    ownerUserID: userID.flatMap(UUID.init(uuidString:)),
                    authorName: displayName
                )
            }
        }
    }
}

#Preview {
    PairingInviteView(
        session: AuthSession(
            id: UUID().uuidString,
            provider: .apple,
            displayName: "Alvilde",
            timeZoneID: "Europe/Oslo",
            profilePhotoAssetID: nil,
            profileStatus: .complete
        ),
        onSubmitJoinCode: { _ in false },
        onRefreshAccess: {}
    )
    .environment(PaeoniaBannerCenter())
    .padding()
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}
