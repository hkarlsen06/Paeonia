import SwiftUI

/// "Download my data" on its own, for places outside Privacy and safety. The
/// paywall opens it, since someone without a subscription can reach nothing else.
/// The sheet covers the app's root banner, so it mounts the shared banner itself.
struct DataExportScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @State private var viewModel: DataExportViewModel

    @MainActor
    init(service: (any DataExportServicing)? = DataExportServiceFactory.makeDefault()) {
        _viewModel = State(initialValue: DataExportViewModel(service: service))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                PaeoniaCard(padding: 0) {
                    DataExportSection(viewModel: viewModel)
                }
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                .padding(.top, PaeoniaSpacing.screenTopSpacing)
                .padding(.bottom, PaeoniaSpacing.space24)
                .paeoniaReadableWidth(alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .paeoniaScreenBackground()
            .navigationTitle(Text(.privacySafetyDataExportTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(.commonDone)
                    }
                }
            }
        }
        .paeoniaTopBanner(bannerCenter)
        .presentationDetents([.large])
        .presentationBackground(.paeoniaBackgroundPrimary)
    }
}
