import Testing
@testable import PaeoniaApp

struct GuessMySpotCoordinateInputTests {
    @Test func signedCoordinatesAndDecimalCommaKeepTheirMeaning() throws {
        let coordinate = try #require(GuessMySpotCoordinateInput.parse(latitude: " -33,86 ", longitude: "151.21"))
        #expect(coordinate.latitude == -33.86)
        #expect(coordinate.longitude == 151.21)
        #expect(GuessMySpotCoordinateInput.parse(latitude: "0", longitude: "0") != nil)
    }

    @Test func invalidInputNeverBecomesASelection() {
        for latitude in ["", "north", "nan", "inf", "90.001", "-90.001", "1,2,3"] {
            #expect(GuessMySpotCoordinateInput.parse(latitude: latitude, longitude: "0") == nil)
        }
        for longitude in ["", "west", "nan", "inf", "180.001", "-180.001"] {
            #expect(GuessMySpotCoordinateInput.parse(latitude: "0", longitude: longitude) == nil)
        }
        #expect(GuessMySpotCoordinateInput.parse(latitude: "-90", longitude: "180") != nil)
    }
}
