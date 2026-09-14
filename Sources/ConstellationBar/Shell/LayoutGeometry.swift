import Foundation

/// Shared by the live bar and preview. Every returned frame stays inside its region.
struct LayoutGeometry {
    var workspace: CGRect
    var focus: CGRect
    var widgets: CGRect
    var widgetBudget: CGFloat

    static func resolve(width: CGFloat, height: CGFloat, margin: CGFloat, workspaceWidth: CGFloat, focusWidth: CGFloat, widgetWidth: CGFloat, leadingWidgets: Bool, exclusion: ClosedRange<CGFloat>? = nil, centered: Bool = false) -> LayoutGeometry {
        let inset = min(margin, max(0, width / 4))
        if let exclusion {
            let left = inset...max(inset, exclusion.lowerBound - 8)
            let right = min(width - inset, exclusion.upperBound + 8)...max(inset, width - inset)
            let workRegion = leadingWidgets ? right : left
            let statusRegion = leadingWidgets ? left : right
            let workAvailable = max(0, workRegion.upperBound - workRegion.lowerBound)
            let statusAvailable = max(0, statusRegion.upperBound - statusRegion.lowerBound)
            let workspace = min(workspaceWidth, workAvailable * (focusWidth > 0 ? 0.70 : 1))
            let focus = min(focusWidth, max(0, workAvailable - workspace - (workspace > 0 ? 12 : 0)))
            let widgets = min(widgetWidth, statusAvailable)
            let h = min(34, height), y = (height - h) / 2
            var result = LayoutGeometry(
                workspace: CGRect(x: leadingWidgets ? workRegion.upperBound - workspace : workRegion.lowerBound, y: y, width: workspace, height: h),
                focus: CGRect(x: leadingWidgets ? workRegion.upperBound - workspace - (workspace > 0 ? 12 : 0) - focus : workRegion.lowerBound + workspace + (workspace > 0 ? 12 : 0), y: y, width: focus, height: h),
                widgets: CGRect(x: leadingWidgets ? statusRegion.lowerBound : statusRegion.upperBound - widgets, y: y, width: widgets, height: h), widgetBudget: statusAvailable)
            if centered {
                // Pack each group against the camera's safe area, never underneath it.
                let groupWidth = workspace + focus + (workspace > 0 && focus > 0 ? 12 : 0)
                let start = leadingWidgets ? workRegion.lowerBound : workRegion.upperBound - groupWidth
                result.workspace.origin.x = leadingWidgets ? start + groupWidth - workspace : start
                result.focus.origin.x = leadingWidgets ? start : start + workspace + (workspace > 0 ? 12 : 0)
                result.widgets.origin.x = leadingWidgets ? statusRegion.upperBound - widgets : statusRegion.lowerBound
            }
            return result
        }
        let available = max(0, width - inset * 2)
        let gap: CGFloat = available > 100 ? 12 : 0
        let workspace = min(workspaceWidth, available * 0.42)
        let budget = max(0, available - workspace - (workspace > 0 ? gap : 0))
        let widgets = min(widgetWidth, max(0, budget - min(110, budget * 0.25)))
        let focus = min(focusWidth, max(0, budget - widgets - (widgets > 0 ? gap : 0)))
        let contentHeight = min(34, height)
        let y = (height - contentHeight) / 2
        var result = LayoutGeometry(
            workspace: CGRect(x: inset, y: y, width: workspace, height: contentHeight),
            focus: CGRect(x: inset + workspace + (workspace > 0 ? gap : 0), y: y, width: focus, height: contentHeight),
            widgets: CGRect(x: width - inset - widgets, y: y, width: widgets, height: contentHeight), widgetBudget: max(0, budget - min(110, budget * 0.25)))
        if leadingWidgets {
            result.widgets.origin.x = inset
            result.workspace.origin.x = width - inset - workspace
            result.focus.origin.x = max(inset + widgets + gap, result.workspace.minX - gap - focus)
        }
        if centered {
            let ordered = leadingWidgets ? [2, 1, 0] : [0, 1, 2]
            var frames = [result.workspace, result.focus, result.widgets]
            let visible = ordered.filter { frames[$0].width > 0 }
            let total = visible.reduce(CGFloat(0)) { $0 + frames[$1].width } + CGFloat(max(0, visible.count - 1)) * gap
            var x = (width - total) / 2
            for index in visible { frames[index].origin.x = x; x += frames[index].width + gap }
            result.workspace = frames[0]; result.focus = frames[1]; result.widgets = frames[2]
        }
        return result
    }
}

