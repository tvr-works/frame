import Common
import Foundation

package enum WindowDropDestination: Equatable {
    case insert(column: Column, slot: Int)
    case newColumn(workspace: Workspace, before: Column?)

    @MainActor package var workspace: Workspace? {
        switch self {
            case .insert(let column, _): column.nodeWorkspace
            case .newColumn(let workspace, _): workspace
        }
    }

    @MainActor
    @discardableResult
    package func apply(to window: Window) -> Bool {
        guard let sourceColumn = window.column, let workspace, workspace.isVisible else { return false }
        switch self {
            case .insert(let column, let slot):
                return window.insert(into: column, at: slot)
            case .newColumn(_, let before):
                guard before == nil || before?.parent === workspace.columnsRoot else { return false }
                let index = before?.ownIndex ?? workspace.columns.count
                // Moving a sole window immediately beside its own column changes nothing.
                if sourceColumn.nodeWorkspace === workspace, sourceColumn.children.count == 1,
                   let sourceIndex = sourceColumn.ownIndex, index == sourceIndex || index == sourceIndex + 1
                { return true }
                let column = before.map { workspace.addColumn(before: $0) } ?? workspace.addColumn(after: nil)
                return window.insert(into: column, at: 0)
        }
    }
}

package struct WindowDropPreview {
    package let rect: Rect
    package let isNewColumn: Bool
}

package struct WindowDropTarget {
    package let destination: WindowDropDestination
    package let preview: WindowDropPreview
    // A small dead band keeps the target stable when the pointer crosses a midpoint.
    private let activationRect: Rect

    @MainActor
    package static func resolve(at pointer: CGPoint, previous: WindowDropTarget? = nil) -> WindowDropTarget? {
        guard let monitor = monitors.first(where: { $0.rect.contains(pointer) }), monitor.visibleRect.contains(pointer) else { return nil }
        let workspace = monitor.activeWorkspace
        let area = monitor.visibleRectPaddedByOuterGaps
        guard area.width > 0, area.height > 0 else { return nil }
        let columns = workspace.columns
        let targets = candidates(workspace: workspace, area: area)
        if let previous, previous.destination.workspace === workspace,
           previous.activationRect.expanded(by: 4).contains(pointer),
           let current = targets.first(where: { $0.destination == previous.destination }),
           current.activationRect.expanded(by: 4).contains(pointer)
        { return current }
        if columns.isEmpty { return targets.first }
        // Column boundaries have priority over insertion slots, including with zero gaps.
        return targets.first(where: { $0.preview.isNewColumn && $0.activationRect.contains(pointer) })
            ?? targets.first(where: { !$0.preview.isNewColumn && $0.activationRect.contains(pointer) })
    }

    @MainActor
    private static func candidates(workspace: Workspace, area: Rect) -> [WindowDropTarget] {
        let columns = workspace.columns
        if columns.isEmpty {
            return [WindowDropTarget(destination: .newColumn(workspace: workspace, before: nil),
                                     preview: WindowDropPreview(rect: area, isNewColumn: true), activationRect: area)]
        }
        let monitorArea = workspace.workspaceMonitor.visibleRect
        let rects = columns.compactMap(\.lastAppliedLayoutPhysicalRect)
        guard rects.count == columns.count else { return [] }
        let boundaries = [monitorArea.minX] + zip(rects, rects.dropFirst()).map { ($0.maxX + $1.minX) / 2 } + [monitorArea.maxX]
        var result: [WindowDropTarget] = []
        for index in 0 ... columns.count {
            let x = index == 0 ? area.minX : index == columns.count ? area.maxX : boundaries[index]
            let adjacentWidth = min(rects[max(0, index - 1)].width, rects[min(index, rects.count - 1)].width)
            let band = min(12, adjacentWidth / 4)
            let left = index == 0 ? monitorArea.minX : x - band
            let right = index == columns.count ? monitorArea.maxX : x + band
            let activation = Rect(topLeftX: left, topLeftY: monitorArea.minY, width: right - left, height: monitorArea.height)
            let preview = Rect(topLeftX: min(max(x - 12, area.minX), max(area.minX, area.maxX - 24)),
                               topLeftY: area.minY, width: min(24, area.width), height: area.height)
            result.append(WindowDropTarget(destination: .newColumn(workspace: workspace, before: columns.getOrNil(atIndex: index)),
                                           preview: WindowDropPreview(rect: preview, isNewColumn: true), activationRect: activation))
        }
        for (index, column) in columns.enumerated() {
            let windows = column.children.compactMap { $0 as? Window }
            let windowRects = windows.compactMap(\.lastAppliedLayoutPhysicalRect)
            guard windows.count == windowRects.count else { continue }
            for slot in 0 ... windows.count {
                let top = slot == 0 ? monitorArea.minY : windowRects[slot - 1].center.y
                let bottom = slot == windows.count ? monitorArea.maxY : windowRects[slot].center.y
                let lineY = slot == 0 ? rects[index].minY
                    : slot == windows.count ? windowRects[slot - 1].maxY
                    : (windowRects[slot - 1].maxY + windowRects[slot].minY) / 2
                let left = result[index].activationRect.maxX
                let right = result[index + 1].activationRect.minX
                let activation = Rect(topLeftX: left, topLeftY: top, width: right - left, height: bottom - top)
                let preview = Rect(topLeftX: rects[index].minX, topLeftY: max(area.minY, min(lineY - 2, area.maxY - 4)),
                                   width: rects[index].width, height: 4)
                result.append(WindowDropTarget(destination: .insert(column: column, slot: slot),
                                               preview: WindowDropPreview(rect: preview, isNewColumn: false), activationRect: activation))
            }
        }
        return result
    }
}

extension Rect {
    fileprivate func expanded(by amount: CGFloat) -> Rect {
        Rect(topLeftX: minX - amount, topLeftY: minY - amount, width: width + 2 * amount, height: height + 2 * amount)
    }
}
