import CoreGraphics
import Testing
@testable import PaeoniaApp

/// Where the dots, lines and boxes sit, and which line a touch picks. A 400 point
/// board has an inset of 25 and boxes 87.5 points wide.
struct DotsAndBoxesBoardGeometryTests {
    private let geometry = DotsAndBoxesBoardGeometry(side: 400)
    private let boxCount = DotsAndBoxesBoard.boxTotal

    /// A point inside a box, as a fraction of the box width from its center.
    private func point(inBox box: Int, dx: CGFloat, dy: CGFloat) -> CGPoint {
        let rect = geometry.boxRect(box)
        return CGPoint(x: rect.midX + dx * geometry.cell, y: rect.midY + dy * geometry.cell)
    }

    private func isClose(_ first: CGFloat, _ second: CGFloat) -> Bool {
        abs(first - second) < 0.001
    }

    // MARK: Layout

    @Test func theGridFillsTheBoardInsideAnInset() {
        let grid = geometry.gridRect

        #expect(isClose(geometry.inset, 25))
        #expect(isClose(geometry.cell, 87.5))
        #expect(isClose(grid.minX, 25))
        #expect(isClose(grid.maxX, 375))
        #expect(isClose(grid.width, grid.height))
    }

    @Test func theLayoutScalesWithTheSide() {
        let wide = DotsAndBoxesBoardGeometry(side: DotsAndBoxesBoardGeometry.maxSide)

        #expect(isClose(wide.inset * 2 + wide.cell * 4, 560))
        #expect(wide.lineThickness > geometry.lineThickness)
        #expect(isClose(wide.lineThickness / wide.cell, geometry.lineThickness / geometry.cell))
    }

    @Test func aPhoneSizedBoardDrawsLinesAboutFivePointsThick() {
        let phone = DotsAndBoxesBoardGeometry(side: 350)

        #expect(phone.lineThickness > 4.5)
        #expect(phone.lineThickness < 6)
        #expect(phone.dotDiameter > phone.lineThickness)
        #expect(phone.activeDotDiameter > phone.dotDiameter)
    }

    @Test func dotsSitOnTheGridCorners() {
        #expect(geometry.dotPosition(index: 0) == CGPoint(x: 25, y: 25))
        #expect(geometry.dotPosition(index: 4) == CGPoint(x: 375, y: 25))
        #expect(geometry.dotPosition(index: 20) == CGPoint(x: 25, y: 375))
        #expect(geometry.dotPosition(index: 24) == CGPoint(x: 375, y: 375))
        #expect(DotsAndBoxesBoardGeometry.dotTotal == 25)
    }

    // MARK: Lines

    @Test func everyLineJoinsTwoNeighboringDots() throws {
        for line in 0..<DotsAndBoxesBoard.moveLimit {
            let segment = try #require(geometry.segment(of: line))
            let dots = DotsAndBoxesBoardGeometry.dotIndices(of: line)

            #expect(dots.count == 2)
            #expect(geometry.dotPosition(index: dots[0]) == segment.start)
            #expect(geometry.dotPosition(index: dots[1]) == segment.end)
            #expect(isClose(segment.length, geometry.cell))
            #expect(segment.isHorizontal == (line < DotsAndBoxesBoard.horizontalLineCount))
        }
    }

    @Test func aLineIsNotDrawnForAnIndexThatIsNotALine() {
        #expect(geometry.segment(of: -1) == nil)
        #expect(geometry.segment(of: DotsAndBoxesBoard.moveLimit) == nil)
        #expect(DotsAndBoxesBoardGeometry.dotIndices(of: 40).isEmpty)
    }

    @Test func aLineViewHasRoomForTheThickerStrokeWhileItGrows() throws {
        let segment = try #require(geometry.segment(of: 5))
        let frame = geometry.frame(of: segment)

        #expect(frame.contains(segment.start))
        #expect(frame.contains(segment.end))
        #expect(frame.height >= geometry.lineThickness * 2)
        #expect(isClose(frame.midX, segment.midpoint.x))
        #expect(isClose(frame.midY, segment.midpoint.y))
    }

    // MARK: Boxes and photo pieces

