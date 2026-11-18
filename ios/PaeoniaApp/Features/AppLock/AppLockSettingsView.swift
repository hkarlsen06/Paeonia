import SwiftUI

/// The lock's own screen under App in the More tab: the switch, how long Paeonia
/// may be left before it locks, and what the lock does not cover.
struct AppLockSettingsView: View {
    let model: AppLockModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Form {
            Group {
                if !model.capability.canAuthenticate, !model.isEnabled {
                    Section {
                        noPasscodeNote
                    }
                }

                Section {
                    Toggle(isOn: lockBinding) {
                        Text(.appLockLockWith(model.capability.biometry.name))
                        Text(.appLockToggleSubtitle)
                    }
                    .disabled(model.isAuthenticating || (!model.capability.canAuthenticate && !model.isEnabled))

                    if model.isEnabled {
                        Picker(selection: timeoutBinding) {
                            ForEach(AppLockTimeout.allCases, id: \.self) { timeout in
                                Text(timeout.title).tag(timeout)
                            }
                        } label: {
                            Text(.appLockTimeoutLabel)
                        }
                    }
                } footer: {
                    Text(.appLockFooter)
                }
            }
            .listRowBackground(Color.paeoniaSurfacePrimary)
        }
        // The timeout picker glides in and out with the switch.
        .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: model.isEnabled)
        .paeoniaGroupedList()
        .navigationTitle(Text(.appLockScreenTitle))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            model.refreshCapability()
        }
    }

    /// A phone without a passcode has nothing to unlock with, so the switch
    /// stays off and this says why.
    private var noPasscodeNote: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
            Text(.appLockNoPasscodeTitle)
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaTextPrimary)
            Text(.appLockNoPasscodeMessage)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Reads the saved setting, so a prompt the person cancels leaves the
    /// switch where it was.
    private var lockBinding: Binding<Bool> {
        Binding(
            get: { model.isEnabled },
            set: { newValue in
                Task {
                    // Spotlight holds nothing while the lock is on, and gets it back when it is off.
                    if await model.setEnabled(newValue) {
                        await SiriEntityIndexer.shared.refresh(force: true)
                    }
                }
            }
        )
    }

    private var timeoutBinding: Binding<AppLockTimeout> {
        Binding(
            get: { model.timeout },
            set: { model.setTimeout($0) }
        )
    }
}

/// The App section row that opens the lock screen. Its value names what the lock
/// opens with, or says Off. Previews and developer flows have no lock, and the
/// row is not shown there.
struct AppLockSettingsRow: View {
    @Environment(AppLockModel.self) private var model: AppLockModel?

    var body: some View {
        if let model {
            NavigationLink {
                AppLockSettingsView(model: model)
                    .analyticsScreen("settings_app_lock")
            } label: {
                SettingsMenuLabel(.appLockRowTitle, systemImage: "lock.fill", value: value(model))
            }
            .accessibilityIdentifier("settings.appLock")
        }
    }

    /// The passcode's name is lowercase prose, so a phone without Face ID, Touch ID
    /// or Optic ID says On instead.
    private func value(_ model: AppLockModel) -> Text {
        guard model.isEnabled else {
            return Text(.settingsValueOff)
        }
        return model.capability.biometry == .passcode
            ? Text(.settingsValueOn)
            : Text(verbatim: model.capability.biometry.name)
    }
}
