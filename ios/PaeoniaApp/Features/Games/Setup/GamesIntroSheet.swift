import SwiftUI

/// The steps before this person's first game, in one sheet: the couple's
/// settings, or what the partner picked, and then the mark on their pieces.
/// The game opens when the sheet closes after the mark step.
struct GamesIntroSheet: View {
    @Bindable var viewModel: GamesViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    var body: some View {
        switch viewModel.introStep {
        case .setup:
            settingsStep {
                GamesSetupView(viewModel: viewModel)
            }
        case let .partnerPicked(settings):
            settingsStep {
                GamesPartnerPickedView(viewModel: viewModel, settings: settings)
            }
        case let .mark(model):
            BoardMarkEditorView(color: .boardGameMine, model: model)
        case nil:
            EmptyView()
        }
    }

    /// The sheet covers the app's top banner, so it mounts its own copy for a
    /// failed save.
    private func settingsStep(@ViewBuilder content: () -> some View) -> some View {
        NavigationStack {
            content()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Text(.commonCancel)
                        }
                        .disabled(viewModel.isSavingSettings)
                        .accessibilityIdentifier("games.intro.cancel")
                    }
                }
        }
        .paeoniaTopBanner(bannerCenter)
        .presentationBackground(.paeoniaBackgroundPrimary)
        .interactiveDismissDisabled(viewModel.isSavingSettings)
    }
}
