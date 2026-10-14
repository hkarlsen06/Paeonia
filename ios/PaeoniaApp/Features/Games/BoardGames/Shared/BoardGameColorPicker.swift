import SwiftUI

/// What the color circles show: the four Ludo colors, the one this person has
/// and the one their partner has.
nonisolated struct BoardGameColorChoice: Equatable, Sendable {
    struct Option: Equatable, Sendable, Identifiable {
        let color: LudoColor
        /// The color this person has now.
        let isSelected: Bool
        /// The partner has this color, so it can't be picked.
        let isTaken: Bool

        var id: LudoColor { color }
    }

    let options: [Option]
    let partnerName: String
    /// Shown on the circle the partner has.
    let partnerInitial: String

    init(colors: LudoColorPair, partnerName: String, partnerInitial: String) {
        options = LudoColor.allCases.map {
            Option(color: $0, isSelected: $0 == colors.mine, isTaken: $0 == colors.partner)
        }
        self.partnerName = partnerName
        self.partnerInitial = partnerInitial
    }
}

/// "Your color" and four round color circles, shown before the first move of a
/// Ludo game. The circle this person has carries a ring and a check mark. The
/// circle the partner has is faded, shows the partner's initial and can't be
/// tapped. Every circle has a 44 point tap target.
struct BoardGameColorPicker: View {
    let choice: BoardGameColorChoice
    let onPick: (LudoColor) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let swatchSize: CGFloat = 30
    private static let hitTarget = PaeoniaSpacing.compactButtonHeight

    var body: some View {
        // At large text sizes the title takes its own line.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: PaeoniaSpacing.space12) {
                title
                swatches
            }
            VStack(spacing: PaeoniaSpacing.space4) {
                title
                swatches
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.ludoColorTitle))
        .accessibilityIdentifier("ludo.color.picker")
    }

    private var title: some View {
        Text(.ludoColorTitle)
            .font(PaeoniaTypography.caption)
            .foregroundStyle(.paeoniaTextSecondary)
            .accessibilityHidden(true)
    }

    private var swatches: some View {
        HStack(spacing: 0) {
            ForEach(choice.options) { option in
                Button {
                    onPick(option.color)
                } label: {
                    swatch(option)
                        .frame(width: Self.hitTarget, height: Self.hitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(option.isTaken)
                .accessibilityLabel(Text(verbatim: spokenName(of: option)))
                .accessibilityHint(option.isTaken ? Text(verbatim: "") : Text(.ludoColorHintA11Y(choice.partnerName)))
                .accessibilityAddTraits(option.isSelected ? .isSelected : [])
                .accessibilityIdentifier("ludo.color.\(option.color.rawValue)")
            }
        }
    }

    private func swatch(_ option: BoardGameColorChoice.Option) -> some View {
        ZStack {
            Circle()
                .fill(option.color.color)
                .opacity(option.isTaken ? 0.35 : 1)
            if option.isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.paeoniaBackgroundSecondary)
                    .accessibilityHidden(true)
            } else if option.isTaken {
                Text(verbatim: choice.partnerInitial)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.paeoniaTextPrimary)
            }
        }
        .frame(width: Self.swatchSize, height: Self.swatchSize)
        .overlay {
            Circle()
                .stroke(.paeoniaTextPrimary, lineWidth: option.isSelected ? 2 : 0)
                .padding(-3)
        }
        .animation(reduceMotion ? nil : PaeoniaMotion.buttonPress, value: option.isSelected)
    }

    private func spokenName(of option: BoardGameColorChoice.Option) -> String {
        let name = String(localized: option.color.name)
        return option.isTaken ? String(localized: .ludoColorTakenA11Y(name, choice.partnerName)) : name
    }
}

#if DEBUG
#Preview("Picker") {
    VStack(spacing: PaeoniaSpacing.space24) {
        BoardGameColorPicker(
            choice: BoardGameColorChoice(colors: .standard, partnerName: "Robin", partnerInitial: "R"),
            onPick: { _ in }
        )
        BoardGameColorPicker(
            choice: BoardGameColorChoice(
                colors: LudoColorPair(mine: .gold, partner: .sky),
                partnerName: "Robin",
                partnerInitial: "R"
            ),
            onPick: { _ in }
        )
    }
    .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
    .frame(maxHeight: .infinity)
    .background(.paeoniaBackgroundSecondary)
    .preferredColorScheme(.dark)
}
#endif
