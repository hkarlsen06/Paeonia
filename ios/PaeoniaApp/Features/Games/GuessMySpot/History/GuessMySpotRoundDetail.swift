import SwiftUI

/// One round: the photo, where and when it was taken, both pins with the line
/// between them, who sent it, and how close the guess came. The sender can delete
/// it for both partners once both have seen its reveal. Present it inside a
/// `NavigationStack`.
struct GuessMySpotRoundDetail: View {
    let round: RemoteGuessMySpotRound
    let history: GuessMySpotHistoryViewModel
    /// Off where the detail is pushed, so back is the way out.
    var showsClose = true

    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDelete = false
    @State private var image: UIImage?
    @State private var photoFailed = false
    @State private var camera = GuessMySpotCamera.world

    private var sentByMe: Bool {
        round.senderUserID == history.currentUserID
    }

    var body: some View {
        ScrollView {
            VStack(spacing: PaeoniaSpacing.space16) {
                GuessMySpotPhotoPane(image: image, failed: photoFailed, retry: loadPhoto)
                    .frame(height: 300)
                    .background(.paeoniaSurfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous))
                heading
                map
                caption
                if round.canDelete == true, sentByMe {
                    deleteButton
                }
            }
            .padding(PaeoniaSpacing.screenHorizontalPadding)
            .paeoniaReadableWidth(PaeoniaSpacing.focusedContentWidth)
        }
        .paeoniaScreenBackground(.paeoniaBackgroundSecondary)
        .toolbar {
            if showsClose {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) {
                        dismiss()
                    }
                    .accessibilityIdentifier("guessMySpot.history.detail.close")
                }
            }
        }
        .confirmationDialog(
            Text(.guessMySpotHistoryDeleteConfirmTitle),
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                Task {
                    if await history.delete(round) {
                        PaeoniaHaptics.selection()
                        dismiss()
                    }
                }
            } label: {
                Text(.guessMySpotHistoryDeleteConfirmAction)
            }
        } message: {
            Text(.guessMySpotHistoryDeleteConfirmMessage(history.partnerName))
        }
        .preferredColorScheme(.dark)
        .task { loadPhoto() }
        .accessibilityIdentifier("guessMySpot.history.detail")
    }

    private var heading: some View {
        VStack(spacing: PaeoniaSpacing.space4) {
            Text(verbatim: round.placeName ?? String(localized: .guessMySpotHistorySomewhere))
                .font(PaeoniaTypography.title)
                .foregroundStyle(.paeoniaTextPrimary)
                .accessibilityAddTraits(.isHeader)
            if let date = GuessMySpotText.takenOn(round.takenOn) {
                Text(verbatim: date)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
        }
        .multilineTextAlignment(.center)
    }

    @ViewBuilder
    private var map: some View {
        if let guess = round.guess, let spot = round.spot {
            GuessMySpotMap(
                position: $camera,
                pins: [
                    GuessMySpotMap.Pin(id: "guess", coordinate: guess, style: history.style(of: round.guesserUserID)),
                    GuessMySpotMap.Pin(id: "spot", coordinate: spot, style: history.style(of: round.senderUserID)),
                ],
                line: GuessMySpotMap.Line(
                    from: guess,
                    to: spot,
                    isFar: GuessMySpotRules.verdict(distanceMeters: round.knownDistance ?? 0) == .far
                ),
                showsSatelliteButton: false,
                accessibilityValue: .guessMySpotMapPinDropped
            )
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous))
            .onAppear { camera = GuessMySpotCamera.framing(guess, spot) }
        }
    }

    private var caption: some View {
        VStack(spacing: PaeoniaSpacing.space4) {
            Text(sentByMe ? .guessMySpotHistoryDetailSentByYou : .guessMySpotHistoryDetailSentBy(history.partnerName))
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaTextPrimary)
            if let distance = round.knownDistance {
                let off = GuessMySpotText.distance(distance)
                let guessed: LocalizedStringResource = sentByMe
                    ? .guessMySpotHistoryDetailGuess(history.partnerName, off)
                    : .guessMySpotHistoryDetailGuessYou(off)
                let points: LocalizedStringResource = .guessMySpotStatsPoints(round.knownPoints ?? 0)
                Text(verbatim: GuessMySpotHistoryScreen.joined(guessed, points))
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            isConfirmingDelete = true
        } label: {
            Label {
                Text(.guessMySpotHistoryDelete)
            } icon: {
                Image(systemName: "trash")
            }
        }
        .buttonStyle(PaeoniaQuietButtonStyle())
        .padding(.top, PaeoniaSpacing.space8)
        .accessibilityIdentifier("guessMySpot.history.detail.delete")
    }

    private func loadPhoto() {
        photoFailed = false
        Task {
            let loaded = await history.photo(of: round)
            image = loaded
            photoFailed = loaded == nil
        }
    }
}
