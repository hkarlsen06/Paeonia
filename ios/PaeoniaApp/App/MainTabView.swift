import SwiftUI

/// The native tab bar shown once a couple is paired.
///
/// Tab selection is owned by `RootViewModel` and passed in as a binding. That lets
/// navigation intent — opening the widget drawing screen from the Home Screen
/// widget — select the Home tab and present its destination in one atomic update,
/// so the screen can never open hidden behind another tab.
struct MainTabView: View {
    let currentDisplayName: String?
    let currentProfilePhotoAssetID: UUID?
    let partnerDisplayName: String?
    let partnerProfilePhotoAssetID: UUID?
    let authorName: String?
    let selection: Binding<MainTab>
    let widgetDrawingPresented: Binding<Bool>
    let onOpenWidgetDrawing: () -> Void

    var body: some View {
        TabView(selection: selection) {
            ForEach(MainTab.allCases) { tab in
                content(for: tab)
                    .tag(tab)
                    .tabItem {
                        Label {
                            Text(tab.title)
                        } icon: {
                            Image(systemName: tab.systemImage)
                        }
                    }
            }
        }
        .tint(.paeoniaAccentPrimary)
    }

    @ViewBuilder
    private func content(for tab: MainTab) -> some View {
        switch tab {
        case .home:
            homeTab
        case .you:
            youTab
        }
    }

    private var homeTab: some View {
        NavigationStack {
            PairedHomeView(
                currentDisplayName: currentDisplayName,
                currentProfilePhotoAssetID: currentProfilePhotoAssetID,
                partnerDisplayName: partnerDisplayName,
                partnerProfilePhotoAssetID: partnerProfilePhotoAssetID,
                onOpenWidgetDrawing: onOpenWidgetDrawing
            )
            .navigationBarTitleDisplayMode(.inline)
            // The brand mark and couple avatars are populated into the navigation
            // bar from inside PairedHomeView, where the name/photo data lives.
            .navigationDestination(isPresented: widgetDrawingPresented) {
                WidgetDrawingView(authorName: authorName)
            }
        }
    }

    private var youTab: some View {
        NavigationStack {
            SettingsView()
        }
    }

}

#if DEBUG
#Preview {
    MainTabView(
        currentDisplayName: "Hjalmar",
        currentProfilePhotoAssetID: nil,
        partnerDisplayName: "Oda",
        partnerProfilePhotoAssetID: nil,
        authorName: "Hjalmar",
        selection: .constant(.home),
        widgetDrawingPresented: .constant(false),
        onOpenWidgetDrawing: {}
    )
    .preferredColorScheme(.dark)
}
#endif
