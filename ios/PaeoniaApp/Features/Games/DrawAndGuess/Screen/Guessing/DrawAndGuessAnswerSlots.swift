import SwiftUI

/// The empty slots of the answer, one per letter with a gap between words. Tapping
/// a filled slot sends its tile back. On the reveal the slots light up.
struct DrawAndGuessAnswerSlots: View {
    let viewModel: DrawAndGuessViewModel
    let timeline: DrawAndGuessRevealTimeline
    let namespace: Namespace.ID
    /// The round ended, so the slots show the answer.
    let isRevealed: Bool
    /// The right word lights up green. A missed round fills in quietly.
    let litsGreen: Bool

    @State private var availableWidth: CGFloat = 320
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var rotorNamespace

    private struct Word: Identifiable {
        let id: Int
        let slots: [DrawAndGuessSlots.Slot]
    }

    var body: some View {
        DrawAndGuessFlowLayout(spacing: PaeoniaSpacing.space16, lineSpacing: PaeoniaSpacing.space12) {
            ForEach(words) { word in
                HStack(spacing: Self.slotGap) {
                    ForEach(word.slots) { slot in
                        slotView(slot)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .modifier(DrawAndGuessShake(trigger: viewModel.wrongGuessCount, isEnabled: !reduceMotion))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
        .animation(reduceMotion ? PaeoniaMotion.buttonPress : .spring(duration: 0.16), value: viewModel.slots)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(answerDescription))
        .accessibilityRotor(Text(.gamesDrawAndGuessGuessEmptyLetters)) {
            ForEach(viewModel.slots.slots.filter { !$0.isGap && $0.tile == nil }) { slot in
                AccessibilityRotorEntry(
                    Text(.gamesDrawAndGuessSlotEmpty(number(of: slot))),
                    id: slot.id,
                    in: rotorNamespace
                )
            }
        }
        .accessibilityIdentifier("draw.guess.slots")
    }

    private static let slotGap: CGFloat = 4

    // MARK: Layout

    private var words: [Word] {
        var groups: [[DrawAndGuessSlots.Slot]] = [[]]
        for slot in viewModel.slots.slots {
            if slot.isGap {
                groups.append([])
            } else {
                groups[groups.count - 1].append(slot)
            }
        }
        return groups.filter { !$0.isEmpty }.map { Word(id: $0[0].id, slots: $0) }
    }

    private var letterCount: Int {
        viewModel.slots.slots.count { !$0.isGap }
    }

    /// Wide enough to fill the row, but never smaller than 24 or bigger than 44.
    private var slotWidth: CGFloat {
        let wordCount = max(words.count, 1)
        let gaps = Self.slotGap * CGFloat(letterCount - wordCount) + PaeoniaSpacing.space16 * CGFloat(wordCount - 1)
        let width = (availableWidth - gaps) / CGFloat(max(letterCount, 1))
        return min(44, max(24, width.rounded(.down)))
    }

    // MARK: Slots

    private func slotView(_ slot: DrawAndGuessSlots.Slot) -> some View {
        let number = number(of: slot)
        let isLit = isRevealed && timeline.litLetters >= number
        let fill: Color = isLit && litsGreen ? .paeoniaSuccess : .paeoniaSurfacePrimary
        let textColor: Color = isLit && litsGreen ? .paeoniaTextInverse : .paeoniaTextPrimary
        return Button {
            guard slot.tile != nil else { return }
            PaeoniaHaptics.selection()
            viewModel.removeTile(atSlot: slot.id)
        } label: {
            ZStack {
                if let tile = slot.tile {
                    DrawAndGuessTileFace(letter: tile.letter, fill: fill, textColor: textColor)
                        .frame(width: slotWidth, height: Self.slotHeight)
                        .modifier(DrawAndGuessTileFlight(id: tile.id, namespace: namespace))
                } else if isLit, let letter = answerLetter(slot) {
                    DrawAndGuessTileFace(letter: letter, fill: fill, textColor: textColor)
                        .frame(width: slotWidth, height: Self.slotHeight)
                } else {
                    emptySlot
                }
            }
            .frame(width: slotWidth, height: Self.slotHeight)
            .overlay {
                RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous)
                    .strokeBorder(.paeoniaWarning, lineWidth: 2)
                    .opacity(viewModel.isShowingWrongGuess && slot.tile != nil ? 1 : 0)
                    .animation(PaeoniaMotion.buttonPress, value: viewModel.isShowingWrongGuess)
            }
            .scaleEffect(timeline.rippleIndex == number - 1 ? 1.18 : 1)
            .contentShape(Rectangle().inset(by: -2))
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!isRevealed)
        .accessibilityLabel(Text(slotLabel(slot, number: number)))
        .accessibilityHint(slot.tile == nil || isRevealed ? Text(verbatim: "") : Text(.gamesDrawAndGuessSlotRemoveHint))
        .accessibilityRotorEntry(id: slot.id, in: rotorNamespace)
    }

    private static let slotHeight: CGFloat = 48

    private var emptySlot: some View {
        RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous)
            .fill(.paeoniaSurfaceSecondary)
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(.paeoniaTextTertiary)
                    .frame(height: 2)
                    .padding(.horizontal, PaeoniaSpacing.space8)
                    .padding(.bottom, PaeoniaSpacing.space8)
            }
    }

    // MARK: Labels

    /// The position of the slot among the letters, starting at 1.
    private func number(of slot: DrawAndGuessSlots.Slot) -> Int {
        viewModel.slots.slots.prefix(slot.id + 1).count { !$0.isGap }
    }

    private func answerLetter(_ slot: DrawAndGuessSlots.Slot) -> Character? {
        let answer = Array(viewModel.slots.answer)
        return answer.indices.contains(slot.id) ? answer[slot.id] : nil
    }

    private func slotLabel(_ slot: DrawAndGuessSlots.Slot, number: Int) -> LocalizedStringResource {
        if let tile = slot.tile {
            return .gamesDrawAndGuessSlotFilled(number, String(tile.letter))
        }
        if isRevealed, let letter = answerLetter(slot) {
            return .gamesDrawAndGuessSlotFilled(number, String(letter))
        }
        return .gamesDrawAndGuessSlotEmpty(number)
    }

    /// "Answer, 2 words, 3 and 5 letters".
    private var answerDescription: LocalizedStringResource {
        let counts = words.map { $0.slots.count }
        if counts.count <= 1 {
            return .gamesDrawAndGuessGuessAnswerOneWord(letterCount)
        }
        let list = counts.map(String.init).formatted(.list(type: .and))
        return .gamesDrawAndGuessGuessAnswerWords(counts.count, list)
    }
}
