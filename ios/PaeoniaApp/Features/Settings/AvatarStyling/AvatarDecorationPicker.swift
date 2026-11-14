import SwiftUI

/// Pushed from the More tab, and shown in a sheet from the stories on Home.
///
/// Pushed, it works like the nickname screen: while the choice is unsaved, Cancel takes
/// the back button's place, so a stray swipe never drops it. A sheet always shows Cancel,
/// because it has no back button.
struct AvatarDecorationPicker: View {
    let model: AvatarStylingModel
    let name: String
    let photoAssetID: UUID?
    let isSheet: Bool
    @State private var selection: AvatarDecoration
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(PaeoniaBannerCenter.self) private var banners

    init(model: AvatarStylingModel, name: String, photoAssetID: UUID?, isSheet: Bool = false) {
        self.model = model
        self.name = name
        self.photoAssetID = photoAssetID
        self.isSheet = isSheet
        _selection = State(initialValue: model.decorations.own)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: PaeoniaSpacing.space24) {
                PaeoniaDecoratedAvatar(
                    mediaAssetID: photoAssetID, name: name, tint: .paeoniaPartnerOne,
                    size: 104, decoration: selection
                )
                .padding(.top, 104 * AvatarDecoration.maximumOutset)
                .accessibilityLabel(Text(.avatarDecorationPreview))
                .accessibilityValue(Text(selection.title))

                Text(.avatarDecorationExplanation)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .multilineTextAlignment(.center)

                LazyVGrid(columns: columns, spacing: PaeoniaSpacing.space12) {
                    ForEach(AvatarDecoration.allCases, id: \.self) { decoration in
                        choice(decoration)
                    }
                }
            }
            .padding(PaeoniaSpacing.screenHorizontalPadding)
            .paeoniaReadableWidth()
        }
        .paeoniaScreenBackground()
        .paeoniaBanner(banners)
        .navigationTitle(Text(.avatarDecorationTitle))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(holdsUnsavedChoice)
        .toolbar {
            if isSheet || holdsUnsavedChoice {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: cancel) { Text(.commonCancel) }
                        .disabled(model.isSaving)
                        .accessibilityIdentifier("avatarDecoration.cancel")
                }
            }
        }
        .paeoniaBottomBar {
            Button {
                Task { await save() }
            } label: {
                HStack {
                    if model.isSaving { ProgressView().tint(.paeoniaTextInverse) }
                    Text(model.isSaving ? .settingsProfileSaving : .avatarDecorationSave)
                }
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())
            .disabled(model.isSaving || selection == model.decorations.own)
            .accessibilityIdentifier("avatarDecoration.save")
            .padding(PaeoniaSpacing.screenHorizontalPadding)
            // Pushed on the More tab, Save sits above the tab bar, and the choices
            // would show between the two.
            .background {
                LinearGradient(
                    stops: [
                        .init(color: .paeoniaBackgroundPrimary.opacity(0), location: 0),
                        .init(color: .paeoniaBackgroundPrimary, location: 0.25)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .interactiveDismissDisabled(model.isSaving)
    }

    /// Also true during a save, so the person cannot leave before it reports back.
    private var holdsUnsavedChoice: Bool {
        selection != model.decorations.own || model.isSaving
    }

    private func cancel() {
        if isSheet {
            dismiss()
        } else {
            selection = model.decorations.own
        }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible()), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    }

    private func choice(_ decoration: AvatarDecoration) -> some View {
        Button {
            selection = decoration
        } label: {
            VStack(spacing: PaeoniaSpacing.space12) {
                PaeoniaDecoratedAvatar(
                    mediaAssetID: photoAssetID, name: name, tint: .paeoniaPartnerOne,
                    size: 64, decoration: decoration
                )
                .accessibilityHidden(true)
                .padding(.top, 64 * AvatarDecoration.maximumOutset)
                .padding(.horizontal, 64 * AvatarDecoration.maximumOutset)
                HStack(spacing: PaeoniaSpacing.space8) {
                    Text(decoration.title)
                    if selection == decoration {
                        Image(systemName: "checkmark.circle.fill").accessibilityHidden(true)
                    }
                }
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(PaeoniaSpacing.space16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isSaving)
        .accessibilityLabel(Text(decoration.title))
        .accessibilityAddTraits(selection == decoration ? .isSelected : [])
        .accessibilityIdentifier("avatarDecoration.choice.\(decoration.rawValue)")
    }

    private func save() async {
        do {
            try await model.save(selection)
            PaeoniaHaptics.profilePhotoSet()
            dismiss()
        } catch {
            banners.show(.error(
                title: String(localized: .avatarDecorationSaveFailed),
                message: String(localized: PaeoniaFailure(error) == .offline
                    ? .avatarDecorationSaveOffline : .avatarDecorationSaveOther)
            ))
        }
    }
}
