import SwiftUI

struct AvatarDecorationPicker: View {
    let model: AvatarStylingModel
    let name: String
    let photoAssetID: UUID?
    @State private var selection: AvatarDecoration
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(PaeoniaBannerCenter.self) private var banners

    init(model: AvatarStylingModel, name: String, photoAssetID: UUID?) {
        self.model = model
        self.name = name
        self.photoAssetID = photoAssetID
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
        .paeoniaTopBanner(banners)
        .navigationTitle(Text(.avatarDecorationTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: { Text(.commonCancel) }
                    .disabled(model.isSaving)
                    .accessibilityIdentifier("avatarDecoration.cancel")
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
        }
        .interactiveDismissDisabled(model.isSaving)
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
            .background(.paeoniaSurfacePrimary, in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius16))
            .overlay {
                RoundedRectangle(cornerRadius: PaeoniaRadius.radius16)
                    .strokeBorder(selection == decoration ? Color.paeoniaAccentPrimary : .clear, lineWidth: 2)
            }
            .contentShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius16))
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
