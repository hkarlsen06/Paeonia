import SwiftUI
import UIKit

/// The "You" tab: the couple member's personal corner. For MVP it hosts the
/// notification settings; more personal settings will join it here.
struct SettingsView: View {
    @State private var viewModel = SettingsViewModel()
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.sectionSpacing) {
                notificationsSection
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.screenTopSpacing)
            .padding(.bottom, PaeoniaSpacing.space40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.paeoniaBackgroundPrimary)
        .navigationTitle(Text(.mainTabYou))
        .navigationBarTitleDisplayMode(.large)
        .task {
            await viewModel.load()
        }
        .onChange(of: viewModel.notice) { _, notice in
            guard notice != nil else {
                return
            }
            bannerCenter.show(
                .error(
                    title: String(localized: .settingsNotificationsSaveErrorTitle),
                    message: String(localized: .settingsNotificationsSaveErrorMessage)
                )
            )
            viewModel.dismissNotice()
        }
    }

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            Text(.settingsNotificationsSectionTitle)
                .font(PaeoniaTypography.sectionTitle)
                .foregroundStyle(.paeoniaTextSecondary)

            PaeoniaCard {
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
                    Toggle(isOn: widgetAlertsBinding) {
                        VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                            Text(.settingsNotificationsWidgetAlertsTitle)
                                .font(PaeoniaTypography.body)
                                .foregroundStyle(.paeoniaTextPrimary)
                            Text(.settingsNotificationsWidgetAlertsSubtitle)
                                .font(PaeoniaTypography.caption)
                                .foregroundStyle(.paeoniaTextSecondary)
                        }
                    }
                    .tint(.paeoniaAccentPrimary)
                    .disabled(!viewModel.isLoaded)

                    if viewModel.systemNotificationsDenied {
                        systemDisabledNote
                    }
                }
            }
        }
    }

    private var systemDisabledNote: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            Divider()
                .overlay(.paeoniaSurfacePressed)

            Text(.settingsNotificationsSystemOffTitle)
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaTextPrimary)
            Text(.settingsNotificationsSystemOffMessage)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } label: {
                Text(.settingsNotificationsOpenSettingsButton)
            }
            .buttonStyle(PaeoniaSecondaryButtonStyle())
        }
    }

    private var widgetAlertsBinding: Binding<Bool> {
        Binding(
            get: { viewModel.widgetAlertsEnabled },
            set: { newValue in
                Task { await viewModel.setWidgetAlertsEnabled(newValue) }
            }
        )
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(PaeoniaBannerCenter())
    .preferredColorScheme(.dark)
}
