import SwiftUI

/// The guesses of a round as chips, in the order they were made. The right word,
/// when it has joined, is the last chip in green.
struct DrawAndGuessAttemptChips: View {
    let partnerName: String
    let wrongAttempts: [DrawAndGuessAttemptView]
    /// The right word, once it joins the row.
    let correctWord: String?
    /// How many letters of the right word have lit up.
    var litLetters = 0
    /// Each letter of the right word pops as it lights. False once the reveal skipped to the end.
    var popsLetters = false
    /// The petals burst from the right word.
    var bloomStart: Date?
    var bloomSeed = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            Text(.gamesDrawAndGuessResultTried(partnerName))
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextSecondary)
            DrawAndGuessFlowLayout(
                spacing: PaeoniaSpacing.space8,
                lineSpacing: PaeoniaSpacing.space8
            ) {
                ForEach(wrongAttempts) { attempt in
                    chip(attempt.text.uppercased(), isCorrect: false)
                        .transition(chipTransition)
                }
                if let correctWord {
                    correctChip(correctWord)
                        .overlay {
                            if let bloomStart {
                                GamePetalBloom(start: bloomStart, seed: bloomSeed, intensity: 0.5)
                                    .frame(width: 480, height: 320)
                            }
                        }
                        .transition(chipTransition)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spokenSentence))
        .accessibilityIdentifier("draw.attempts")
    }

    private var chipTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .offset(y: 8)).combined(with: .scale(scale: 0.92))
    }

    private func chip(_ text: String, isCorrect: Bool) -> some View {
        Text(text)
            .font(PaeoniaTypography.caption.weight(.semibold))
            .foregroundStyle(isCorrect ? .paeoniaTextInverse : .paeoniaTextPrimary)
            .padding(.horizontal, PaeoniaSpacing.space12)
            .padding(.vertical, PaeoniaSpacing.space8)
            .background(isCorrect ? .paeoniaSuccess : .paeoniaSurfacePrimary, in: Capsule(style: .continuous))
    }

    /// The right word. Its letters light up one after another, like the answer slots.
    private func correctChip(_ word: String) -> some View {
        HStack(spacing: 1) {
            ForEach(Array(DrawAndGuessAnswer.numberedCharacters(of: word).enumerated()), id: \.offset) { _, item in
                // A space has no letter number and is never dimmed.
                let isLit = litLetters == 0 || item.letter.map { $0 < litLetters } ?? true
                Text(String(item.character))
                    .opacity(isLit ? 1 : 0.35)
                    .modifier(DrawAndGuessLetterPop(isLit: isLit, peak: 1.3, isEnabled: popsLetters))
            }
        }
        .font(PaeoniaTypography.caption.weight(.bold))
        .foregroundStyle(.paeoniaTextInverse)
        .padding(.horizontal, PaeoniaSpacing.space12)
        .padding(.vertical, PaeoniaSpacing.space8)
        .background(.paeoniaSuccess, in: Capsule(style: .continuous))
    }

    /// "[Name] tried CAT, then HAT, then DOG".
    private var spokenSentence: String {
        let words = wrongAttempts.map { $0.text.uppercased() } + (correctWord.map { [$0.uppercased()] } ?? [])
        let list = words.joined(separator: String(localized: .gamesDrawAndGuessResultThen))
        return String(localized: .gamesDrawAndGuessDrawTried(partnerName, list))
    }
}
