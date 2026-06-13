import SwiftUI

struct RootView: View {
    @State private var viewModel = RootViewModel()

    var body: some View {
        VStack(spacing: 8) {
            Text(.appTitle)
                .font(.largeTitle.bold())
            Text(.appTagline)
                .font(.body)
                .foregroundStyle(.secondary)
            Text(stateDescription)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .multilineTextAlignment(.center)
        .padding()
        .task {
            await viewModel.start()
        }
    }

    private var stateDescription: LocalizedStringResource {
        switch viewModel.state {
        case .launching:
            .appStateLaunching
        case .unauthenticated:
            .appStateUnauthenticated
        case .onboarding:
            .appStateOnboarding
        case .unpaired:
            .appStateUnpaired
        case .paired:
            .appStatePaired
        case .paywalled:
            .appStatePaywalled
        }
    }
}

#Preview {
  RootView()
}
