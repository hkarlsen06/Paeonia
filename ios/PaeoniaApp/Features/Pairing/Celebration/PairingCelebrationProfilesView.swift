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
    /// The diameter used by the pairing celebration, where the flying hero avatar
    /// must land exactly over the settled slot. Also the default for callers that
    /// don't need a smaller avatar.
    static let diameter: CGFloat = 84

    let name: String
    let tint: Color
    let imageData: Data?
    let diameter: CGFloat

    init(
        name: String,
        tint: Color,
        imageData: Data? = nil,
        diameter: CGFloat = PairingCelebrationAvatar.diameter
    ) {
        self.name = name
        self.tint = tint
        self.imageData = imageData
        self.diameter = diameter
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.18))

            if let profileImage {
                Image(uiImage: profileImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: diameter, height: diameter)
                    .clipShape(Circle())
            } else {
                initials
            }

            Circle()
                .strokeBorder(tint.opacity(0.82), lineWidth: 1.5)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityLabel(Text(name))
    }

    private var initials: some View {
        Text(PaeoniaProfilePhotoAvatar.initials(for: name))
            .font(.system(size: diameter * 0.33, weight: .semibold, design: .rounded))
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
    /// Sizing and behavior that differ between the full-screen celebration and the
    /// compact copy shown at the top of the Home tab. The celebration preset must
    /// stay byte-for-byte identical to the original layout so the flying avatar
    /// still lands exactly over its settled slot.
    struct Metrics {
        var avatarDiameter: CGFloat
        var columnWidth: CGFloat
        var connectorWidth: CGFloat
        var avatarNameSpacing: CGFloat
        var nameFont: Font
        var connectorCircleDiameter: CGFloat
        var heartFontSize: CGFloat
        var connectorLineThickness: CGFloat
        /// Whether the heart beats. Only the celebration earns the live pulse; the
        /// Home tab shows a calm, static heart.
        var animatesHeartbeat: Bool
        /// Whether each avatar shows its name underneath. The Home tab toolbar
        /// drops the names so the cluster fits the navigation bar height.
        var showsNames: Bool

        static let celebration = Metrics(
            avatarDiameter: 84,
            columnWidth: 112,
            connectorWidth: 82,
            avatarNameSpacing: PaeoniaSpacing.space12,
            nameFont: PaeoniaTypography.bodyEmphasis,
            connectorCircleDiameter: 34,
            heartFontSize: 13,
            connectorLineThickness: 1.5,
            animatesHeartbeat: true,
            showsNames: true
        )

        static let compact = Metrics(
            avatarDiameter: 48,
            columnWidth: 72,
            connectorWidth: 52,
            avatarNameSpacing: PaeoniaSpacing.space8,
            nameFont: PaeoniaTypography.caption,
            connectorCircleDiameter: 22,
            heartFontSize: 9,
            connectorLineThickness: 1,
            animatesHeartbeat: false,
            showsNames: false
        )
    }

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
    var metrics: Metrics = .celebration
    let onPartnerSlotChange: (CGRect) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var heartbeatScale: CGFloat = 1

    /// The line must touch both avatar perimeters, so it spans the full
    /// center-to-center distance (one column plus the connector) minus both radii.
    private var connectorLineWidth: CGFloat {
        metrics.columnWidth + metrics.connectorWidth - metrics.avatarDiameter
    }

    var body: some View {
        HStack(alignment: .avatarCenter, spacing: 0) {
            column(name: currentName) {
                PairingCelebrationAvatar(
                    name: currentName,
                    tint: .paeoniaPartnerOne,
                    imageData: currentPhotoData,
                    diameter: metrics.avatarDiameter
                )
                    .alignmentGuide(.avatarCenter) { _ in metrics.avatarDiameter / 2 }
            }
            .opacity(surroundingsOpacity)

            connector
                .opacity(surroundingsOpacity)

            column(name: partnerName, nameOpacity: surroundingsOpacity) {
                partnerSlot
                    .alignmentGuide(.avatarCenter) { _ in metrics.avatarDiameter / 2 }
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
        VStack(spacing: metrics.avatarNameSpacing) {
            avatar()

            if metrics.showsNames {
                Text(name)
                    .font(metrics.nameFont)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .opacity(nameOpacity)
            }
        }
        .frame(width: metrics.columnWidth)
    }

    @ViewBuilder
    private var partnerSlot: some View {
        if partnerSlotIsPlaceholder {
            // Reserve the avatar's space and publish where it sits so the flying
            // avatar can land exactly here.
            Color.clear
                .frame(width: metrics.avatarDiameter, height: metrics.avatarDiameter)
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
                imageData: partnerPhotoData,
                diameter: metrics.avatarDiameter
            )
        }
    }

    private var connector: some View {
        ZStack {
            // The line overflows the connector frame on both sides so it reaches
            // all the way to the avatar circles while leaving column spacing intact.
            Rectangle()
                .fill(.paeoniaAccentPrimary.opacity(0.6))
                .frame(width: connectorLineWidth, height: metrics.connectorLineThickness)

            Circle()
                .fill(.paeoniaBackgroundPrimary)
                .frame(width: metrics.connectorCircleDiameter, height: metrics.connectorCircleDiameter)

            Circle()
                .stroke(.paeoniaAccentPrimary.opacity(0.72), lineWidth: 1.2)
                .frame(width: metrics.connectorCircleDiameter, height: metrics.connectorCircleDiameter)

            beatingHeart
        }
        .frame(width: metrics.connectorWidth, height: metrics.connectorCircleDiameter)
        .accessibilityHidden(true)
    }

    /// Always the same single image so its identity stays stable: the connector
    /// fades in during the settle spring, and any structural swap here would make
    /// SwiftUI animate the heart in from the container origin. The lub-dub pulse is
    /// driven purely by `heartbeatScale`, which scales around center without moving.
    private var beatingHeart: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: metrics.heartFontSize, weight: .semibold))
            .foregroundStyle(.paeoniaAccentPrimary)
            .accessibilityHidden(true)
            .scaleEffect(heartbeatScale)
            .task(id: reduceMotion) {
                guard metrics.animatesHeartbeat, !reduceMotion else {
                    heartbeatScale = 1
                    return
                }
                await runHeartbeat()
            }
    }

    /// Beats twice (a strong lub, a softer dub) and then rests, on a loop, so the
    /// link reads like a calm resting heart rather than a steady fast pulse.
    @MainActor
    private func runHeartbeat() async {
        while !Task.isCancelled {
            withAnimation(.easeOut(duration: 0.14)) { heartbeatScale = 1.22 }
            try? await Task.sleep(for: .seconds(0.15))

            withAnimation(.easeIn(duration: 0.16)) { heartbeatScale = 1 }
            try? await Task.sleep(for: .seconds(0.12))

            withAnimation(.easeOut(duration: 0.12)) { heartbeatScale = 1.12 }
            try? await Task.sleep(for: .seconds(0.12))

            withAnimation(.easeIn(duration: 0.2)) { heartbeatScale = 1 }
            try? await Task.sleep(for: .seconds(0.95))
        }
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
