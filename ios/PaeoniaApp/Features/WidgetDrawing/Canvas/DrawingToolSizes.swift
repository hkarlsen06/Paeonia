import CoreGraphics
import Foundation

/// The size each drawing tool was last set to, as a size slider position in
/// `0...1`. Every canvas shares these sizes, and they are kept across launches.
enum DrawingToolSizes {
    /// The pen and the pencil start where every tool used to. The eraser
    /// starts bigger, because it clears areas instead of drawing lines.
    private static func defaultFraction(for tool: WidgetDrawingTool) -> CGFloat {
        tool.isEraser ? 0.75 : 0.4
    }

    /// The paint bucket has no size and its slider is off. It reads the
    /// pen's, whose width range it shares.
    private static func sizedTool(_ tool: WidgetDrawingTool) -> WidgetDrawingTool {
        tool.isFill ? .pen : tool
    }

    private static func key(for tool: WidgetDrawingTool) -> String {
        "paeonia.drawing.toolSize.\(sizedTool(tool))"
    }

    static func fraction(for tool: WidgetDrawingTool) -> CGFloat {
        let saved = UserDefaults.standard.object(forKey: key(for: tool)) as? Double
        return saved.map { CGFloat($0) } ?? defaultFraction(for: sizedTool(tool))
    }

    static func save(_ fraction: CGFloat, for tool: WidgetDrawingTool) {
        guard !tool.isFill else {
            return
        }
        UserDefaults.standard.set(Double(fraction), forKey: key(for: tool))
    }
}
