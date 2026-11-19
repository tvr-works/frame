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
    func isNoOp(for window: Window) -> Bool {
        guard let source = window.column else { return false }
        switch self {
            case .insert(let column, let slot):
                guard source === column, let index = window.ownIndex else { return false }
                // Slots on both sides of the window resolve to its current index after removal.
                return slot == index || slot == index + 1
            case .newColumn(let workspace, let before):
                guard source.nodeWorkspace === workspace, source.children.count == 1,
                      let index = source.ownIndex
                else { return false }
                let slot = before?.ownIndex ?? workspace.columns.count
                return slot == index || slot == index + 1
        }
    }

    @MainActor
    @discardableResult
    package func apply(to window: Window) -> Bool {
        guard window.column != nil, let workspace, workspace.isVisible else { return false }
        switch self {
            case .insert(let column, let slot):
                return window.insert(into: column, at: slot)
            case .newColumn(_, let before):
                guard before == nil || before?.parent === workspace.columnsRoot else { return false }
                if isNoOp(for: window) { return true }
                let column = before.map { workspace.addColumn(before: $0) } ?? workspace.addColumn(after: nil)
                return window.insert(into: column, at: 0)
        }
    }
}

package struct WindowDropPreview {
    package let rect: Rect
}

package struct WindowDropTarget {
    private static let previewThickness: CGFloat = 2

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
        // Candidates list column boundaries first so they win even with zero gaps.
        return targets.first(where: { $0.activationRect.contains(pointer) })
    }

    @MainActor
    private static func candidates(workspace: Workspace, area: Rect) -> [WindowDropTarget] {
        let columns = workspace.columns
        let lineWidth = min(previewThickness, area.width)
        if columns.isEmpty {
            let preview = Rect(topLeftX: area.center.x - lineWidth / 2, topLeftY: area.minY, width: lineWidth, height: area.height)
            return [WindowDropTarget(destination: .newColumn(workspace: workspace, before: nil),
                                     preview: WindowDropPreview(rect: preview), activationRect: area)]
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
            let left = index == 0 ? monitorArea.minX : min(rects[index - 1].maxX, x - band)
            let right = index == columns.count ? monitorArea.maxX : max(rects[index].minX, x + band)
            let activation = Rect(topLeftX: left, topLeftY: monitorArea.minY, width: right - left, height: monitorArea.height)
            let preview = Rect(topLeftX: min(max(x - lineWidth / 2, area.minX), area.maxX - lineWidth),
                               topLeftY: area.minY, width: lineWidth, height: area.height)
            result.append(WindowDropTarget(destination: .newColumn(workspace: workspace, before: columns.getOrNil(atIndex: index)),
                                           preview: WindowDropPreview(rect: preview), activationRect: activation))
        }
        let lineHeight = min(previewThickness, area.height)
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
                let preview = Rect(topLeftX: rects[index].minX, topLeftY: max(area.minY, min(lineY - lineHeight / 2, area.maxY - lineHeight)),
                                   width: rects[index].width, height: lineHeight)
                result.append(WindowDropTarget(destination: .insert(column: column, slot: slot),
                                               preview: WindowDropPreview(rect: preview), activationRect: activation))
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
