import SwiftUI

struct PairingCelebrationHeartCore: View {
    var body: some View {
        ZStack {
            heart
                .foregroundStyle(.paeoniaAccentSecondary.opacity(0.24))
                .blur(radius: 16)
                .scaleEffect(1.12)
            heart
                .foregroundStyle(LinearGradient(
                    stops: [
                        .init(color: .paeoniaTextPrimary, location: 0),
                        .init(color: .paeoniaAccentSecondary, location: 0.3),
                        .init(color: .paeoniaPartnerTwo, location: 0.65),
                        .init(color: .paeoniaAccentPrimary, location: 1)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    Ellipse()
                        .fill(.paeoniaTextPrimary.opacity(0.4))
                        .frame(width: 23, height: 13)
                        .rotationEffect(.degrees(-35))
                        .blur(radius: 7)
                        .offset(x: -16, y: -13)
                        .mask(heart)
                }
                .shadow(color: .paeoniaAccentPrimary.opacity(0.22), radius: 8, y: 5)
        }
        .frame(width: 168, height: 168)
        .accessibilityHidden(true)
    }

    private var heart: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: PairingCelebrationTiming.heartSize, weight: .regular))
            .accessibilityHidden(true)
    }
}
