import SwiftUI

/// The round's photo with where and when it was taken over its lower edge, as the
/// reveal and "Our guesses" show it once the spot is known.
struct GuessMySpotPhotoCaption: View {
    let image: UIImage?
    let placeName: String?
    let takenOn: String?
    var height: CGFloat = 180

    var body: some View {
        // The photo fills a box of fixed height, so the caption sits on the box's edge
        // and not on the edge of the larger filled image.
        Color.paeoniaSurfacePrimary
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        // The clip cuts only the drawing. The filled image would still
                        // take touches past the box and keep them from the map.
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if placeName != nil || takenOn != nil {
                    caption
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous))
            .accessibilityIdentifier("guessMySpot.photoCaption")
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let placeName {
                Text(verbatim: placeName)
                    .font(PaeoniaTypography.bodyEmphasis)
                    .lineLimit(2)
            }
            if let date = GuessMySpotText.takenOn(takenOn) {
                Text(verbatim: date)
                    .font(PaeoniaTypography.caption)
                    .opacity(0.85)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, PaeoniaSpacing.space12)
        .padding(.top, PaeoniaSpacing.space24)
        .padding(.bottom, PaeoniaSpacing.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom))
        .accessibilityElement(children: .combine)
    }
}
