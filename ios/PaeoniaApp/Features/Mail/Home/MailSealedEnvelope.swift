import SwiftUI

/// A letter that waits to be opened. It is the daily card's envelope with the pink wax seal on
/// the tip of its flap, at the spot measured for `DailyPromptHeroArtwork`.
struct MailSealedEnvelope: View {
    let width: CGFloat

    var body: some View {
        let height = width / PaeoniaEnvelopeLayer.aspect
        Image(.homeEnvelopeSealed)
            .resizable()
            .accessibilityHidden(true)
            .frame(width: width, height: height)
            .overlay(alignment: .topLeading) {
                Image(.homeWaxSealPink)
                    .resizable()
                    .accessibilityHidden(true)
                    .scaledToFit()
                    .frame(width: width * 0.27)
                    .position(x: width * 0.495, y: height * 0.614)
            }
    }
}
