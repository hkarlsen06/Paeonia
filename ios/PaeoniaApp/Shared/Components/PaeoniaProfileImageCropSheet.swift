import CropViewController
import SwiftUI
import TOCropViewController
import UIKit

/// Shared square crop sheet for profile images. Display surfaces can still
/// choose their own clipping shape after the cropped image is saved.
struct PaeoniaProfileImageCropSheet: UIViewControllerRepresentable {
    let image: UIImage
    let onCrop: (UIImage) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let cropViewController = CropViewController(croppingStyle: .default, image: image)
        cropViewController.delegate = context.coordinator
        cropViewController.rotateButtonsHidden = true
        cropViewController.rotateClockwiseButtonHidden = true
        cropViewController.aspectRatioPreset = CGSize(width: 1, height: 1)
        cropViewController.aspectRatioLockEnabled = true
        cropViewController.resetAspectRatioEnabled = false
        cropViewController.aspectRatioPickerButtonHidden = true
        cropViewController.doneButtonTitle = String(localized: .imageCropDone)
        cropViewController.cancelButtonTitle = String(localized: .commonCancel)

        let navigationController = UINavigationController(rootViewController: cropViewController)
        navigationController.modalPresentationStyle = .fullScreen
        return navigationController
    }

    func updateUIViewController(_: UINavigationController, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCrop: onCrop, onCancel: onCancel)
    }

    final class Coordinator: NSObject, CropViewControllerDelegate {
        private let onCrop: (UIImage) -> Void
        private let onCancel: () -> Void

        init(onCrop: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onCrop = onCrop
            self.onCancel = onCancel
        }

        func cropViewController(
            _: CropViewController,
            didCropToImage image: UIImage,
            withRect _: CGRect,
            angle _: Int
        ) {
            onCrop(image)
        }

        func cropViewController(
            _: CropViewController,
            didCropToCircularImage image: UIImage,
            withRect _: CGRect,
            angle _: Int
        ) {
            onCrop(image)
        }

        func cropViewController(
            _: CropViewController,
            didFinishCancelled cancelled: Bool
        ) {
            if cancelled {
                onCancel()
            }
        }
    }
}
