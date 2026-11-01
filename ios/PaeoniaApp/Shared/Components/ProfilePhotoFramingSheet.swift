import SwiftUI
import UIKit

struct ProfilePhotoFramingSheet: View {
    let image: UIImage
    let onApply: (CGRect) -> Void
    @Environment(\.dismiss) private var dismiss
    @State var framing: ProfilePhotoFraming

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    preview
                        .accessibilityLabel(Text(.imageCropPreview))
                }
                framingControls
                    .listRowBackground(Color.paeoniaSurfacePrimary)
            }
            .paeoniaGroupedList()
            .navigationTitle(Text(.imageCropAdjustFraming))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(.commonCancel) { dismiss() }
                        .accessibilityIdentifier("imageCrop.cancelFraming")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(.imageCropApplyFraming) {
                        onApply(framing.crop)
                        dismiss()
                    }
                    .accessibilityIdentifier("imageCrop.applyFraming")
                }
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
    }

    private var framingControls: some View {
        Section {
            Stepper(value: $framing.zoom, in: 1...framing.maximumZoom, step: 0.25) {
                VStack(alignment: .leading) {
                    Text(.imageCropZoom)
                    Text(framing.zoom, format: .number.precision(.fractionLength(2)))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel(Text(.imageCropZoom))
            .accessibilityValue(Text(framing.zoom, format: .number.precision(.fractionLength(2))))
            .accessibilityIdentifier("imageCrop.zoom")
            positionControl(
                .imageCropHorizontalPosition,
                value: $framing.horizontalPosition,
                disabled: framing.crop.width >= image.size.width,
                identifier: "imageCrop.horizontalPosition"
            )
            positionControl(
                .imageCropVerticalPosition,
                value: $framing.verticalPosition,
                disabled: framing.crop.height >= image.size.height,
                identifier: "imageCrop.verticalPosition"
            )
            Button(.imageCropResetFraming) { framing.reset() }
                .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
                .accessibilityIdentifier("imageCrop.resetFraming")
        } footer: {
            Text(.imageCropFramingInstructions)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
        }
    }

    private var preview: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    let crop = framing.crop
                    let scale = proxy.size.width / crop.width
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: image.size.width * scale, height: image.size.height * scale)
                        .offset(x: -crop.minX * scale, y: -crop.minY * scale)
                }
                .clipped()
                .accessibilityHidden(true)
            }
            .frame(maxWidth: 240)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isImage)
    }

    private func positionControl(
        _ title: LocalizedStringResource,
        value: Binding<Double>,
        disabled: Bool,
        identifier: String
    ) -> some View {
        Stepper(value: value, in: 0...1, step: 0.05) {
            VStack(alignment: .leading) {
                Text(title)
                Text(value.wrappedValue, format: .percent.precision(.fractionLength(0)))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(value.wrappedValue, format: .percent.precision(.fractionLength(0))))
        .disabled(disabled)
        .accessibilityIdentifier(identifier)
    }
}
