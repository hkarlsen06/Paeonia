import DeclaredAgeRange
import SwiftUI

/// What the age check means for the adults-only topic. Pure, so tests can cover it.
nonisolated enum AdultAgeCheck {
    /// Only a shared range that starts at 18 or above opens the topic. Anything else,
    /// such as an unknown lower bound, hides it.
    static func status(lowerBound: Int?) -> AdultTopicsStatus {
        guard let lowerBound, lowerBound >= 18 else { return .hidden }
        return .confirmed
    }

    /// Errors that mean the age can't be known on this phone. They hide the topic,
    /// like declining. A network error and a bad request are failures to try again.
    static func hidesTopic(_ error: AgeRangeService.Error) -> Bool {
        switch error {
        case .notAvailable, .invalidAccount, .declinedOnboarding:
            true
        case .network, .invalidRequest:
            false
        @unknown default:
            true
        }
    }
}

/// Shown the first time someone opens the adults-only topic, and from "Show Flirt
/// again". Continue hands over to Apple's own age sheet (`requestAgeRange`). Nothing
/// is asked at launch. Paeonia saves only whether the topic may open, never the age.
/// Declining closes the sheet and the topic leaves the shelf on both phones, with no
/// message, so nothing tells the partner why.
struct AdultTopicSheet: View {
    let viewModel: TopicsViewModel
    let partnerName: String

    @Environment(\.requestAgeRange) private var requestAgeRange
    @Environment(\.dismiss) private var dismiss
    @State private var isChecking = false

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            TopicArtwork(topicKey: "flirt", height: 72)
                .padding(.top, PaeoniaSpacing.space24)

            Text(.topicsAdultTitle)
                .font(PaeoniaTypography.collectionHeroTitle)
                .foregroundStyle(.paeoniaTextPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: PaeoniaSpacing.space12) {
                Text(.topicsAdultBody)
                Text(.topicsAdultPartnerLine(partnerName))
            }
            .font(PaeoniaTypography.body)
            .foregroundStyle(.paeoniaTextSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: PaeoniaSpacing.space8)

            actions
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.bottom, PaeoniaSpacing.space16)
        .frame(maxWidth: PaeoniaSpacing.focusedContentWidth)
        .analyticsScreen("topics_adult_check")
    }

    private var actions: some View {
        VStack(spacing: PaeoniaSpacing.space4) {
            Button {
                Task { await check() }
            } label: {
                if isChecking {
                    ProgressView()
                        .tint(.paeoniaTextInverse)
                } else {
                    Text(.topicsAdultContinue)
                }
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())
            .disabled(isChecking)
            .accessibilityIdentifier("topics.adult.continue")

            Button {
                dismiss()
            } label: {
                Text(.topicsAdultNotNow)
                    .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.compactButtonHeight)
            }
            .font(PaeoniaTypography.button)
            .foregroundStyle(.paeoniaTextSecondary)
        }
    }

    private func check() async {
        isChecking = true
        defer { isChecking = false }
        // Apple's action isn't Sendable. This screen only calls it from the main actor.
        nonisolated(unsafe) let requestAgeRange = requestAgeRange
        do {
            let status: AdultTopicsStatus
            switch try await requestAgeRange(ageGates: 18) {
            case let .sharing(range):
                status = AdultAgeCheck.status(lowerBound: range.lowerBound)
            case .declinedSharing:
                status = .hidden
            @unknown default:
                status = .hidden
            }
            await viewModel.saveAdultTopicsStatus(status)
            dismiss()
        } catch let error as AgeRangeService.Error {
            if AdultAgeCheck.hidesTopic(error) {
                await viewModel.saveAdultTopicsStatus(.hidden)
                dismiss()
            } else {
                // Apple's network error doesn't show the phone is offline, so the
                // banner says something went wrong rather than blaming the connection.
                viewModel.reportAdultCheckFailure(.other)
            }
        } catch {
            guard !error.isCancellation else { return }
            viewModel.reportAdultCheckFailure(PaeoniaFailure(error))
        }
    }
}