    @Test func eachBoxSitsBetweenItsFourLines() throws {
        for box in 0..<boxCount {
            let rect = geometry.boxRect(box)
            let lines = DotsAndBoxesBoard.lines(of: box)
            let top = try #require(geometry.segment(of: lines[0]))
            let bottom = try #require(geometry.segment(of: lines[1]))
            let left = try #require(geometry.segment(of: lines[2]))
            let right = try #require(geometry.segment(of: lines[3]))

            #expect(isClose(top.midpoint.y, rect.minY))
            #expect(isClose(bottom.midpoint.y, rect.maxY))
            #expect(isClose(left.midpoint.x, rect.minX))
            #expect(isClose(right.midpoint.x, rect.maxX))
        }
    }

    @Test func thePhotoPiecesTileThePhotoExactly() {
        let photo = CGRect(x: 0, y: 0, width: geometry.photoSide, height: geometry.photoSide)
        let pieces = (0..<boxCount).map { geometry.photoPieceRect(forBox: $0) }

        #expect(isClose(pieces.reduce(0) { $0 + $1.width * $1.height }, photo.width * photo.height))
        #expect(pieces.allSatisfy { photo.contains($0) })
        for first in pieces.indices {
            for second in pieces.indices where second > first {
                let overlap = pieces[first].intersection(pieces[second])
                #expect(overlap.isNull || overlap.width * overlap.height == 0)
            }
        }
    }

    @Test func aBoxShowsTheSamePartOfThePhotoWhereverItSitsOnTheBoard() {
        // The piece starts as far into the photo as the box starts into the grid.
        for box in 0..<boxCount {
            let piece = geometry.photoPieceRect(forBox: box)
            let rect = geometry.boxRect(box)

            #expect(isClose(piece.minX, rect.minX - geometry.gridRect.minX))
            #expect(isClose(piece.minY, rect.minY - geometry.gridRect.minY))
        }
    }

    // MARK: Picking

    @Test func theMiddleOfEachBoxEdgePicksThatEdgesLine() {
        for box in 0..<boxCount {
            let lines = DotsAndBoxesBoard.lines(of: box)

            #expect(geometry.line(at: point(inBox: box, dx: 0, dy: -0.3)) == lines[0])
            #expect(geometry.line(at: point(inBox: box, dx: 0, dy: 0.3)) == lines[1])
            #expect(geometry.line(at: point(inBox: box, dx: -0.3, dy: 0)) == lines[2])
            #expect(geometry.line(at: point(inBox: box, dx: 0.3, dy: 0)) == lines[3])
        }
    }

    @Test func eachBoxSplitsIntoFourTrianglesAlongItsDiagonals() {
        for box in 0..<boxCount {
            let lines = DotsAndBoxesBoard.lines(of: box)

            // Closer to a side than to the top or bottom picks the side.
            #expect(geometry.line(at: point(inBox: box, dx: -0.4, dy: -0.2)) == lines[2])
            #expect(geometry.line(at: point(inBox: box, dx: -0.4, dy: 0.2)) == lines[2])
            #expect(geometry.line(at: point(inBox: box, dx: 0.4, dy: -0.2)) == lines[3])
            #expect(geometry.line(at: point(inBox: box, dx: 0.4, dy: 0.2)) == lines[3])
            // Closer to the top or bottom than to a side picks that edge.
            #expect(geometry.line(at: point(inBox: box, dx: -0.2, dy: -0.4)) == lines[0])
            #expect(geometry.line(at: point(inBox: box, dx: 0.2, dy: -0.4)) == lines[0])
            #expect(geometry.line(at: point(inBox: box, dx: -0.2, dy: 0.4)) == lines[1])
            #expect(geometry.line(at: point(inBox: box, dx: 0.2, dy: 0.4)) == lines[1])
        }
    }

    @Test func theCenterOfABoxStillPicksOneOfItsLines() throws {
        for box in 0..<boxCount {
            let line = try #require(geometry.line(at: point(inBox: box, dx: 0, dy: 0)))

            #expect(DotsAndBoxesBoard.lines(of: box).contains(line))
        }
    }

