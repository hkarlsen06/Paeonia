import SwiftUI

struct DailyAnswerComposerColors {
    let foreground: Color
    let secondary: Color
    let control: Color
    let accent: Color
    let selected: Color

    static let standard = Self(
        foreground: .paeoniaTextPrimary,
        secondary: .paeoniaTextSecondary,
        control: .paeoniaSurfaceSecondary,
        accent: .paeoniaAccentPrimary,
        selected: .paeoniaSurfacePressed
    )

    static let composer = Self(
        foreground: .paeoniaTextPrimary,
        secondary: .paeoniaTextSecondary,
        control: Color.paeoniaBackgroundSecondary.opacity(0.6),
        accent: .paeoniaAccentPrimary,
        selected: Color.paeoniaAccentPrimary.opacity(0.18)
    )
}

extension EnvironmentValues {
    @Entry var dailyAnswerComposerColors = DailyAnswerComposerColors.standard
}

struct DailyAnswerFlowHeader: View {
    let question: DailyChallengeQuestion?
    let participants: DailyChallengeParticipants
    let onClose: () -> Void
    var canSkip = false
    var skipTitle: LocalizedStringResource?
    var isSkipDisabled = false
    var isSkipping = false
    var onSkip: () -> Void = {}
    /// A quiet line between Close and Skip, such as that the last answer was sent.
    var sentNote: LocalizedStringResource?

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(PaeoniaQuietButtonStyle())
            .accessibilityLabel(Text(.dailyChallengeFlowClose))
            .accessibilityIdentifier("daily.flow.close")

            ZStack {
                if let sentNote {
                    Label {
                        Text(sentNote)
                    } icon: {
                        Image(systemName: "checkmark").accessibilityHidden(true)
                    }
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .transition(.opacity)
                    .accessibilityIdentifier("daily.flow.sentNote")
                }
            }
            .frame(maxWidth: .infinity)

            if question?.hasPartnerAnswer == true {
                partnerBadge
            }

            if canSkip {
                skipButton
            }
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
    }

    private var skipButton: some View {
        Button(action: onSkip) {
            if isSkipping {
                ProgressView()
            } else if let skipTitle {
                Text(skipTitle)
            } else {
                Image(systemName: "shuffle")
            }
        }
        .buttonStyle(PaeoniaQuietButtonStyle())
        .disabled(isSkipDisabled || isSkipping)
        .accessibilityLabel(Text(.dailyChallengeSkipButton))
        .accessibilityIdentifier("daily.flow.skip")
    }

    private var partnerBadge: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            Text(.dailyChallengePartnerHidden(participants.partnerName))
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
            PaeoniaProfilePhotoAvatar(
                mediaAssetID: participants.partnerProfilePhotoAssetID,
                name: participants.partnerName,
                tint: .paeoniaAccentPrimary,
                size: 32
            )
            .accessibilityHidden(true)
        }
    }
}

struct DailyAnswerComposerSendButton: View {
    let title: LocalizedStringResource
    let isBusy: Bool
    let isDisabled: Bool
    let onSend: () -> Void

    var body: some View {
        Button(action: onSend) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: "arrow.up")
            }
            .font(PaeoniaTypography.button)
            .opacity(isBusy ? 0 : 1)
            .overlay {
                if isBusy { ProgressView().tint(.paeoniaTextInverse) }
            }
            .padding(.horizontal, PaeoniaSpacing.space16)
            .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
            .foregroundStyle(.paeoniaTextInverse)
            .background(.paeoniaAccentPrimary, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isBusy)
        .opacity(isDisabled && !isBusy ? 0.4 : 1)
        .accessibilityIdentifier("daily.flow.primary")
    }
}
