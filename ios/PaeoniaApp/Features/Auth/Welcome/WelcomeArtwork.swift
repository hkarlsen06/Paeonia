import SwiftUI

/// The pre-auth welcome hero: the Paeonia brand mark, large. Reusing the logo keeps the
/// greeting unmistakably on-brand and calm — no bespoke illustration.
struct WelcomeBrandArt: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    var body: some View {
        Image(.paeoniaMark)
            .resizable()
            .scaledToFit()
            .frame(width: 160)
            .scaleEffect(breathe ? 1.03 : 1.0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                    breathe = true
                }
            }
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview {
    ZStack {
        Color.paeoniaBackgroundPrimary
        WelcomeBrandArt()
    }
    .ignoresSafeArea()
    .preferredColorScheme(.dark)
}
#endif
