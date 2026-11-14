import AVKit
import SwiftUI

/// One side's video from the call engine, which keeps the view current while the call runs.
struct CallVideoView: UIViewRepresentable {
    let engine: any CallEngineActions
    let source: CallVideoSource

    func makeUIView(context _: Context) -> UIView {
        let view = engine.makeVideoView(source)
        view.clipsToBounds = true
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        return view
    }

    func updateUIView(_: UIView, context _: Context) {}
}

/// The system's picker for AirPods, a headset or a car, which the call screen shows in place of
/// the speaker button while one is connected.
struct CallRoutePicker: UIViewRepresentable {
    func makeUIView(context _: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .white
        picker.activeTintColor = .white
        picker.prioritizesVideoDevices = false
        return picker
    }

    func updateUIView(_: AVRoutePickerView, context _: Context) {}
}
