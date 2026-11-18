import SwiftUI

/// The privacy switches someone without a subscription can still reach: stop
/// sharing their location, and share usage statistics or not. Taking back a yes
/// must not cost a subscription, and the paid app's own switches are behind the
/// paywall. The sheet covers the app's root banner, so it mounts the shared
/// banner itself.
struct PaywallPrivacySheet: View {
    /// Nil for someone without a partner, who shares no location.
    let location: PaywallLocationSharingModel?
    /// Nil in a build without usage statistics.
    let usageToggle: UsageSharingToggle?

    @Environment(\.dismiss) private var dismiss
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    if let location {
                        locationSection(location)
                    }
                    if let usageToggle {
                        Section {
                            usageToggle
                        } header: {
                            Text(.privacySafetyUsageSectionTitle)
                        }
                    }
                }
                .listRowBackground(Color.paeoniaSurfacePrimary)
            }
            .paeoniaGroupedList()
            .navigationTitle(Text(.paywallPrivacyTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(.commonDone)
                    }
                }
            }
        }
        .paeoniaBanner(bannerCenter)
        .presentationDetents([.large])
        .presentationBackground(.paeoniaBackgroundPrimary)
        .task {
            await location?.load()
        }
        .onChange(of: location?.failure) { _, failure in
            guard let failure else {
                return
            }
            // Only a phone without a connection is told to connect.
            bannerCenter.show(
                .error(
                    title: String(localized: .paywallPrivacySaveFailedTitle),
                    message: String(localized: failure == .offline
                        ? .paywallPrivacySaveFailedOfflineMessage : .commonActionFailedMessage)
                )
            )
            location?.clearFailure()
        }
    }

    @ViewBuilder
    private func locationSection(_ location: PaywallLocationSharingModel) -> some View {
        switch location.state {
        case .noCouple:
            EmptyView()
        case .loading:
            Section {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(Text(.commonLoading))
            } header: {
                Text(.settingsLocationSectionTitle)
            }
        case .loadFailed:
            Section {
                Text(.commonActionFailedMessage)
                    .foregroundStyle(.paeoniaTextSecondary)
                Button {
                    Task { await location.load() }
                } label: {
                    Text(.commonTryAgain)
                }
            } header: {
                Text(.settingsLocationSectionTitle)
            }
        case .loaded:
            Section {
                locationToggle(location)
            } header: {
                Text(.settingsLocationSectionTitle)
            }
        }
    }

    private func locationToggle(_ location: PaywallLocationSharingModel) -> some View {
        Toggle(isOn: Binding(
            get: { location.isEnabled },
            set: { isOn in
                if !isOn {
                    Task { await location.turnOff() }
                }
            }
        )) {
            Text(.settingsLocationSharingTitle)
            Text(.paywallPrivacyLocationDescription)
        }
        // It only turns off here, and a choice that is still saving cannot be flipped again.
        .disabled(!location.isEnabled || location.isSaving)
        .accessibilityIdentifier("paywall.privacy.location")
    }
}
