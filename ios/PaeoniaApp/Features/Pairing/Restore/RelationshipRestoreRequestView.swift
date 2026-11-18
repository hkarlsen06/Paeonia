import SwiftUI

/// The screen an inviter sees when the person who used their code is a former partner
/// who asked to bring back what the two had. It stands in for the invite screen until
/// they answer, and either answer pairs the two.
struct RelationshipRestoreRequestView: View {
    let request: RemoteRestoreRequest
    /// Called once the answer went through, so the root checks access again.
    let onAnswered: () -> Void

    @State private var model: RelationshipRestoreRequestModel
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    /// - Parameter model: A local flow's model. Nil uses the live server.
    init(
        request: RemoteRestoreRequest,
        model: RelationshipRestoreRequestModel? = nil,
        onAnswered: @escaping () -> Void
    ) {
        self.request = request
        _model = State(initialValue: model ?? RelationshipRestoreRequestModel())
        self.onAnswered = onAnswered
    }

    private static let avatarSize: CGFloat = 132

    private var partnerName: String? {
        request.partnerName?.trimmedNonEmpty
    }

    var body: some View {
        PaeoniaScreenScroll {
            VStack(spacing: PaeoniaSpacing.space24) {
                PaeoniaProfilePhotoAvatar(
                    mediaAssetID: request.partnerProfilePhotoAssetID,
                    name: partnerName ?? "",
                    tint: .paeoniaPartnerTwo,
                    size: Self.avatarSize
                )
                .accessibilityHidden(true)
                .screenEntrance(order: 1)

                Text(partnerName.map { .pairingRestoreRequestTitle($0) } ?? .pairingRestoreRequestTitleFallback)
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .screenEntrance(order: 2)

                RelationshipRestoreSummary(title: nil, message: .pairingRestoreRequestMessage)
                    .screenEntrance(order: 3)

                Text(partnerName.map { .pairingRestoreRequestEither($0) } ?? .pairingRestoreRequestEitherFallback)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .screenEntrance(order: 3)
            }
            .frame(maxWidth: .infinity)
        }
        .paeoniaBottomBar(spacing: 0) {
            VStack(spacing: PaeoniaSpacing.space8) {
                Button {
                    answer(restore: true)
                } label: {
                    Text(.pairingRestoreBringBack)
                }
                .buttonStyle(PaeoniaPrimaryButtonStyle(isLoading: model.sendingAnswer == true))
                .accessibilityIdentifier("pairing.restore.request.bringBack")

                Button {
                    answer(restore: false)
                } label: {
                    Text(.pairingRestoreStartFresh)
                }
                .buttonStyle(PaeoniaSecondaryButtonStyle(isLoading: model.sendingAnswer == false))
                .accessibilityIdentifier("pairing.restore.request.startFresh")
            }
            .disabled(model.sendingAnswer != nil)
            .padding(.top, PaeoniaSpacing.space12)
            .onboardingBottomBarFade()
            .screenEntrance(order: 4)
        }
    }

    private func answer(restore: Bool) {
        Task {
            switch await model.answer(request, restore: restore) {
            case .paired(tooLate: false):
                bannerCenter.dismiss()
                onAnswered()
            case .paired(tooLate: true):
                bannerCenter.show(.info(message: String(localized: .pairingRestoreTooLate)))
                onAnswered()
            case .requestGone:
                bannerCenter.show(.info(message: String(localized: .pairingRestoreRequestGone)))
                onAnswered()
            case let .failed(failure):
                let message: LocalizedStringResource = failure == .offline
                    ? .pairingRestoreAnswerFailed
                    : .pairingRestoreAnswerFailedLater
                bannerCenter.show(.error(message: String(localized: message)))
            case nil:
                break
            }
        }
    }
}
