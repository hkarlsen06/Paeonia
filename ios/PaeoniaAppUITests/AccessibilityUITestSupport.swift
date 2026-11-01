import XCTest

extension XCUIApplication {
    /// Feature journeys explicitly opt into the optional tools. Settings journeys test the default presentation.
    @MainActor
    func launchWithExtraAccessibilityTools() {
        launchArguments += [
            "-accessibility.alwaysShowControls", "YES",
            "-accessibility.alwaysShowMediaAlternatives", "YES",
        ]
        launch()
    }
}
