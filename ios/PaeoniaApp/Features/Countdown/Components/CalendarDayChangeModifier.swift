import Combine
import SwiftUI
import UIKit

extension View {
    /// Runs `action` when the calendar day may have changed under a view that is
    /// still on screen: midnight, a time zone change, a clock change, or the app
    /// coming back to the foreground. Views that show "days until" call this to
    /// refresh the `Date` they compute from, because nothing else re-renders them
    /// overnight.
    func onCalendarDayChange(perform action: @escaping () -> Void) -> some View {
        modifier(CalendarDayChangeModifier(action: action))
    }
}

private struct CalendarDayChangeModifier: ViewModifier {
    let action: () -> Void

    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onReceive(dayChanges) { _ in action() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { action() }
            }
    }

    /// The system doesn't promise which thread posts these, so hop to main before
    /// touching view state.
    private var dayChanges: AnyPublisher<Notification, Never> {
        let center = NotificationCenter.default
        return Publishers.Merge3(
            center.publisher(for: .NSCalendarDayChanged),
            center.publisher(for: .NSSystemTimeZoneDidChange),
            center.publisher(for: UIApplication.significantTimeChangeNotification)
        )
        .receive(on: DispatchQueue.main)
        .eraseToAnyPublisher()
    }
}
