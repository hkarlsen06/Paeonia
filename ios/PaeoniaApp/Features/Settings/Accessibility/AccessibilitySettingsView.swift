import SwiftUI

struct AccessibilitySettingsRow: View {
    var body: some View {
        NavigationLink {
            AccessibilitySettingsView()
        } label: {
            Label {
                Text(.settingsAccessibilityTitle)
            } icon: {
                Image(systemName: "accessibility")
            }
        }
        .accessibilityIdentifier("settings.accessibility")
    }
}

struct AccessibilitySettingsView: View {
    @AccessibilityPresentation(.controls) private var showsControls
    @AccessibilityPresentation(.media) private var showsMedia
    @AppStorage(PaeoniaContrastPreference.storageKey) private var highContrast = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $showsControls) {
                    Text(.settingsAccessibilityControls)
                    Text(.settingsAccessibilityControlsHelp)
                }
                .accessibilityIdentifier("settings.accessibility.controls")
                Toggle(isOn: $showsMedia) {
                    Text(.settingsAccessibilityMedia)
                    Text(.settingsAccessibilityMediaHelp)
                }
                .accessibilityIdentifier("settings.accessibility.media")
                Toggle(isOn: $highContrast) {
                    Text(.settingsAccessibilityHighContrast)
                    Text(.settingsAccessibilityHighContrastHelp)
                }
                .accessibilityIdentifier("settings.accessibility.highContrast")
            } footer: {
                Text(.settingsAccessibilityAutomaticFooter)
            }
            .listRowBackground(Color.paeoniaSurfacePrimary)
        }
        .paeoniaGroupedList()
        .accessibilityIdentifier("settings.accessibility.form")
        .navigationTitle(Text(.settingsAccessibilityTitle))
        .navigationBarTitleDisplayMode(.inline)
    }
}
