import SwiftUI

/// The screen an entitled but unpaired user sees. It shows their invite code and lets
/// them join a partner's code instead.
///
/// The default view model is built once after the view appears. Building it in `init`
/// would repeat its setup (service creation, reading saved data) on every parent redraw.
struct PairingInviteView: View {
    @State private var viewModel: PairingInviteViewModel?

    private let userID: String?
    private let pendingJoinCode: String?
    private let onClearPendingJoinCode: () -> Void
    private let onInviteAccepted: () -> Void
    private let onRefreshAccess: () -> Void

    /// - Parameters:
    ///   - pendingJoinCode: A normalized partner code from a link or the welcome screen.
    ///     The screen asks the user to confirm joining it once their own code is showing.
    ///   - onClearPendingJoinCode: Called when the pending code is done with, so the root
    ///     can forget it.
    ///   - onInviteAccepted: Called after the user joined their partner.
    ///   - onRefreshAccess: Called when access should be checked again.
    init(
        session: AuthSession?,
        viewModel: PairingInviteViewModel? = nil,
        pendingJoinCode: String?,
        onClearPendingJoinCode: @escaping () -> Void,
        onInviteAccepted: @escaping () -> Void,
        onRefreshAccess: @escaping () -> Void
    ) {
        userID = session?.id
        _viewModel = State(initialValue: viewModel)
        self.pendingJoinCode = pendingJoinCode
        self.onClearPendingJoinCode = onClearPendingJoinCode
        self.onInviteAccepted = onInviteAccepted
        self.onRefreshAccess = onRefreshAccess
    }

    var body: some View {
        ZStack {
            if let viewModel {
                PairingInviteContent(
                    viewModel: viewModel,
                    pendingJoinCode: pendingJoinCode,
                    onClearPendingJoinCode: onClearPendingJoinCode,
                    onInviteAccepted: onInviteAccepted,
                    onRefreshAccess: onRefreshAccess
                )
            } else {
                AuthLaunchingView()
            }
        }
        .task {
            if viewModel == nil {
                viewModel = PairingInviteViewModel(userID: userID)
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
        pendingJoinCode: nil,
        onClearPendingJoinCode: {},
        onInviteAccepted: {},
        onRefreshAccess: {}
    )
    .environment(PaeoniaBannerCenter())
    .padding()
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}
