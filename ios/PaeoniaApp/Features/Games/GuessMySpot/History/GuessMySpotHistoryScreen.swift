import MapKit
import SwiftUI

/// "Our guesses": one map with a pin for every guessed round, at the real spot, in the
/// sender's color. Pins that would overlap at the zoom show as one pin with a count.
/// A pin opens its round. A cluster zooms in, or lists its rounds when they all
/// share one spot. The records float over the top.
struct GuessMySpotHistoryScreen: View {
    @Bindable var viewModel: GuessMySpotHistoryViewModel

    @State private var camera = GuessMySpotCamera.world
    @State private var span: MKCoordinateSpan?
    @State private var selected: RemoteGuessMySpotRound?
    @State private var oneSpot: GuessMySpotCluster?
    @State private var hasFramed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .paeoniaScreenBackground(.paeoniaBackgroundSecondary)
            .navigationTitle(Text(.guessMySpotHistoryTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.paeoniaBackgroundSecondary, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .preferredColorScheme(.dark)
            .task { await viewModel.load() }
            .task { await viewModel.follow() }
            .sheet(item: $selected) { round in
                NavigationStack {
                    GuessMySpotRoundDetail(round: round, history: viewModel)
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $oneSpot) { cluster in
                GuessMySpotSpotSheet(
                    rounds: cluster.roundIDs.compactMap { id in viewModel.rounds.first { $0.id == id } },
                    history: viewModel
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .accessibilityIdentifier("guessMySpot.history")
    }

    @ViewBuilder
    private var content: some View {
        if !viewModel.rounds.isEmpty {
            map
        } else if viewModel.isLoading {
            ProgressView()
                .tint(.paeoniaAccentPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let failure = viewModel.loadFailure {
            PaeoniaLoadFailureView(
                failure: failure,
                offlineMessage: .guessMySpotHistoryOfflineMessage,
                failedMessage: .guessMySpotHistoryFailedMessage
            ) {
                Button {
                    Task { await viewModel.load() }
                } label: {
                    Text(.commonTryAgain)
                }
                .buttonStyle(PaeoniaSecondaryButtonStyle())
            }
            .padding(PaeoniaSpacing.screenHorizontalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            PaeoniaEmptyStateView(
                title: .guessMySpotHistoryEmptyTitle,
                message: .guessMySpotHistoryEmptyMessage,
                systemImage: "map"
            )
            .padding(PaeoniaSpacing.screenHorizontalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Map

    private var clusters: [GuessMySpotCluster] {
        let items = viewModel.rounds.compactMap { round in round.spot.map { (id: round.id, spot: $0) } }
        // Before the camera reports its span, every round stands alone.
        return GuessMySpotClustering.clusters(
            items,
            latitudeDelta: span?.latitudeDelta ?? 0,
            longitudeDelta: span?.longitudeDelta ?? 0
        )
    }

    private var map: some View {
        let clusters = clusters
        return GuessMySpotMap(
            position: $camera,
            pins: clusters.compactMap(pin),
            onPinTap: { id in open(clusters.first { $0.id.uuidString == id }) },
            onCameraChange: { span = $0.span }
        )
        .safeAreaPadding(.top, 130)
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .top) {
            if let records = viewModel.records {
                GuessMySpotRecordsCard(
                    records: records,
                    score: viewModel.score,
                    places: viewModel.rounds.count,
                    me: viewModel.me,
                    partner: viewModel.partner
                )
            }
        }
        .onChange(of: viewModel.rounds.map(\.id), initial: true) { _, _ in
            guard !hasFramed else { return }
            hasFramed = true
            camera = GuessMySpotCamera.framing(viewModel.rounds.compactMap(\.spot))
        }
    }

    /// One round opens. Rounds at one spot list. Anything else zooms in until it splits.
    private func open(_ cluster: GuessMySpotCluster?) {
        guard let cluster else { return }
        if cluster.count == 1 {
            selected = viewModel.rounds.first { $0.id == cluster.id }
        } else if cluster.isOneSpot {
            oneSpot = cluster
        } else {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.6)) {
                // Its spots are over 300 m apart, so a 500 m minimum always splits it.
                camera = GuessMySpotCamera.framing(cluster.spots, minimumMeters: 500)
            }
        }
    }

    private func pin(for cluster: GuessMySpotCluster) -> GuessMySpotMap.Pin? {
        guard let newest = viewModel.rounds.first(where: { $0.id == cluster.id }) else { return nil }
        let label: String
        if cluster.count > 1 {
            label = String(localized: .guessMySpotHistoryPlaces(cluster.count))
        } else {
            let place = newest.placeName ?? String(localized: .guessMySpotHistorySomewhere)
            label = [place, GuessMySpotText.takenOn(newest.takenOn)].compactMap(\.self).joined(separator: ", ")
        }
        return GuessMySpotMap.Pin(
            id: cluster.id.uuidString,
            coordinate: cluster.coordinate,
            style: viewModel.style(of: newest.senderUserID),
            count: cluster.count,
            label: label
        )
    }
}
