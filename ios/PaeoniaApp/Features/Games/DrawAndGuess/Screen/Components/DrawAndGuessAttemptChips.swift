import SwiftUI

/// The guesses of a round as chips, in the order they were made. The right word,
/// when it has joined, is the last chip in green.
struct DrawAndGuessAttemptChips: View {
    let partnerName: String
    let wrongAttempts: [DrawAndGuessAttemptView]
    /// The right word, once it joins the row.
    let correctWord: String?
    /// How many letters of the right word have lit up, and the one that is scaling up.
    var litLetters = 0
    var rippleIndex: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            Text(.gamesDrawAndGuessResultTried(partnerName))
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextSecondary)
            DrawAndGuessFlowLayout(
                spacing: PaeoniaSpacing.space8,
                lineSpacing: PaeoniaSpacing.space8,
                alignsLeading: true
            ) {
                ForEach(wrongAttempts) { attempt in
                    chip(attempt.text.uppercased(), isCorrect: false)
                        .transition(chipTransition)
                }
                if let correctWord {
                    correctChip(correctWord)
                        .transition(chipTransition)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            ForEach(Array(word.uppercased().enumerated()), id: \.offset) { index, letter in
                Text(String(letter))
                    .opacity(index < litLetters || litLetters == 0 ? 1 : 0.35)
                    .scaleEffect(rippleIndex == index ? 1.3 : 1)
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
