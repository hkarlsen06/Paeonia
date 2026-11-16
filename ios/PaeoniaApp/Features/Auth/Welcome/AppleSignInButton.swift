import AuthenticationServices
import SwiftUI
import UIKit

/// Where Apple's button draws its logo and its title, in points from the button's
/// leading edge.
struct AppleSignInButtonContent: Equatable {
    let logoMaxX: CGFloat
    let titleMinX: CGFloat
}

/// Apple's own Sign in with Apple button. Apple allows a custom button only with the
/// logo artwork from Apple Design Resources, and App Review checks custom buttons, so
/// the system button is the safe choice. It translates its title itself.
///
/// The button centers its logo and title as one group, so the title's left edge moves
/// with the title's length. It draws into a bitmap and exposes no layout, so
/// `onContentChange` reports where the logo and title landed, read from the button's
/// own drawing, and the other sign-in buttons line up with them.
struct AppleSignInButton: UIViewRepresentable {
    let action: () -> Void
    let onContentChange: (AppleSignInButtonContent) -> Void

    func makeUIView(context: Context) -> MeasuredAppleIDButton {
        let view = MeasuredAppleIDButton()
        view.button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        return view
    }

    func updateUIView(_ view: MeasuredAppleIDButton, context: Context) {
        context.coordinator.action = action
        view.onContentChange = onContentChange
        view.button.isEnabled = context.environment.isEnabled
        // On the wrapper, so the measured drawing stays fully opaque.
        view.alpha = context.environment.isEnabled ? 1 : 0.5
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func tapped() {
            action()
        }
    }
}

final class MeasuredAppleIDButton: UIView {
    let button = ASAuthorizationAppleIDButton(authorizationButtonType: .continue, authorizationButtonStyle: .white)
    var onContentChange: ((AppleSignInButtonContent) -> Void)?
    private var measuredSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        button.cornerRadius = PaeoniaRadius.radius16
        button.accessibilityIdentifier = "auth.signIn.apple"
        button.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        button.frame = bounds
        addSubview(button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != measuredSize, bounds.width > 0, bounds.height > 0 else {
            return
        }
        measuredSize = bounds.size
        button.layoutIfNeeded()
        guard let content = Self.measure(button) else {
            return
        }
        // SwiftUI may be in the middle of a layout pass here.
        DispatchQueue.main.async { [weak self] in
            self?.onContentChange?(content)
        }
    }

    /// Renders the button and finds its first dark run of columns, the logo, and the
    /// next dark column after it, the title's first letter. The white style draws
    /// black on white, and the corners outside the rounded shape are transparent.
    private static func measure(_ button: UIView) -> AppleSignInButtonContent? {
        let scale: CGFloat = 2
        let width = Int(button.bounds.width * scale)
        let height = Int(button.bounds.height * scale)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return nil
        }
        context.scaleBy(x: scale, y: scale)
        button.layer.render(in: context)

        let isInk = (0..<width).map { column in
            (0..<height).contains { row in
                let pixel = pixels + (row * width + column) * 4
                // Opaque and dark.
                return pixel[3] > 200 && Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2]) < 3 * 100
            }
        }
        guard let logoStart = isInk.firstIndex(of: true),
              let logoEnd = isInk[logoStart...].firstIndex(of: false),
              let titleStart = isInk[logoEnd...].firstIndex(of: true)
        else {
            return nil
        }
        return AppleSignInButtonContent(
            logoMaxX: CGFloat(logoEnd) / scale,
            titleMinX: CGFloat(titleStart) / scale
        )
    }
}
