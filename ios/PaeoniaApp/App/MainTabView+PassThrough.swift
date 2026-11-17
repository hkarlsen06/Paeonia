import SwiftUI
import UIKit

/// On iPad the tab bar sits at the top, and the selected tab's navigation bar shares its
/// row. A tab view that appears in a window already on screen, as it does after launch or
/// pairing, puts that tab's bar on its own row below instead, until the tab changes or the
/// window's width class does. So the tab view shows another tab, drawn empty so its screen
/// neither appears nor counts as seen, and returns to the selected tab once the empty one is
/// up. The tab view stays hidden meanwhile.
///
/// A pass made while the launch overlay covers the tabs leaves the bar where it is, so it
/// waits until the overlay has gone. Until the pass is over the tabs stay hidden and their
/// content holds its launch entrance, so the overlay fades to the plain background and Home
/// then fades and drops in with its bar already in place.
extension MainTabView {
    /// The tabs wait for the pass. Only an iPad makes one.
    var isWaitingForPassThrough: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && tabPassThrough != .done
    }

    var tabViewSelection: Binding<MainTab> {
        Binding(get: { tabPassThrough.passingTab ?? selection.wrappedValue }, set: selectTabFromTabBar)
    }

    @ViewBuilder
    func tabRoot(for tab: MainTab) -> some View {
        if tab == tabPassThrough.passingTab {
            Color.clear.onAppear { tabPassThrough = .done }
        } else {
            content(for: tab)
        }
    }

    /// Runs once, after the launch overlay has gone, and never again when a cover over the
    /// tabs closes.
    func passThroughTab() async {
        guard tabPassThrough == .pending, !launchOverlayShowing else { return }
        guard UIDevice.current.userInterfaceIdiom == .pad,
              let other = tabs.first(where: { $0 != selection.wrappedValue })
        else {
            tabPassThrough = .done
            return
        }
        tabPassThrough = .passing(other)
        // The empty tab ends the pass as it appears. This ends it if the tab never does,
        // so the tabs can't stay hidden.
        try? await Task.sleep(for: .seconds(1))
        tabPassThrough = .done
    }
}

enum TabPassThrough: Equatable {
    case pending
    case passing(MainTab)
    case done

    var passingTab: MainTab? {
        if case let .passing(tab) = self { tab } else { nil }
    }
}

extension View {
    /// Hides the tab view until its pass is over, then fades it in and cues its content's
    /// launch entrance (`launchEntrance(order:)`).
    func revealedAfterPassThrough(_ tabs: MainTabView) -> some View {
        let isWaiting = tabs.isWaitingForPassThrough
        return environment(\.launchContentRevealed, tabs.launchContentRevealed && !isWaiting)
            .animation(tabs.reduceMotion ? nil : .easeOut(duration: PaeoniaMotion.motionDefault)) {
                $0.opacity(isWaiting ? 0 : 1)
            }
            .task(id: tabs.launchOverlayShowing) { await tabs.passThroughTab() }
    }
}
