import PhotosUI
import SwiftUI

/// Taps on Continue while profile setup still has no photo. Each tap replays the
/// nudge on the photo, and any tap at all keeps the callout up until a photo is in.
struct AuthOnboardingPhotoNudge: Equatable {
    private(set) var taps = 0

    /// Continue was tapped at least once without a photo.
    var hasTapped: Bool {
        taps > 0
    }

    mutating func replay() {
        taps += 1
    }
}

/// The photo picker on profile setup. Without a photo it is a dashed circle that asks
/// for one. After Continue was tapped without a photo, the circle shakes, its ring
/// warms to the accent color and glows twice, and a callout under it says why. The
/// callout opens the picker too. Reduce Motion keeps the color change and fades the
/// callout in, without the shake or the glow.
struct AuthOnboardingPhotoField: View {
    @Binding var selection: PhotosPickerItem?
    let image: Image?
    let savedPhotoAssetID: UUID?
    let name: String
    let nudge: AuthOnboardingPhotoNudge
    let isDisabled: Bool
    let isFocused: AccessibilityFocusState<Bool>.Binding

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasPhoto: Bool {
        image != nil || savedPhotoAssetID != nil
    }

    private var showsCallout: Bool {
        nudge.hasTapped && !hasPhoto
    }

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            picker

            if showsCallout {
                callout
                    .transition(calloutTransition)
            }
        }
        // Full width with or without the callout, so the photo stays put sideways
        // while the callout grows in.
        .frame(maxWidth: .infinity)
    }

    private var picker: some View {
        // The picker's label closure is not on the main actor, so it gets a ready-made view.
        let preview = AuthOnboardingPhotoPreview(
            image: image,
            savedPhotoAssetID: savedPhotoAssetID,
            name: name,
            isWarm: showsCallout
        )
        return PhotosPicker(selection: $selection, matching: .images, photoLibrary: .shared()) {
            preview
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .keyframeAnimator(
            initialValue: NudgeFrame(),
            // Reduce Motion never starts the keyframes.
            trigger: reduceMotion ? 0 : nudge.taps
        ) { content, frame in
            content
                .background {
                    Circle()
                        .fill(.paeoniaAccentPrimary)
                        .blur(radius: 16)
                        .opacity(frame.glow * 0.7)
                        .scaleEffect(1 + frame.glow * 0.15)
                }
                .offset(x: frame.shake)
        } keyframes: { _ in
            KeyframeTrack(\.shake) {
                // A damped "no": swings that start at 15 points and settle in about
                // half a second.
                CubicKeyframe(-15, duration: 0.07)
                CubicKeyframe(13, duration: 0.09)
                CubicKeyframe(-9, duration: 0.09)
                CubicKeyframe(5, duration: 0.08)
                CubicKeyframe(-2, duration: 0.07)
                CubicKeyframe(0, duration: 0.08)
            }
            KeyframeTrack(\.glow) {
                CubicKeyframe(1, duration: 0.25)
                CubicKeyframe(0.2, duration: 0.3)
                CubicKeyframe(0.9, duration: 0.3)
                CubicKeyframe(0, duration: 0.45)
            }
        }
        .accessibilityLabel(Text(hasPhoto ? .authOnboardingProfilePhotoChange : .authOnboardingProfilePhotoAdd))
        .accessibilityHint(showsCallout ? Text(.authOnboardingProfilePhotoRequired) : Text(verbatim: ""))
        .accessibilityFocused(isFocused)
        .accessibilityIdentifier("auth.onboarding.profilePhoto")
    }

    private var callout: some View {
        PhotosPicker(selection: $selection, matching: .images, photoLibrary: .shared()) {
            AuthOnboardingPhotoCallout()
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityIdentifier("auth.onboarding.profilePhotoCallout")
    }

    /// An inserted view gets its final place at once while the content under it is
    /// still moving down, so the callout waits a beat and grows into the gap instead
    /// of drawing over the title.
    private var calloutTransition: AnyTransition {
        reduceMotion
            ? .asymmetric(
                insertion: .opacity.animation(PaeoniaMotion.stateChange.delay(Self.calloutDelay)),
                removal: .opacity
            )
            : .asymmetric(
                insertion: .scale(scale: 0.8, anchor: .top).combined(with: .opacity)
                    .animation(PaeoniaMotion.cardReveal.delay(Self.calloutDelay)),
                removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .top))
            )
    }

    private static let calloutDelay: TimeInterval = 0.15
}

/// One frame of the nudge: how far the photo is pushed sideways and how bright its
/// glow is, from 0 to 1.
private struct NudgeFrame {
    var shake: CGFloat = 0
    var glow: CGFloat = 0
}

/// The bubble under the photo that says a photo is needed, with a small arrow up at it.
private struct AuthOnboardingPhotoCallout: View {
    private static let arrowSize = CGSize(width: 20, height: 9)

    var body: some View {
        let shape = CalloutBubbleShape(arrowSize: Self.arrowSize)

        HStack(spacing: PaeoniaSpacing.space12) {
            Image(systemName: "camera.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.paeoniaAccentPrimary)
                .accessibilityHidden(true)

            Text(.authOnboardingProfilePhotoRequired)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, PaeoniaSpacing.space16)
        .padding(.vertical, PaeoniaSpacing.space12)
        .padding(.top, Self.arrowSize.height)
        .background {
            shape
                .fill(.paeoniaSurfacePrimary)
                .overlay {
                    shape.fill(.paeoniaAccentPrimary.opacity(0.14))
                }
                .overlay {
                    shape.stroke(.paeoniaAccentPrimary.opacity(0.45), lineWidth: PaeoniaRadius.strokeDefault)
                }
        }
        .contentShape(shape)
    }
}

/// A rounded rectangle with a small triangle on top, in the middle, pointing up.
nonisolated private struct CalloutBubbleShape: Shape {
    let arrowSize: CGSize

    func path(in rect: CGRect) -> Path {
        let body = CGRect(
            x: rect.minX,
            y: rect.minY + arrowSize.height,
            width: rect.width,
            height: rect.height - arrowSize.height
        )
        let bubble = Path(roundedRect: body, cornerRadius: PaeoniaRadius.radius16, style: .continuous)

        var arrow = Path()
        arrow.move(to: CGPoint(x: rect.midX - arrowSize.width / 2, y: body.minY + 1))
        arrow.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control: CGPoint(x: rect.midX - arrowSize.width / 6, y: body.minY)
        )
        arrow.addQuadCurve(
            to: CGPoint(x: rect.midX + arrowSize.width / 2, y: body.minY + 1),
            control: CGPoint(x: rect.midX + arrowSize.width / 6, y: body.minY)
        )
        arrow.closeSubpath()

        return bubble.union(arrow)
    }
}
