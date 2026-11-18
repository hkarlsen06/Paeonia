import SwiftUI

/// The privacy switches someone without a subscription can still reach: stop
/// sharing their location, turn off private topics such as Flirt, and share usage
/// statistics or not. Taking back a yes
/// must not cost a subscription, and the paid app's own switches are behind the
/// paywall. The sheet covers the app's root banner, so it mounts the shared
/// banner itself.
struct PaywallPrivacySheet: View {
    /// Nil for someone without a partner, who shares no location.
    let location: PaywallLocationSharingModel?
    /// Nil in previews. Shows its switch only for someone who said yes to private topics.
    let privateTopics: PaywallPrivateTopicsModel?
    /// Nil in a build without usage statistics.
    let usageToggle: UsageSharingToggle?

    @State private var isConfirmingPrivateTopicsOff = false
    @Environment(\.dismiss) private var dismiss
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    if let location {
                        locationSection(location)
                    }
                    if let privateTopics {
                        privateTopicsSection(privateTopics)
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
        .task {
            await privateTopics?.load()
        }
        .onChange(of: location?.failure) { _, failure in
            guard let failure else {
                return
            }
            showSaveFailed(failure)
            location?.clearFailure()
        }
        .onChange(of: privateTopics?.failure) { _, failure in
            guard let failure else {
                return
            }
            showSaveFailed(failure)
            privateTopics?.clearFailure()
        }
    }

    private func showSaveFailed(_ failure: PaeoniaFailure) {
        // Only a phone without a connection is told to connect.
        bannerCenter.show(
            .error(
                title: String(localized: .paywallPrivacySaveFailedTitle),
                message: String(localized: failure == .offline
                    ? .paywallPrivacySaveFailedOfflineMessage : .commonActionFailedMessage)
            )
        )
    }

    /// A section whose switch waits for the server's answer.
    private enum SectionPhase {
        case hidden
        case loading
        case loadFailed
        case loaded
    }

    @ViewBuilder
    private func section(
        _ title: LocalizedStringResource,
        phase: SectionPhase,
        retry: @escaping () async -> Void,
        @ViewBuilder content: () -> some View
    ) -> some View {
        switch phase {
        case .hidden:
            EmptyView()
        case .loading:
            Section {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(Text(.commonLoading))
            } header: {
                Text(title)
            }
        case .loadFailed:
            Section {
                Text(.commonActionFailedMessage)
                    .foregroundStyle(.paeoniaTextSecondary)
                Button {
                    Task { await retry() }
                } label: {
                    Text(.commonTryAgain)
                }
            } header: {
                Text(title)
            }
        case .loaded:
            Section {
                content()
            } header: {
                Text(title)
            }
        }
    }

    private func locationSection(_ location: PaywallLocationSharingModel) -> some View {
        let phase: SectionPhase = switch location.state {
        case .noCouple: .hidden
        case .loading: .loading
        case .loadFailed: .loadFailed
        case .loaded: .loaded
        }
        return section(.settingsLocationSectionTitle, phase: phase, retry: location.load) {
            locationToggle(location)
        }
    }

    private func privateTopicsSection(_ privateTopics: PaywallPrivateTopicsModel) -> some View {
        let phase: SectionPhase = switch privateTopics.state {
        case .notConsented: .hidden
        case .loading: .loading
        case .loadFailed: .loadFailed
        case .loaded: .loaded
        }
        return section(.privacySafetyPrivateTopicsSectionTitle, phase: phase, retry: privateTopics.load) {
            if case let .loaded(name, isOn) = privateTopics.state {
                privateTopicsToggle(privateTopics, name: name, isOn: isOn)
            }
        }
    }

    private func privateTopicsToggle(_ privateTopics: PaywallPrivateTopicsModel, name: String, isOn: Bool) -> some View {
        Toggle(isOn: Binding(
            get: { isOn },
            set: { isOn in
                if !isOn {
                    isConfirmingPrivateTopicsOff = true
                }
            }
        )) {
            Text(verbatim: name)
            Text(.privacySafetyPrivateTopicsToggleDescription(name))
        }
        // It only turns off here, and a choice that is still saving cannot be flipped again.
        .disabled(!isOn || privateTopics.isSaving)
        .accessibilityIdentifier("paywall.privacy.privateTopics")
        .alert(Text(.privacySafetyPrivateTopicsTurnOffTitle(name)), isPresented: $isConfirmingPrivateTopicsOff) {
            Button(role: .destructive) {
                Task {
                    if await privateTopics.turnOff() {
                        bannerCenter.show(
                            .info(
                                message: String(localized: .privacySafetyPrivateTopicsDeletedMessage(name)),
                                systemImage: "checkmark.shield.fill"
                            )
                        )
                    }
                }
            } label: {
                Text(.privacySafetyPrivateTopicsTurnOffConfirm)
            }
            .accessibilityIdentifier("paywall.privacy.privateTopics.turnOff.confirm")
            Button(role: .cancel, action: {}) {
                Text(.commonCancel)
            }
        } message: {
            Text(.privacySafetyPrivateTopicsTurnOffMessage(name))
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
