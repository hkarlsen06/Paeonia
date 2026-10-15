import SwiftUI

/// The two quiet buttons under the tiles: "Show a letter" and "Show me". Both
/// ask first when asking costs something. They fade out on the reveal and keep
/// their space, so nothing below the tiles jumps.
struct DrawAndGuessGuessActions: View {
    let viewModel: DrawAndGuessViewModel
    let isRevealed: Bool

    @State private var isShowMeAlertPresented = false
    @State private var isHintAlertPresented = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: PaeoniaSpacing.space8) {
                hintButton
                showMeButton
            }
            VStack(spacing: PaeoniaSpacing.space4) {
                hintButton
                showMeButton
            }
        }
        .opacity(isRevealed ? 0 : 1)
        .animation(PaeoniaMotion.stateChange, value: isRevealed)
        .disabled(isRevealed)
        .accessibilityHidden(isRevealed)
        .alert(Text(.gamesDrawAndGuessShowMeConfirmTitle), isPresented: $isShowMeAlertPresented) {
            Button {
                Task { await viewModel.giveUp() }
            } label: {
                Text(.gamesDrawAndGuessShowMe)
            }
            Button(role: .cancel) {} label: {
                Text(.gamesDrawAndGuessKeepGuessing)
            }
        } message: {
            Text(.gamesDrawAndGuessShowMeConfirmMessage)
        }
        .alert(Text(.gamesDrawAndGuessHintConfirmTitle), isPresented: $isHintAlertPresented) {
            Button {
                showLetter()
            } label: {
                Text(.gamesDrawAndGuessHint)
            }
            Button(role: .cancel) {} label: {
                Text(.gamesDrawAndGuessKeepGuessing)
            }
        } message: {
            Text(.gamesDrawAndGuessHintConfirmMessage)
        }
    }

    private var hintButton: some View {
        Button {
            if viewModel.needsHintWarning {
                isHintAlertPresented = true
            } else {
                showLetter()
            }
        } label: {
            Text(.gamesDrawAndGuessHint)
        }
        .buttonStyle(PaeoniaQuietButtonStyle())
        .disabled(!viewModel.canShowLetter)
        .accessibilityIdentifier("draw.hint")
    }

    private var showMeButton: some View {
        Button {
            isShowMeAlertPresented = true
        } label: {
            Text(.gamesDrawAndGuessShowMe)
        }
        .buttonStyle(PaeoniaQuietButtonStyle())
        .accessibilityIdentifier("draw.showMe")
    }

    private func showLetter() {
        let hintedBefore = Set(viewModel.slots.hintedIndexes)
        viewModel.showLetter()
        let slots = viewModel.slots
        guard let index = slots.hintedIndexes.first(where: { !hintedBefore.contains($0) }) else { return }
        let letter = Array(slots.answer)[index]
        let number = slots.slots.prefix(index + 1).count { !$0.isGap }
        PaeoniaHaptics.selection()
        GameSound.tick.play()
        AccessibilityNotification.Announcement(
            String(localized: .gamesDrawAndGuessGuessHintPlaced(String(letter), number))
        ).post()
    }
}
