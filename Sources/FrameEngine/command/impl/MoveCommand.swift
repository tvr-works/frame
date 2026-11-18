import Common

struct MoveCommand: Command {
    let args: MoveCmdArgs

    func run(in session: AppSession, _ env: CmdEnv, _ io: CmdIo) -> Bool {
        let direction = args.direction.val
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        guard let currentWindow = target.windowOrNil else {
            return io.err(noWindowIsFocused)
        }
        guard let parent = currentWindow.parent else { return false }
        if let parent = parent as? Column {
            switch direction.orientation {
                case .h: // left/right — push window to adjacent column
                    return moveWindowBetweenColumns(currentWindow, direction: direction, args, io)
                case .v: // up/down — reorder within column
                    guard parent.orientation == .v else { return true }
                    let indexOfCurrent = currentWindow.ownIndex.orDie()
                    let indexOfTarget = indexOfCurrent + direction.focusOffset
                    guard parent.children.indices.contains(indexOfTarget) else { return true }
                    return currentWindow.insert(into: parent, at: indexOfTarget + (direction == .down ? 1 : 0))
            }
        }
        if parent is ExcludedWindowsContainer {
            return io.err("moving excluded windows isn't supported")
        }
        if parent is NativeMinimizedWindowsContainer || parent is NativeFullscreenWindowsContainer || parent is HiddenAppWindowsContainer {
            return io.err(moveOutUnconventionalWindow)
        }
        return false
    }
}

private let moveOutUnconventionalWindow =
    "moving macOS fullscreen, minimized windows and windows of hidden apps isn't yet supported"

@MainActor private func moveWindowBetweenColumns(
    _ window: Window,
    direction: CardinalDirection,
    _ args: MoveCmdArgs,
    _ io: CmdIo,
) -> Bool {
    guard let workspace = window.nodeWorkspace else { return false }
    let cols = workspace.columns
    guard let currentColumn = window.column,
          let currentIndex = cols.firstIndex(of: currentColumn)
    else {
        // Defensive only. Normal runtime paths should always place tiled windows in a column.
        return true
    }

    let targetIndex = currentIndex + direction.focusOffset
    let targetColumn: Column
    if cols.indices.contains(targetIndex) {
        targetColumn = cols[targetIndex]
    } else {
        switch args.boundariesAction {
            case .stop:
                return true
            case .fail:
                return false
            case .createImplicitContainer:
                if args.boundaries != .workspace {
                    return io.err("create-implicit-container only supports --boundaries workspace")
                }
                if direction == .left {
                    targetColumn = workspace.addColumn(before: currentColumn)
                } else if direction == .right {
                    targetColumn = workspace.addColumn(after: currentColumn)
                } else {
                    return io.err("Invalid move direction for column move: \(direction.rawValue)")
                }
        }
    }
    return window.insert(into: targetColumn, at: targetColumn.children.count)
}