    @Test func twoBoxesThatShareALineBothPickItNearTheirSharedEdge() {
        // Boxes 5 and 6 are neighbors in the second row. They share the vertical line 27.
        let shared = DotsAndBoxesBoard.verticalLine(row: 1, column: 2)

        #expect(geometry.line(at: point(inBox: 5, dx: 0.49, dy: 0)) == shared)
        #expect(geometry.line(at: point(inBox: 6, dx: -0.49, dy: 0)) == shared)
        #expect(geometry.line(at: point(inBox: 5, dx: 0.49, dy: 0.2)) == shared)
        #expect(geometry.line(at: point(inBox: 6, dx: -0.49, dy: -0.2)) == shared)
    }

    @Test func aPointOutsideTheGridPicksTheNearestBorderLine() {
        let side = geometry.side
        let halfInset = geometry.inset / 2
        let count = DotsAndBoxesBoard.boxesPerSide

        for index in 0..<count {
            let along = geometry.boxRect(index * count + index)
            #expect(
                geometry.line(at: CGPoint(x: halfInset, y: along.midY))
                    == DotsAndBoxesBoard.verticalLine(row: index, column: 0)
            )
            #expect(
                geometry.line(at: CGPoint(x: side - halfInset, y: along.midY))
                    == DotsAndBoxesBoard.verticalLine(row: index, column: count)
            )
            #expect(
                geometry.line(at: CGPoint(x: along.midX, y: halfInset))
                    == DotsAndBoxesBoard.horizontalLine(row: 0, column: index)
            )
            #expect(
                geometry.line(at: CGPoint(x: along.midX, y: side - halfInset))
                    == DotsAndBoxesBoard.horizontalLine(row: count, column: index)
            )
        }
    }

    @Test func aTapInACornerPicksABorderLineOfTheCornerBox() throws {
        let side = geometry.side
        let corners: [(point: CGPoint, box: Int)] = [
            (CGPoint(x: 0, y: 0), 0),
            (CGPoint(x: side, y: 0), 3),
            (CGPoint(x: 0, y: side), 12),
            (CGPoint(x: side, y: side), 15),
            (CGPoint(x: geometry.inset, y: geometry.inset), 0),
            (CGPoint(x: side - geometry.inset, y: side - geometry.inset), 15)
        ]

        for corner in corners {
            let line = try #require(geometry.line(at: corner.point))

            // Only a border line touches just the corner box.
            #expect(DotsAndBoxesBoard.boxes(touching: line) == [corner.box])
        }
    }

    @Test func everyPointOnTheBoardPicksALineOfTheBoxItIsIn() throws {
        let count = DotsAndBoxesBoard.boxesPerSide
        let grid = geometry.gridRect

        for stepX in stride(from: -20.0, through: geometry.side + 20, by: 7.3) {
            for stepY in stride(from: -20.0, through: geometry.side + 20, by: 7.3) {
                let point = CGPoint(x: stepX, y: stepY)
                let line = try #require(geometry.line(at: point))
                let column = min(max(Int((point.x - grid.minX) / geometry.cell), 0), count - 1)
                let row = min(max(Int((point.y - grid.minY) / geometry.cell), 0), count - 1)

                #expect((0..<DotsAndBoxesBoard.moveLimit).contains(line))
                #expect(DotsAndBoxesBoard.boxes(touching: line).contains(row * count + column))
            }
        }
    }

    @Test func aBoardWithNoSizePicksNothing() {
        let empty = DotsAndBoxesBoardGeometry(side: 0)

        #expect(empty.line(at: .zero) == nil)
        #expect(geometry.line(at: CGPoint(x: CGFloat.nan, y: 10)) == nil)
    }

    @Test func aTouchCountsOnlyNearTheBoard() {
        #expect(geometry.touchBounds.contains(CGPoint(x: 200, y: 200)))
        #expect(geometry.touchBounds.contains(CGPoint(x: -10, y: 410)))
        #expect(!geometry.touchBounds.contains(CGPoint(x: -100, y: 200)))
        #expect(!geometry.touchBounds.contains(CGPoint(x: 200, y: 600)))
    }
}
