import SwiftUI

struct GameContinueLabel: View {
    let title: LocalizedStringResource
    let partnerName: String
    let continuation: GameContinuation?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(continuation?.title(partnerName: partnerName) ?? title)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, PaeoniaSpacing.space8)
            .contentTransition(.opacity)
            .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: continuation)
    }
}
