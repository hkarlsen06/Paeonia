import SwiftUI

struct PaeoniaWordmark: View {
    private static let baselineSize: CGFloat = 36

    private let title: LocalizedStringResource
    private let minimumScaleFactor: CGFloat
    private let sizeRatio: CGFloat

    @ScaledMetric(relativeTo: .largeTitle) private var scaledBaselineSize: CGFloat = 36

    private var scaledSize: CGFloat {
        scaledBaselineSize * sizeRatio
    }

    init(
        _ title: LocalizedStringResource = .appTitle,
        size: CGFloat = 36,
        minimumScaleFactor: CGFloat = 0.6
    ) {
        self.title = title
        self.minimumScaleFactor = minimumScaleFactor
        sizeRatio = size / Self.baselineSize
    }

    var body: some View {
        HStack(alignment: .center, spacing: scaledSize * 0.32) {
            Image(.paeoniaMark)
                .resizable()
                .scaledToFit()
                .frame(height: scaledSize * 0.9)
                .accessibilityHidden(true)

            Text(title)
                .font(PaeoniaTypography.wordmark(size: scaledSize))
                .foregroundStyle(.paeoniaTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(minimumScaleFactor)
                .layoutPriority(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
    }
}

struct PaeoniaBrandLockup: View {
    private let wordmarkSize: CGFloat
    private let taglineSize: CGFloat
    private let spacing: CGFloat
    private let taglineColor: Color
    private let horizontalAlignment: HorizontalAlignment

    @State private var taglineSizeValue: CGSize = .zero
    @State private var wordmarkSizeValue: CGSize = .zero

    private var wordmarkScale: CGFloat {
        guard taglineSizeValue.width > 0, wordmarkSizeValue.width > 0 else {
            return 1
        }

        return taglineSizeValue.width / wordmarkSizeValue.width
    }

    private var scaledWordmarkHeight: CGFloat? {
        guard wordmarkSizeValue.height > 0 else {
            return nil
        }

        return wordmarkSizeValue.height * wordmarkScale
    }

    private var taglineWidth: CGFloat? {
        taglineSizeValue.width > 0 ? taglineSizeValue.width : nil
    }

    init(
        wordmarkSize: CGFloat = 36,
        taglineSize: CGFloat = 17,
        spacing: CGFloat = PaeoniaSpacing.space12,
        taglineColor: Color = .paeoniaTextSecondary,
        horizontalAlignment: HorizontalAlignment = .center
    ) {
        self.wordmarkSize = wordmarkSize
        self.taglineSize = taglineSize
        self.spacing = spacing
        self.taglineColor = taglineColor
        self.horizontalAlignment = horizontalAlignment
    }

    var body: some View {
        VStack(alignment: horizontalAlignment, spacing: spacing) {
            PaeoniaWordmark(size: wordmarkSize)
                .fixedSize(horizontal: true, vertical: true)
                .readSize { wordmarkSizeValue = $0 }
                .scaleEffect(wordmarkScale, anchor: .center)
                .frame(width: taglineWidth, alignment: .center)
                .frame(height: scaledWordmarkHeight)

            Text(.appTagline)
                .font(PaeoniaTypography.wordmarkTagline(size: taglineSize))
                .foregroundStyle(taglineColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: true, vertical: false)
                .readSize { taglineSizeValue = $0 }
        }
        .multilineTextAlignment(.center)
    }
}

private struct PaeoniaSizePreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let nextSize = nextValue()
        value = CGSize(
            width: max(value.width, nextSize.width),
            height: max(value.height, nextSize.height)
        )
    }
}

private extension View {
    func readSize(_ onChange: @escaping (CGSize) -> Void) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: PaeoniaSizePreferenceKey.self, value: proxy.size)
            }
        }
        .onPreferenceChange(PaeoniaSizePreferenceKey.self) { size in
            guard size.width > 0, size.height > 0 else {
                return
            }

            onChange(size)
        }
    }
}

#if DEBUG
#Preview {
    PaeoniaBrandLockup()
        .padding()
        .background(.paeoniaBackgroundPrimary)
        .preferredColorScheme(.dark)
}
#endif
