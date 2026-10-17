import SwiftUI

/// The round photo in the profile picker, with its add or change badge.
struct AuthOnboardingPhotoPreview: View {
    let image: Image?
    let savedPhotoAssetID: UUID?
    let name: String
    let hasPhoto: Bool
    let showsPhotoRequiredHint: Bool

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .scaledToFill()
            } else if let savedPhotoAssetID {
                PaeoniaProfilePhotoAvatar(
                    mediaAssetID: savedPhotoAssetID,
                    name: name,
                    tint: .paeoniaPartnerOne,
                    size: 88
                )
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(PaeoniaSpacing.space12)
                    .foregroundStyle(.paeoniaTextTertiary)
            }
        }
        .frame(width: 88, height: 88)
        .background(.paeoniaSurfaceSecondary)
        .clipShape(Circle())
        .overlay {
            Circle()
                .strokeBorder(
                    .paeoniaAccentPrimary.opacity(showsPhotoRequiredHint ? 1 : 0.25),
                    lineWidth: showsPhotoRequiredHint ? 2 : 1
                )
        }
        .animation(PaeoniaMotion.stateChange, value: showsPhotoRequiredHint)
        .accessibilityHidden(true)
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: hasPhoto ? "pencil.circle.fill" : "plus.circle.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.paeoniaAccentPrimary)
                .contentTransition(.symbolEffect(.replace))
                .background(Circle().fill(.paeoniaBackgroundPrimary))
                .accessibilityHidden(true)
        }
    }
}
