import SwiftUI

struct WidgetDrawingDescriptionSheet: View {
    @Binding var text: String
    @Environment(\.dismiss) private var dismiss
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    private var isTooLong: Bool { text.unicodeScalars.count > 500 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(text: $text, axis: .vertical) { Text(.drawingDescriptionTitle) }
                        .accessibilityIdentifier("widgetDrawing.description.text")
                    if isTooLong {
                        Text(.drawingDescriptionTooLong)
                            .foregroundStyle(.paeoniaErrorText)
                    }
                } footer: {
                    Text(.drawingDescriptionHint)
                }
            }
            .paeoniaGroupedList()
            .navigationTitle(Text(.mediaAccessibilityDrawingDescription))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(.commonDone) { dismiss() }
                        .disabled(isTooLong)
                        .accessibilityIdentifier("widgetDrawing.description.done")
                }
            }
        }
        .preferredColorScheme(.dark)
        .paeoniaBanner(bannerCenter)
    }
}
