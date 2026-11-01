import CoreGraphics
import XCTest

/// Fixed game actions can sit below a scrolling form. Exclude actual visible system
/// bars, rather than a guessed inset that repeatedly scrolls an already reachable action.
@MainActor
func gameJourneyViewport(in app: XCUIApplication) -> CGRect {
    let window = app.windows.firstMatch.frame
    var top = window.minY
    var bottom = window.maxY
    for bar in app.navigationBars.allElementsBoundByIndex where bar.isHittable {
        top = max(top, bar.frame.maxY)
    }
    for bar in app.tabBars.allElementsBoundByIndex where bar.isHittable {
        bottom = min(bottom, bar.frame.minY)
    }
    if app.keyboards.firstMatch.exists {
        bottom = min(bottom, app.keyboards.firstMatch.frame.minY)
    }
    return CGRect(x: window.minX, y: top, width: window.width, height: max(0, bottom - top))
}
