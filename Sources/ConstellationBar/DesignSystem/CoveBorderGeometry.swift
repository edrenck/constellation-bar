import AppKit
import SwiftUI

/// Desktop corners use screen points; changing the size of bar content must not resize them.
enum CoveBorderGeometry {
    static func logicalDepth(screenRadius: CGFloat, contentScale: CGFloat) -> CGFloat {
        max(0, screenRadius) / max(0.01, contentScale)
    }

    /// The desktop cutout uses the system's continuous corner shape, inverted below the rail.
    static func mask(in bounds: CGRect, depth: CGFloat) -> CGPath {
        let radius = min(max(0, depth), bounds.height, bounds.width / 2)
        let path = CGMutablePath()
        path.addRect(bounds)
        guard radius > 0 else { return path }
        let desktop = CGRect(x: bounds.minX, y: bounds.minY - bounds.height,
                             width: bounds.width, height: bounds.height + radius)
        path.addPath(RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: desktop).cgPath)
        return path
    }
}
