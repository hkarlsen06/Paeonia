import SwiftUI

/// The switch for private topics such as Flirt on the privacy and safety screen. On
/// means this person said yes to answering there. Turning it on asks the same
/// question the topic asks the first time it opens. Turning it off asks once,
/// then takes the yes back, which deletes their answers there.
struct PrivateTopicsConsentSection: View {
    let topics: TopicsViewModel

    @State private var isAskingConsent = false
    @State private var isConfirmingTurnOff = false
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    private var name: String {
        topics.privateTopicsName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            Text(.privacySafetyPrivateTopicsSectionTitle)
                .font(PaeoniaTypography.sectionTitle)
                .foregroundStyle(.paeoniaTextSecondary)

            PaeoniaCard(surface: .raised) {
                Toggle(isOn: Binding(
                    get: { topics.hasPrivateTopicsConsent },
                    set: { isOn in
                        if isOn {
                            isAskingConsent = true
                        } else {
                            isConfirmingTurnOff = true
                        }
                    }
                )) {
                    Text(verbatim: name)
                    Text(.privacySafetyPrivateTopicsToggleDescription(name))
                }
                .disabled(topics.isSavingPrivateTopicsConsent)
                .accessibilityIdentifier("privacy.privateTopics.toggle")
            }
        }
        .sheet(isPresented: $isAskingConsent) {
            if let topic = topics.privateTopics.first {
                PrivateTopicConsentSheet(
                    topicKey: topic.id,
                    topicName: name,
                    purpose: .turnOn,
                    viewModel: topics,
                    onConsented: { isAskingConsent = false }
                )
            }
        }
        .alert(Text(.privacySafetyPrivateTopicsTurnOffTitle(name)), isPresented: $isConfirmingTurnOff) {
            Button(role: .destructive, action: turnOff) {
                Text(.privacySafetyPrivateTopicsTurnOffConfirm)
            }
            .accessibilityIdentifier("privacy.privateTopics.turnOff.confirm")
            Button(role: .cancel, action: {}) {
                Text(.commonCancel)
            }
        } message: {
            Text(.privacySafetyPrivateTopicsTurnOffMessage(name))
        }
    }

    private func turnOff() {
        // Read before the switch goes off, in case the shelf changes meanwhile.
        let topicName = name
        Task {
            if let failure = await topics.setPrivateTopicsConsent(false) {
                bannerCenter.show(failure.topicsBanner)
            } else {
                bannerCenter.show(
                    .info(
                        message: String(localized: .privacySafetyPrivateTopicsDeletedMessage(topicName)),
                        systemImage: "checkmark.shield.fill"
                    )
                )
            }
        }
    }
}
