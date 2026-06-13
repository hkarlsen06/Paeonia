import SwiftUI

struct RootView: View {
    @State private var viewModel = RootViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: PaeoniaSpacing.sectionSpacing) {
                    header
                    foundationCard
                    emptyStateCard
                }
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                .padding(.top, PaeoniaSpacing.screenTopSpacing)
                .padding(.bottom, PaeoniaSpacing.space40)
            }
            .background(.paeoniaBackgroundPrimary)
        }
        .task {
            await viewModel.start()
        }
    }

    private var header: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            Text(.appTitle)
                .font(PaeoniaTypography.display)
                .foregroundStyle(.paeoniaTextPrimary)

            Text(.appTagline)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)

            ViewThatFits {
                HStack(spacing: PaeoniaSpacing.space8) {
                    PaeoniaSyncStatusView(status: syncStatus)
                    stateLabel
                }

                VStack(spacing: PaeoniaSpacing.space8) {
                    PaeoniaSyncStatusView(status: syncStatus)
                    stateLabel
                }
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private var foundationCard: some View {
        PaeoniaCard {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
                    Text(.rootFoundationTitle)
                        .font(PaeoniaTypography.sectionTitle)
                        .foregroundStyle(.paeoniaTextPrimary)

                    Text(.rootFoundationMessage)
                        .font(PaeoniaTypography.body)
                        .foregroundStyle(.paeoniaTextSecondary)
                }

                VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
                    Text(.rootPaletteTitle)
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextPrimary)

                    Text(.rootPaletteMessage)
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextTertiary)
                }
            }
        }
    }

    private var emptyStateCard: some View {
        PaeoniaCard {
            PaeoniaEmptyStateView(
                title: .rootEmptyTitle,
                message: .rootEmptyMessage,
                systemImage: "heart.text.square"
            ) {
                VStack(spacing: PaeoniaSpacing.space8) {
                    Button {} label: {
                        Text(.rootPrimaryAction)
                    }
                    .buttonStyle(PaeoniaPrimaryButtonStyle())
                    .disabled(true)

                    Text(.rootPrimaryActionHint)
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextTertiary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private var stateLabel: some View {
        Text(stateDescription)
            .font(PaeoniaTypography.caption)
            .foregroundStyle(.paeoniaTextTertiary)
            .padding(.horizontal, PaeoniaSpacing.space12)
            .padding(.vertical, PaeoniaSpacing.space8)
            .background(.paeoniaSurfaceSecondary)
            .clipShape(Capsule(style: .continuous))
    }

    private var syncStatus: PaeoniaSyncStatus {
        viewModel.state == .launching ? .syncing : .savedLocally
    }

    private var stateDescription: LocalizedStringResource {
        switch viewModel.state {
        case .launching:
            .appStateLaunching
        case .unauthenticated:
            .appStateUnauthenticated
        case .onboarding:
            .appStateOnboarding
        case .unpaired:
            .appStateUnpaired
        case .paired:
            .appStatePaired
        case .paywalled:
            .appStatePaywalled
        }
    }
}

#Preview {
  RootView()
}
