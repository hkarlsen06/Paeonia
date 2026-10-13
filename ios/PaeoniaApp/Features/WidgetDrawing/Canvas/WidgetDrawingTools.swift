import PencilKit
import SwiftUI
import UIKit

struct WidgetDrawingColorChoice: Identifiable, Equatable {
    let id: String
    let color: Color
    let uiColor: UIColor
    let accessibilityLabel: LocalizedStringResource

    static func == (lhs: WidgetDrawingColorChoice, rhs: WidgetDrawingColorChoice) -> Bool {
        lhs.id == rhs.id
    }
}

extension WidgetDrawingColorChoice {
    /// The fixed ink palette offered by the drawing tools.
    static let palette: [WidgetDrawingColorChoice] = [
        WidgetDrawingColorChoice(
            id: "blush",
            color: .paeoniaWidgetDrawing,
            uiColor: .paeoniaWidgetDrawing,
            accessibilityLabel: .widgetDrawingColorBlush
        ),
        WidgetDrawingColorChoice(
            id: "petal",
            color: .paeoniaAccentPrimary,
            uiColor: .paeoniaAccentPrimary,
            accessibilityLabel: .widgetDrawingColorPetal
        ),
        WidgetDrawingColorChoice(
            id: "pink",
            color: .paeoniaAccentSecondary,
            uiColor: .paeoniaAccentSecondary,
            accessibilityLabel: .widgetDrawingColorPink
        ),
        WidgetDrawingColorChoice(
            id: "warm",
            color: .paeoniaPartnerTwo,
            uiColor: .paeoniaPartnerTwo,
            accessibilityLabel: .widgetDrawingColorWarm
        ),
        WidgetDrawingColorChoice(
            id: "green",
            color: .paeoniaSuccess,
            uiColor: .paeoniaSuccess,
            accessibilityLabel: .widgetDrawingColorGreen
        ),
        WidgetDrawingColorChoice(
            id: "gold",
            color: .paeoniaInkGold,
            uiColor: .paeoniaInkGold,
            accessibilityLabel: .widgetDrawingColorGold
        ),
        WidgetDrawingColorChoice(
            id: "blue",
            color: .paeoniaInkBlue,
            uiColor: .paeoniaInkBlue,
            accessibilityLabel: .widgetDrawingColorBlue
        ),
        WidgetDrawingColorChoice(
            id: "lavender",
            color: .paeoniaInkLavender,
            uiColor: .paeoniaInkLavender,
            accessibilityLabel: .widgetDrawingColorLavender
        ),
    ]
}

enum WidgetDrawingTool: CaseIterable, Equatable, Identifiable {
    case pen
    case pencil
    case fill
    case eraser

    var id: Self { self }

    var isEraser: Bool {
        self == .eraser
    }

    /// The paint bucket fills on a tap instead of drawing, so it has no size.
    var isFill: Bool {
        self == .fill
    }

    var systemImageName: String {
        switch self {
        case .pen:
            "pencil.tip"
        case .pencil:
            "pencil"
        case .fill:
            "paint.bucket.classic"
        case .eraser:
            "eraser.fill"
        }
    }

    var accessibilityLabel: LocalizedStringResource {
        switch self {
        case .pen:
            .widgetDrawingToolPen
        case .pencil:
            .widgetDrawingToolPencil
        case .fill:
            .widgetDrawingToolFill
        case .eraser:
            .widgetDrawingToolEraser
        }
    }

    func pencilKitTool(color: UIColor, width: CGFloat) -> any PKTool {
        let clampedWidth = clampedWidth(width)

        return switch self {
        // The canvas takes no strokes while the bucket is picked. The fill
        // itself is made in `DrawingFloodFill` on a tap.
        case .pen, .fill:
            // PencilKit's `.pen` ink sizes finger strokes by speed and mostly
            // ignores the width, so the size slider barely changed it. Monoline
            // draws exactly the width it is given.
            PKInkingTool(.monoline, color: color, width: clampedWidth)
        case .pencil:
            PKInkingTool(.pencil, color: color, width: clampedWidth)
        case .eraser:
            PKEraserTool(.fixedWidthBitmap, width: clampedWidth)
        }
    }

    func clampedWidth(_ width: CGFloat) -> CGFloat {
        min(max(validWidthRange.lowerBound, width), validWidthRange.upperBound)
    }

    /// Maps a `0...1` slider position onto this tool's own valid width range, so
    /// the full slider travel always spans the tool's smallest-to-largest width.
    func width(forFraction fraction: CGFloat) -> CGFloat {
        let clampedFraction = min(max(0, fraction), 1)
        let range = validWidthRange
        return range.lowerBound + (range.upperBound - range.lowerBound) * clampedFraction
    }

    /// Each tool has its own width range, which is why a single fixed slider
    /// range cannot be shared. Monoline reports `0.5...4`, too thin to be
    /// useful, but it draws wider widths correctly, so the pen sets its own.
    var validWidthRange: ClosedRange<CGFloat> {
        switch self {
        case .pen, .fill:
            1...12
        case .pencil:
            PKInkingTool.InkType.pencil.validWidthRange
        case .eraser:
            PKEraserTool.EraserType.fixedWidthBitmap.validWidthRange
        }
    }
}

extension UIColor {
    /// Resolves a picked color to literal sRGB, the same in light and dark mode,
    /// so PencilKit stores the exact ink the person chose.
    static func paeoniaDrawingColor(from cgColor: CGColor) -> UIColor {
        let resolvedColor = UIColor(cgColor: cgColor).resolvedColor(
            with: UITraitCollection(userInterfaceStyle: .light)
        )

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let convertedColor = resolvedColor.cgColor.converted(
                  to: colorSpace,
                  intent: .defaultIntent,
                  options: nil
              )
        else {
            return resolvedColor
        }

        return UIColor(cgColor: convertedColor)
    }
}
