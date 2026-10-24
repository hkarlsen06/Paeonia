import SwiftUI

/// The round photo in the profile picker. Without a photo it asks for one: a camera
/// and "Add photo" inside a dashed accent ring, which turns solid and brighter while
/// the photo is what still blocks Continue (`isWarm`). With a photo it shows the photo
/// and a change badge.
struct AuthOnboardingPhotoPreview: View {
    let image: Image?
    let savedPhotoAssetID: UUID?
    let name: String
    let isWarm: Bool

    static let size: CGFloat = 112

    var body: some View {
        ZStack {
            if let image {
                image
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else if let savedPhotoAssetID {
                PaeoniaProfilePhotoAvatar(
                    mediaAssetID: savedPhotoAssetID,
                    name: name,
                    tint: .paeoniaPartnerOne,
                    size: Self.size
                )
            } else {
                emptyInvitation
                    .transition(.opacity)
            }
        }
        .frame(width: Self.size, height: Self.size)
        .background(.paeoniaSurfaceSecondary)
        .clipShape(Circle())
        .overlay {
            ring
        }
        .overlay(alignment: .bottomTrailing) {
            if hasPhoto {
                Image(systemName: "pencil.circle.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.paeoniaAccentPrimary)
                    .background(Circle().fill(.paeoniaBackgroundPrimary))
                    .offset(x: -4, y: -4)
                    .accessibilityHidden(true)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(PaeoniaMotion.stateChange, value: isWarm)
        .accessibilityHidden(true)
    }

    private var hasPhoto: Bool {
        image != nil || savedPhotoAssetID != nil
    }

    private var emptyInvitation: some View {
        VStack(spacing: PaeoniaSpacing.space4) {
            Image(systemName: "camera.fill")
                .font(.title2.weight(.semibold))
                .accessibilityHidden(true)

            Text(.authOnboardingProfilePhotoAddLabel)
                .font(PaeoniaTypography.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(.paeoniaAccentPrimary)
        // The circle keeps its size, so the words inside stop growing at a size that fits.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .padding(PaeoniaSpacing.space12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.paeoniaAccentPrimary.opacity(isWarm ? 0.16 : 0.08))
    }

    @ViewBuilder
    private var ring: some View {
        if hasPhoto {
            Circle()
                .strokeBorder(.paeoniaAccentPrimary.opacity(0.25), lineWidth: PaeoniaRadius.strokeDefault)
        } else {
            ZStack {
                Circle()
                    .strokeBorder(
                        .paeoniaAccentPrimary.opacity(0.6),
                        style: StrokeStyle(lineWidth: PaeoniaRadius.strokeEmphasis, lineCap: .round, dash: [5, 6])
                    )
                    .opacity(isWarm ? 0 : 1)

                Circle()
                    .strokeBorder(.paeoniaAccentPrimary, lineWidth: 2.5)
                    .opacity(isWarm ? 1 : 0)
            }
        }
    }
}