/// Independent center and edge widget groups; all regions exclude the camera cutout.
struct GroupedLayoutGeometry {
    var main: LayoutGeometry
    var center: CGRect
    var centerBudget: CGFloat

    static func resolve(width: CGFloat, height: CGFloat, margin: CGFloat, workspaceWidth: CGFloat,
                        focusWidth: CGFloat, widgetWidth: CGFloat, centerWidth: CGFloat,
                        placement: WidgetPlacement, exclusion: ClosedRange<CGFloat>? = nil) -> GroupedLayoutGeometry {
        guard centerWidth > 0 else {
            return .init(main: LayoutGeometry.resolve(width: width, height: height, margin: margin,
                workspaceWidth: workspaceWidth, focusWidth: focusWidth, widgetWidth: widgetWidth,
                leadingWidgets: placement == .leading, exclusion: exclusion, centered: placement == .centered),
                center: .zero, centerBudget: 0)
        }
        let inset = min(max(0, margin), max(0, width / 4)), gap: CGFloat = 12
        let lo = inset, hi = max(lo, width - inset)
        let leading = placement == .leading
        let h = min(34, height), y = (height - h) / 2
        let centerBudget: CGFloat
        let centerX: CGFloat
        let centerSize: CGFloat
        let workLo: CGFloat, workHi: CGFloat, edgeLo: CGFloat, edgeHi: CGFloat
        if let exclusion {
            let leftEnd = max(lo, min(hi, exclusion.lowerBound - 8))
            let rightStart = min(hi, max(lo, exclusion.upperBound + 8))
            let available = leading ? leftEnd - lo : hi - rightStart
            centerBudget = max(0, (available - gap) * 0.5)
            centerSize = min(centerWidth, centerBudget)
            centerX = leading ? leftEnd - centerSize : rightStart
            workLo = leading ? rightStart : lo
            workHi = leading ? hi : leftEnd
            edgeLo = leading ? lo : min(hi, centerX + centerSize + gap)
            edgeHi = leading ? max(lo, centerX - gap) : hi
        } else {
            centerBudget = max(0, (hi - lo) * 0.32)
            centerSize = min(centerWidth, centerBudget)
            centerX = (width - centerSize) / 2
            workLo = leading ? min(hi, centerX + centerSize + gap) : lo
            workHi = leading ? hi : max(lo, centerX - gap)
            edgeLo = leading ? lo : min(hi, centerX + centerSize + gap)
            edgeHi = leading ? max(lo, centerX - gap) : hi
        }
        let workAvailable = max(0, workHi - workLo)
        let ws = min(workspaceWidth, workAvailable * (focusWidth > 0 ? 0.7 : 1))
        let focus = min(focusWidth, max(0, workAvailable - ws - (ws > 0 ? gap : 0)))
        let edgeBudget = max(0, edgeHi - edgeLo), edge = min(widgetWidth, edgeBudget)
        return .init(main: .init(
            workspace: CGRect(x: leading ? workHi - ws : workLo, y: y, width: ws, height: h),
            focus: CGRect(x: leading ? workHi - ws - (ws > 0 ? gap : 0) - focus : workLo + ws + (ws > 0 ? gap : 0), y: y, width: focus, height: h),
            widgets: CGRect(x: leading ? edgeLo : edgeHi - edge, y: y, width: edge, height: h), widgetBudget: edgeBudget),
            center: CGRect(x: centerX, y: y, width: centerSize, height: h), centerBudget: centerBudget)
    }
}

/// Three independent editable zones. This deliberately operates on complete
/// zone widths rather than knowing about specific widgets, so workspaces and
/// the current app follow exactly the same placement rules as system widgets.
struct BarZoneLayoutGeometry {
    var left: CGRect
    var center: CGRect
    var right: CGRect

