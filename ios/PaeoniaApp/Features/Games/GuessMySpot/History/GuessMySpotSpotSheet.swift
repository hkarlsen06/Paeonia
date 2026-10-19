import SwiftUI

/// The rounds that share one spot, which zooming in would never split. A row opens
/// its round.
struct GuessMySpotSpotSheet: View {
    let rounds: [RemoteGuessMySpotRound]
    let history: GuessMySpotHistoryViewModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(rounds) { round in
                NavigationLink {
                    GuessMySpotRoundDetail(round: round, history: history, showsClose: false)
                } label: {
                    row(round)
                }
                .listRowBackground(Color.paeoniaSurfaceSecondary)
            }
            .scrollContentBackground(.hidden)
            .paeoniaScreenBackground(.paeoniaBackgroundSecondary)
            .navigationTitle(Text(verbatim: rounds.first?.placeName ?? String(localized: .guessMySpotHistorySomewhere)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) {
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("guessMySpot.history.spot")
    }

    private func row(_ round: RemoteGuessMySpotRound) -> some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            GuessMySpotThumbnail(round: round, history: history)
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
                Text(round.senderUserID == history.currentUserID
                    ? .guessMySpotHistoryDetailSentByYou
                    : .guessMySpotHistoryDetailSentBy(history.partnerName))
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)
                if let date = GuessMySpotText.takenOn(round.takenOn) {
                    Text(verbatim: date)
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A round's photo as a small rounded square, loaded through the shared media cache.
struct GuessMySpotThumbnail: View {
    let round: RemoteGuessMySpotRound
    let history: GuessMySpotHistoryViewModel
    var size: CGFloat = 48

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.paeoniaSurfacePrimary
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous))
        .accessibilityHidden(true)
        .task(id: round.id) { image = await history.photo(of: round) }
    }
}
