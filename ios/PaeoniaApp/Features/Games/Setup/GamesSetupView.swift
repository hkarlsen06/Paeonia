import SwiftUI

/// The first time a couple opens Games: how they play and in which language. The
/// partner who arrives later skips this and sees `GamesPartnerPickedView`.
struct GamesSetupView: View {
    @Bindable var viewModel: GamesViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.sectionSpacing) {
                header
                GameSettingsOptions(playStyle: $viewModel.draftPlayStyle, language: $viewModel.draftLanguage)
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.screenTopSpacing)
            .padding(.bottom, PaeoniaSpacing.space24)
            .paeoniaReadableWidth()
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(.paeoniaBackgroundPrimary)
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await viewModel.finishSetup() }
            } label: {
                Text(.gamesSetupContinue)
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle(isLoading: viewModel.isSavingSettings))
            .accessibilityIdentifier("games.setup.continue")
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.vertical, PaeoniaSpacing.space12)
            .paeoniaReadableWidth()
            .background(.paeoniaBackgroundPrimary)
        }
        .navigationTitle(Text(.mainTabGames))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("games.setup")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            GamesBadge(systemImage: "gamecontroller.fill")
            Text(.gamesSetupTitle)
                .font(PaeoniaTypography.largeTitle)
                .foregroundStyle(.paeoniaTextPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(.gamesSetupSubtitle)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A round accent badge with a symbol, used at the top of the Games screens.
struct GamesBadge: View {
    let systemImage: String
    @ScaledMetric(relativeTo: .title) private var size: CGFloat = 56

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.paeoniaTextInverse)
            .frame(width: size, height: size)
            .background(.paeoniaAccentPrimary, in: Circle())
            .accessibilityHidden(true)
    }
}

/// Shown once to the partner who opens Games after the other one set it up.
struct GamesPartnerPickedView: View {
    let viewModel: GamesViewModel
    let settings: RemoteGameSettings
    @State private var isChangingSettings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.sectionSpacing) {
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
                    GamesBadge(systemImage: "heart.fill")
                    Text(.gamesPartnerPickedTitle(viewModel.partnerName))
                        .font(PaeoniaTypography.largeTitle)
                        .foregroundStyle(.paeoniaTextPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text(.gamesPartnerPickedSubtitle)
                        .font(PaeoniaTypography.body)
                        .foregroundStyle(.paeoniaTextSecondary)
                }

                VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
                    summaryRow(title: .gamesSetupPlayStyleTitle, value: settings.playStyle.title)
                    summaryRow(title: .gamesSetupLanguageTitle, value: settings.language.title)
                }
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.screenTopSpacing)
            .paeoniaReadableWidth()
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(.paeoniaBackgroundPrimary)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: PaeoniaSpacing.space8) {
                Button {
                    Task { await viewModel.acknowledgePartnerPicked() }
                } label: {
                    Text(.gamesPartnerPickedContinue)
                }
                .buttonStyle(PaeoniaPrimaryButtonStyle())
                .accessibilityIdentifier("games.partnerPicked.continue")

                Button {
                    isChangingSettings = true
                } label: {
                    Text(.gamesPartnerPickedChange)
                }
                .buttonStyle(PaeoniaSecondaryButtonStyle())
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.vertical, PaeoniaSpacing.space12)
            .paeoniaReadableWidth()
            .background(.paeoniaBackgroundPrimary)
        }
        .navigationTitle(Text(.mainTabGames))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isChangingSettings) {
            GamesSettingsSheet(viewModel: viewModel)
        }
        .accessibilityIdentifier("games.partnerPicked")
    }

    private func summaryRow(title: LocalizedStringResource, value: LocalizedStringResource) -> some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
            Text(title)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextTertiary)
            Text(value)
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaTextPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PaeoniaSpacing.cardContentPadding)
        .background(.paeoniaSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Changing the play style or the language after setup. The last change wins for
/// the couple.
struct GamesSettingsSheet: View {
    let viewModel: GamesViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var playStyle: GamePlayStyle
    @State private var language: GameLanguage

    init(viewModel: GamesViewModel) {
        self.viewModel = viewModel
        _playStyle = State(initialValue: viewModel.draftPlayStyle)
        _language = State(initialValue: viewModel.draftLanguage)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PaeoniaSpacing.sectionSpacing) {
                    GameSettingsOptions(playStyle: $playStyle, language: $language)
                    Text(.gamesSettingsLanguageNote)
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                .padding(.top, PaeoniaSpacing.space16)
                .padding(.bottom, PaeoniaSpacing.space24)
                .paeoniaReadableWidth()
            }
            .background(.paeoniaBackgroundPrimary)
            .navigationTitle(Text(.gamesSettingsTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .presentationDetents([.large])
        .presentationBackground(.paeoniaBackgroundPrimary)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(role: .cancel) {
                dismiss()
            } label: {
                Text(.commonCancel)
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button {
                Task {
                    if await viewModel.saveSettings(playStyle: playStyle, language: language) {
                        dismiss()
                    }
                }
            } label: {
                Text(.gamesSettingsSave)
            }
            .disabled(viewModel.isSavingSettings)
            .accessibilityIdentifier("games.settings.save")
        }
    }
}
