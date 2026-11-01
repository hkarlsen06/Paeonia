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

    var body: some View {
        Form {
            Section {
                Picker(selection: $showsControls) {
                    Text(.settingsAccessibilityAutomatic).tag(false)
                        .accessibilityIdentifier("settings.accessibility.controls.automatic")
                    Text(.settingsAccessibilityAlways).tag(true)
                        .accessibilityIdentifier("settings.accessibility.controls.always")
                } label: {
                    Text(.settingsAccessibilityControls)
                }
                .accessibilityIdentifier("settings.accessibility.controls")
                .pickerStyle(.menu)
            } footer: {
                Text(.settingsAccessibilityControlsHelp)
            }
            Section {
                Picker(selection: $showsMedia) {
                    Text(.settingsAccessibilityAutomatic).tag(false)
                        .accessibilityIdentifier("settings.accessibility.media.automatic")
                    Text(.settingsAccessibilityAlways).tag(true)
                        .accessibilityIdentifier("settings.accessibility.media.always")
                } label: {
                    Text(.settingsAccessibilityMedia)
                }
                .accessibilityIdentifier("settings.accessibility.media")
                .pickerStyle(.menu)
            } footer: {
                Text(.settingsAccessibilityMediaHelp)
            }
        }
        .paeoniaGroupedList()
        .accessibilityIdentifier("settings.accessibility.form")
        .navigationTitle(Text(.settingsAccessibilityTitle))
        .navigationBarTitleDisplayMode(.inline)
    }
}
