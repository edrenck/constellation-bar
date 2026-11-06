import Foundation

/// Geometry shared by actual windows and fixtures. Content supplies scrolling when constrained.
enum WindowPlacement {
    static func constrain(_ proposed: NSRect, to visible: NSRect, inset: CGFloat = 0) -> NSRect {
        let dx = min(max(0, inset), max(0, (visible.width-1)/2))
        let dy = min(max(0, inset), max(0, (visible.height-1)/2))
        let available = visible.insetBy(dx: dx, dy: dy)
        let size = NSSize(width: min(max(1, proposed.width), max(1, available.width)),
                          height: min(max(1, proposed.height), max(1, available.height)))
        return NSRect(x: min(max(available.minX, proposed.minX), available.maxX-size.width),
                      y: min(max(available.minY, proposed.minY), available.maxY-size.height), width: size.width, height: size.height)
    }
}
