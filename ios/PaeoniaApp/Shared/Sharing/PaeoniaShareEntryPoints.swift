import SwiftUI

extension View {
    /// Presents `PaeoniaShareSheet` for the item. Set the binding to open it.
    func paeoniaShareSheet(item: Binding<PaeoniaShareable?>) -> some View {
        sheet(item: item) { shareable in
            PaeoniaShareSheet(shareable: shareable)
        }
    }

    /// A share button in the trailing toolbar that opens `PaeoniaShareSheet`.
    /// Pass nil while there is nothing to share, such as an empty canvas or a
    /// drawing that has not loaded, and the button stays away.
    func paeoniaShareToolbar(_ shareable: PaeoniaShareable?, identifier: String = "share.open") -> some View {
        modifier(PaeoniaShareToolbar(shareable: shareable, identifier: identifier))
    }
}

private struct PaeoniaShareToolbar: ViewModifier {
    let shareable: PaeoniaShareable?
    let identifier: String

    @State private var presented: PaeoniaShareable?

    func body(content: Content) -> some View {
        content
            .toolbar {
                if let shareable {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            PaeoniaHaptics.selection()
                            presented = shareable
                        } label: {
                            Label {
                                Text(shareable.actionTitle)
                            } icon: {
                                Image(systemName: shareable.actionSymbol)
                            }
                        }
                        .accessibilityIdentifier(identifier)
                    }
                }
            }
            .paeoniaShareSheet(item: $presented)
    }
}
