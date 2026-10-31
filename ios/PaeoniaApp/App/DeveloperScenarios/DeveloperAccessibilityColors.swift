#if DEBUG
import SwiftUI

nonisolated extension DeveloperScenario {
    static let accessibilityColors = DeveloperScenario(
        "accessibility-colors", "Accessibility color samples",
        "Rendered semantic foregrounds over their actual surfaces", .settings
    ) { _ in DeveloperAccessibilityColors() }

}

private struct DeveloperAccessibilityColors: View {
    private let pairs: [(Color, Color)] = [
        (.paeoniaTextSecondary, .paeoniaSurfacePressed),
        (.paeoniaTextTertiary, .paeoniaSurfacePressed),
        (.paeoniaError, .paeoniaSurfacePressed),
        (.paeoniaBorder, .paeoniaSurfacePrimary),
        (.paeoniaTextInverse, .paeoniaAccentPrimary),
        (.paeoniaTextInverse, .paeoniaAccentSecondary),
        (.paeoniaTextInverse, .paeoniaError),
        (.paeoniaTextInverse, .paeoniaErrorPressed),
        (.paeoniaPartnerTwoText, .paeoniaOutgoingMessage),
        (.paeoniaInkGold, .paeoniaBackgroundPrimary)
    ]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(pairs.indices, id: \.self) { index in
                HStack(spacing: 0) {
                    pairs[index].0
                    Color.clear
                }
                .frame(height: 60)
                .background(pairs[index].1)
                .accessibilityElement()
                .accessibilityLabel("Sample \(index + 1)")
            }
            Spacer(minLength: 0)
        }
        .background(.paeoniaBackgroundPrimary)
        .ignoresSafeArea(.container, edges: .bottom)
        .preferredColorScheme(.dark)
    }
}
#endif
