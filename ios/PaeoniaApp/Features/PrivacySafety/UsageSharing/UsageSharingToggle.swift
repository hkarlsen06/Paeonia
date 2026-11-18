import SwiftUI

/// The Share usage statistics switch, in Privacy and safety and in the paywall's
/// privacy settings.
struct UsageSharingToggle: View {
    @Binding private var shares: Bool

    init(_ usageSharing: UsageSharingModel) {
        _shares = Binding(
            get: { usageSharing.shares == true },
            set: { shares in Task { await usageSharing.answer(shares) } }
        )
    }

    init(shares: Binding<Bool>) {
        _shares = shares
    }

    var body: some View {
        Toggle(isOn: $shares) {
            Text(.privacySafetyUsageToggleTitle)
            Text(.privacySafetyUsageToggleDescription)
        }
        .accessibilityIdentifier("privacy.usage.toggle")
    }
}
