#if DEBUG
  import SwiftUI

  nonisolated extension DeveloperScenario {
    static let keyboardDiagnostics: [DeveloperScenario] = [
      keyboardPlainForm, keyboardToolbarForm, keyboardSingleItemForm
    ]

    static let keyboardPlainForm = DeveloperScenario(
      "keyboard-plain-form", "Keyboard · native Form",
      "Minimal presented Form without a keyboard toolbar, for runtime diagnostics", .settings
    ) { _ in DeveloperKeyboardDiagnosticView(toolbar: .none) }

    static let keyboardToolbarForm = DeveloperScenario(
      "keyboard-toolbar-form", "Keyboard · native Form and toolbar",
      "The same Form with only a native keyboard Done button, for runtime diagnostics", .settings
    ) { _ in DeveloperKeyboardDiagnosticView(toolbar: .spacerGroup) }
  }

  nonisolated extension DeveloperScenario {
    static let keyboardSingleItemForm = DeveloperScenario(
      "keyboard-single-item-form", "Keyboard · native single item",
      "The same Form with a single native keyboard Done item, for runtime diagnostics", .settings
    ) { _ in DeveloperKeyboardDiagnosticView(toolbar: .singleItem) }
  }

  private enum DiagnosticKeyboardToolbar { case none, spacerGroup, singleItem }

  /// Keep these cases free of Paeonia layout modifiers so their runtime logs can
  /// distinguish native Form/keyboard behavior from the production editor styling.
  private struct DeveloperKeyboardDiagnosticView: View {
    let toolbar: DiagnosticKeyboardToolbar
    @State private var isPresented = false

    var body: some View {
      NavigationStack {
        Button(.mediaAccessibilityDrawingDescription) { isPresented = true }
          .accessibilityIdentifier("keyboard.diagnostic.open")
      }
      .sheet(isPresented: $isPresented) {
        DeveloperKeyboardDiagnosticForm(toolbar: toolbar)
      }
    }
  }

  private struct DeveloperKeyboardDiagnosticForm: View {
    let toolbar: DiagnosticKeyboardToolbar
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
      NavigationStack {
        formContent
          .navigationTitle(Text(.mediaAccessibilityDrawingDescription))
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .confirmationAction) {
              Button(.commonDone) { dismiss() }
                .accessibilityIdentifier("keyboard.diagnostic.sheet.done")
            }
          }
      }
    }

    @ViewBuilder
    private var formContent: some View {
      switch toolbar {
      case .spacerGroup:
        form.toolbar {
          ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button(.commonDone) { isFocused = false }
              .accessibilityIdentifier("keyboard.diagnostic.keyboard.done")
          }
        }
      case .singleItem:
        form.toolbar {
          ToolbarItem(placement: .keyboard) {
            Button(.commonDone) { isFocused = false }
              .accessibilityIdentifier("keyboard.diagnostic.keyboard.done")
          }
        }
      case .none:
        form
      }
    }

    private var form: some View {
      Form {
        TextField(text: $text, axis: .vertical) {
          Text(.mediaAccessibilityDrawingDescription)
        }
        .focused($isFocused)
        .accessibilityIdentifier("keyboard.diagnostic.text")
      }
    }
  }
#endif
