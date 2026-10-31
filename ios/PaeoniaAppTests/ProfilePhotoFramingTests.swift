import CoreGraphics
import Foundation
import Testing
@testable import PaeoniaApp

struct ProfilePhotoFramingTests {
    @Test(arguments: [CGSize(width: 1_200, height: 800), CGSize(width: 800, height: 1_200)])
    func reopeningPreservesTheExistingCrop(size: CGSize) {
        let crop = CGRect(x: 120, y: 160, width: 400, height: 400)
        let framing = ProfilePhotoFraming(imageSize: size, crop: crop)
        #expect(abs(framing.crop.minX - crop.minX) < 0.001)
        #expect(abs(framing.crop.minY - crop.minY) < 0.001)
        #expect(framing.crop.size == crop.size)
    }

    @Test(arguments: [CGSize(width: 1_200, height: 800), CGSize(width: 800, height: 1_200)])
    func everyPositionRemainsSquareAndWithinThePhoto(size: CGSize) {
        for zoom in [1.0, 2, 15] {
            for position in [0.0, 0.5, 1] {
                var framing = ProfilePhotoFraming(imageSize: size, crop: .zero)
                framing.zoom = zoom
                framing.horizontalPosition = position
                framing.verticalPosition = position
                let crop = framing.crop
                #expect(crop.width == crop.height)
                #expect(crop.width > 0)
                #expect(CGRect(origin: .zero, size: size).contains(crop))
            }
        }
    }

    @Test func repositioningCanReachBothOppositeCornersOfTheSamePhoto() {
        var framing = ProfilePhotoFraming(imageSize: CGSize(width: 800, height: 800), crop: .zero)
        framing.zoom = 2
        framing.horizontalPosition = 0
        framing.verticalPosition = 0
        #expect(framing.crop == CGRect(x: 0, y: 0, width: 400, height: 400))
        framing.horizontalPosition = 1
        framing.verticalPosition = 1
        #expect(framing.crop == CGRect(x: 400, y: 400, width: 400, height: 400))
        framing.reset()
        #expect(framing.crop == CGRect(x: 0, y: 0, width: 800, height: 800))
    }

    @Test func resetRestoresALargestCenteredSquare() {
        var framing = ProfilePhotoFraming(
            imageSize: CGSize(width: 1_200, height: 800),
            crop: CGRect(x: 600, y: 200, width: 200, height: 200)
        )
        framing.reset()
        #expect(framing.crop == CGRect(x: 200, y: 0, width: 800, height: 800))
    }
}
