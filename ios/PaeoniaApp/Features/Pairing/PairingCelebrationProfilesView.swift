import SwiftUI
import UIKit

/// The heart that forms at the center: a soft dark well that reads as the gravity
/// core, haloed in accent light, with the heart symbol on top. The rim is built
/// from a blurred glow plus a faint gradient edge so it feels lit rather than
/// outlined.
struct PairingCelebrationHeartCore: View {
    var body: some View {
        ZStack {
            darkWell
            softHalo
            lightRim
            Image(systemName: "heart.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.paeoniaAccentPrimary)
                .shadow(color: .paeoniaAccentPrimary.opacity(0.55), radius: 10)
        }
        .accessibilityHidden(true)
    }

    private var darkWell: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        .black.opacity(0.5),
                        .black.opacity(0.34),
                        .clear
                    ],
                    center: .center,
                    startRadius: 6,
                    endRadius: 84
                )
            )
            .frame(width: 168, height: 168)
    }

    private var softHalo: some View {
        Circle()
            .stroke(.paeoniaAccentPrimary.opacity(0.4), lineWidth: 6)
            .frame(width: 118, height: 118)
            .blur(radius: 6)
    }

    private var lightRim: some View {
        Circle()
            .stroke(
                LinearGradient(
                    colors: [
                        .paeoniaAccentPrimary.opacity(0.6),
                        .paeoniaAccentSecondary.opacity(0.2)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1.5
            )
            .frame(width: 122, height: 122)
    }
}

/// A circular avatar showing a person's profile photo, falling back to initials.
/// Used both in the linked row and as the hero avatar that bursts from the heart
/// and flies into place. The fixed diameter is scaled up via `scaleEffect` when
/// shown large, so the whole avatar scales cleanly.
struct PairingCelebrationAvatar: View {
    static let diameter: CGFloat = 84

    let name: String
    let tint: Color
    let imageData: Data?

    init(name: String, tint: Color, imageData: Data? = nil) {
        self.name = name
        self.tint = tint
        self.imageData = imageData
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.18))

            if let profileImage {
                Image(uiImage: profileImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: Self.diameter, height: Self.diameter)
                    .clipShape(Circle())
            } else {
                initials
            }

            Circle()
                .strokeBorder(tint.opacity(0.82), lineWidth: 1.5)
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .accessibilityLabel(Text(name))
    }

    private var initials: some View {
        Text(Self.initials(for: name))
            .font(.system(size: Self.diameter * 0.33, weight: .semibold, design: .rounded))
            .foregroundStyle(.paeoniaTextPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private var profileImage: UIImage? {
        guard let imageData else {
            return nil
        }

        return UIImage(data: imageData)
    }

    static func initials(for name: String) -> String {
        let parts = name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }

        if parts.isEmpty {
            return "?"
        }

        return parts.map { String($0).uppercased() }.joined()
    }
}

/// The final, settled state: the two people with a connecting line between their
/// avatars and a heart centered on that line. The line aligns to the vertical
/// center of both avatar circles via a custom alignment guide.
///
/// During the intro the partner's avatar flies in from the center, so the partner
/// slot is left as a space-reserving placeholder that publishes its frame (the
/// flying avatar then lands exactly over it). Everything except the partner avatar
/// fades in together through `surroundingsOpacity`.
struct PairingCelebrationProfilesView: View {
    let currentName: String
    let currentPhotoData: Data?
    let partnerName: String
    let partnerPhotoData: Data?
    /// When true the partner slot is an invisible placeholder and the partner
    /// avatar is drawn as a flying overlay above this view; when false the avatar
    /// is drawn in place (used when the intro is skipped).
    let partnerSlotIsPlaceholder: Bool
    let surroundingsOpacity: Double
    let slotCoordinateSpace: String
    let onPartnerSlotChange: (CGRect) -> Void

    private let columnWidth: CGFloat = 112

    var body: some View {
        HStack(alignment: .avatarCenter, spacing: 0) {
            column(name: currentName) {
                PairingCelebrationAvatar(
                    name: currentName,
                    tint: .paeoniaPartnerOne,
                    imageData: currentPhotoData
                )
                    .alignmentGuide(.avatarCenter) { _ in PairingCelebrationAvatar.diameter / 2 }
            }
            .opacity(surroundingsOpacity)

            connector
                .opacity(surroundingsOpacity)

            column(name: partnerName, nameOpacity: surroundingsOpacity) {
                partnerSlot
                    .alignmentGuide(.avatarCenter) { _ in PairingCelebrationAvatar.diameter / 2 }
            }
        }
        .frame(maxWidth: .infinity)
        .onPreferenceChange(PartnerSlotPreferenceKey.self) { onPartnerSlotChange($0) }
    }

    private func column<Avatar: View>(
        name: String,
        nameOpacity: Double = 1,
        @ViewBuilder avatar: () -> Avatar
    ) -> some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            avatar()

            Text(name)
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .opacity(nameOpacity)
        }
        .frame(width: columnWidth)
    }

    @ViewBuilder
    private var partnerSlot: some View {
        if partnerSlotIsPlaceholder {
            // Reserve the avatar's space and publish where it sits so the flying
            // avatar can land exactly here.
            Color.clear
                .frame(width: PairingCelebrationAvatar.diameter, height: PairingCelebrationAvatar.diameter)
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: PartnerSlotPreferenceKey.self,
                            value: geometry.frame(in: .named(slotCoordinateSpace))
                        )
                    }
                )
        } else {
            PairingCelebrationAvatar(
                name: partnerName,
                tint: .paeoniaPartnerTwo,
                imageData: partnerPhotoData
            )
        }
    }

    private var connector: some View {
        ZStack {
            Rectangle()
                .fill(.paeoniaAccentPrimary.opacity(0.6))
                .frame(width: 82, height: 1.5)

            Circle()
                .fill(.paeoniaBackgroundPrimary)
                .frame(width: 34, height: 34)

            Circle()
                .stroke(.paeoniaAccentPrimary.opacity(0.72), lineWidth: 1.2)
                .frame(width: 34, height: 34)

            Image(systemName: "heart.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.paeoniaAccentPrimary)
        }
        .frame(width: 82, height: 34)
        .accessibilityHidden(true)
    }
}

private struct PartnerSlotPreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

private extension VerticalAlignment {
    /// Aligns the connecting line and heart to the vertical center of the avatar
    /// circles, independent of the name labels beneath them.
    enum AvatarCenter: AlignmentID {
        static func defaultValue(in dimensions: ViewDimensions) -> CGFloat {
            dimensions[VerticalAlignment.center]
        }
    }

    static let avatarCenter = VerticalAlignment(AvatarCenter.self)
}