    static func resolve(width: CGFloat, height: CGFloat, margin: CGFloat, widths: [CGFloat], alignment: WidgetAlignment,
                        exclusion: ClosedRange<CGFloat>? = nil) -> BarZoneLayoutGeometry {
        let inset = min(max(0, margin), max(0, width / 4))
        let requested = Array((widths + [0, 0, 0]).prefix(3)).map { max(0, $0) }
        let h = min(34, height), y = (height - h) / 2
        let gap: CGFloat = 12
        let available = max(0, width - inset * 2)
        func centered(_ values: [CGFloat], lo: CGFloat, hi: CGFloat) -> [CGRect] {
            let count = values.filter { $0 > 0 }.count
            let spacing = min(gap, max(0, hi - lo) / CGFloat(max(1, count - 1)))
            let gaps = CGFloat(max(0, count - 1)) * spacing
            let total = values.reduce(0, +)
            let factor = total > 0 ? min(1, max(0, hi - lo - gaps) / total) : 1
            var x = lo + max(0, hi - lo - total * factor - gaps) / 2
            return values.map { value in
                let frame = CGRect(x: x, y: y, width: value * factor, height: h)
                if value > 0 { x += frame.width + spacing }
                return frame
            }
        }
        if alignment == .centerAll {
            var frames: [CGRect]
            if let exclusion {
                let leftEnd = max(inset, exclusion.lowerBound - gap)
                let rightStart = min(width - inset, exclusion.upperBound + gap)
                // Assign whole zones to either side of the camera. Pick the
                // split that preserves the most content and then center it.
                var best: [CGRect] = []; var bestScore: CGFloat = -1
                for split in 0...3 {
                    let lhs = centered(Array(requested.prefix(split)), lo: inset, hi: leftEnd)
                    let rhs = centered(Array(requested.dropFirst(split)), lo: rightStart, hi: width - inset)
                    let candidate = lhs + rhs
                    let score = candidate.reduce(CGFloat.zero) { $0 + $1.width }
                    if score > bestScore { best = candidate; bestScore = score }
                }
                frames = best
            } else { frames = centered(requested, lo: inset, hi: width - inset) }
            return .init(left: frames[0], center: frames[1], right: frames[2])
        }

        var centerWidth = min(requested[1], available)
        var centerX = (width - centerWidth) / 2
        var leftBudget: CGFloat
        var rightBudget: CGFloat
        if let exclusion {
            let leftEnd = max(inset, exclusion.lowerBound - gap)
            let rightStart = min(width - inset, exclusion.upperBound + gap)
            leftBudget = max(0, leftEnd - inset)
            rightBudget = max(0, width - inset - rightStart)
            if centerWidth > 0 {
                let leftRoom = max(0, leftBudget - min(requested[0], leftBudget / 2) - gap)
                let rightRoom = max(0, rightBudget - min(requested[2], rightBudget / 2) - gap)
                if rightRoom >= leftRoom {
                    centerWidth = min(centerWidth, rightRoom); centerX = rightStart
                    rightBudget = max(0, width - inset - centerX - centerWidth - gap)
                } else {
                    centerWidth = min(centerWidth, leftRoom); centerX = leftEnd - centerWidth
                    leftBudget = max(0, centerX - inset - gap)
                }
            }
        } else if centerWidth > 0 {
            // Reserve the symmetric space around the centered zone before
            // fitting either edge; asymmetric side widths must not push it.
            if requested[0] > 0 || requested[2] > 0 { centerWidth = min(centerWidth, max(0, available * 0.5 - gap)) }
            centerX = (width - centerWidth) / 2
            leftBudget = max(0, centerX - inset - gap)
            rightBudget = max(0, width - inset - centerX - centerWidth - gap)
        } else {
            let total = requested[0] + requested[2]
            let factor = total > 0 ? min(1, max(0, available - (requested[0] > 0 && requested[2] > 0 ? gap : 0)) / total) : 1
            leftBudget = requested[0] * factor; rightBudget = requested[2] * factor
        }
        let leftWidth = min(requested[0], leftBudget), rightWidth = min(requested[2], rightBudget)
        return .init(left: CGRect(x: inset, y: y, width: leftWidth, height: h),
                     center: CGRect(x: centerX, y: y, width: centerWidth, height: h),
                     right: CGRect(x: width - inset - rightWidth, y: y, width: rightWidth, height: h))
    }
}
