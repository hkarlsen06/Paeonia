import SwiftUI

struct DailyMediaAccessibilityText: View {
    let text: String?
    let isVoice: Bool
    var editingTarget: MediaAlternativeTarget?

    var body: some View {
        MediaAlternativeReadout(text: text, isVoice: isVoice, editingTarget: editingTarget)
    }
}
