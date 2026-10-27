import SwiftUI

/// The two big cards of a pick-one-of-two question. A tap picks one, dims the other
/// and plays a light haptic. The Send action lives in the flow's bottom bar, like the
/// other composers.
struct DailyOptionChoicePicker: View {
    let options: DailyAnswerOptions
    let selection: DailyAnswerOption?
    let onSelect: (DailyAnswerOption) -> Void

    @Environment(\.dailyAnswerComposerColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            ForEach(Array(DailyAnswerOption.allCases.enumerated()), id: \.element) { index, option in
                card(option, position: index + 1)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func card(_ option: DailyAnswerOption, position: Int) -> some View {
        let isSelected = selection == option
        let isDimmed = selection != nil && !isSelected
        let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.radius20, style: .continuous)
        return Button {
            PaeoniaHaptics.selection()
            onSelect(option)
        } label: {
            Text(verbatim: options.label(for: option))
                .font(PaeoniaTypography.sectionTitle)
                .foregroundStyle(colors.foreground)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(PaeoniaSpacing.space16)
                .frame(maxWidth: .infinity, minHeight: 88)
                .background(isSelected ? colors.selected : colors.control, in: shape)
                .overlay {
                    shape.strokeBorder(
                        isSelected ? colors.accent : colors.control,
                        lineWidth: isSelected ? PaeoniaRadius.strokeEmphasis : PaeoniaRadius.strokeHairline
                    )
                }
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(PaeoniaTypography.sectionTitle)
                            .foregroundStyle(colors.accent)
                            .padding(PaeoniaSpacing.space8)
                            .transition(.scale.combined(with: .opacity))
                            .accessibilityHidden(true)
                    }
                }
                .opacity(isDimmed ? 0.55 : 1)
                .scaleEffect(isSelected && !reduceMotion ? 1.02 : 1)
                .contentShape(shape)
        }
        .buttonStyle(.paeoniaPressableCard)
        .animation(reduceMotion ? nil : .spring(duration: PaeoniaMotion.motionDefault, bounce: 0.3), value: selection)
        .accessibilityValue(Text(.dailyChallengePickOptionPosition(position, DailyAnswerOption.allCases.count)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
