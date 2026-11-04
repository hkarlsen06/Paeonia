#if DEBUG
    import SwiftUI

    struct DeveloperPiccanteHubScenarioView: View {
        @State private var hub: PiccanteHubModel

        init() {
            var dependencies = DeveloperGamesScenarioFactory.dependencies(for: .piccanteResult)
            DeveloperPiccanteFixture.configure(&dependencies, for: .piccanteResult)
            let hub = PiccanteHubModel(dependencies: dependencies)
            hub.configure(participants: DeveloperGamesFixture.participants)
            _hub = State(initialValue: hub)
        }

        var body: some View {
            NavigationStack {
                ScrollView {
                    hub.card(
                        GameHubCardContext(partnerName: "Robin", partnerIsHere: false, isOnHub: true, hide: nil),
                        open: { _ in })
                        .padding(PaeoniaSpacing.screenHorizontalPadding)
                }
                .paeoniaScreenBackground()
                .navigationTitle(Text(.piccanteTitle))
            }
            .task { await hub.reload() }
        }
    }
#endif
