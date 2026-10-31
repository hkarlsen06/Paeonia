import SwiftUI
import UIKit

/// A growing plain-text editor that colors overflow without replacing the text
/// while the person types, so selection, undo and keyboard composition survive.
struct StoryChainDraftField: UIViewRepresentable {
    @Binding var text: String
    @Binding var focus: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true
        view.autocorrectionType = .yes
        view.tintColor = UIColor(StoryChainPageStyle.mineInk)
        view.text = text
        style(view)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text { view.text = text }
        style(view)
        // UIKit asks SwiftUI for its next responder. Do that after this graph update ends.
        Task { @MainActor [weak view, coordinator = context.coordinator] in
            guard let view else { return }
            if coordinator.parent.focus, !view.isFirstResponder {
                view.becomeFirstResponder()
            } else if !coordinator.parent.focus, view.isFirstResponder {
                view.resignFirstResponder()
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context _: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: fitted.height)
    }

    private func style(_ view: UITextView) {
        // Wait for an input method to commit its marked text before recoloring it.
        guard view.markedTextRange == nil else { return }
        let descriptor = UIFont.preferredFont(
            forTextStyle: .title3, compatibleWith: view.traitCollection
        ).fontDescriptor
        let font = UIFont(descriptor: descriptor.withDesign(.serif) ?? descriptor, size: 0)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = StoryChainPageStyle.lineSpacing
        let ink = UIColor(StoryChainPageStyle.mineInk)
        let errorInk = UIColor(Color.paeoniaErrorText)
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: ink, .paragraphStyle: paragraph,
        ]
        let draft = view.text ?? ""
        if view.font != font { view.font = font }
        view.textStorage.beginEditing()
        view.textStorage.setAttributes(attributes, range: NSRange(draft.startIndex..., in: draft))
        if let start = StoryChainRules.overflowStart(in: draft) {
            let range = NSRange(start..., in: draft)
            view.textStorage.addAttribute(.foregroundColor, value: errorInk, range: range)
            if view.selectedRange.location >= range.location {
                attributes[.foregroundColor] = errorInk
            }
        }
        view.textStorage.endEditing()
        view.typingAttributes = attributes
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: StoryChainDraftField

        init(parent: StoryChainDraftField) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            parent.style(textView)
        }

        func textViewDidBeginEditing(_: UITextView) {
            if !parent.focus { parent.focus = true }
        }

        func textViewDidEndEditing(_: UITextView) {
            if parent.focus { parent.focus = false }
        }
    }
}
