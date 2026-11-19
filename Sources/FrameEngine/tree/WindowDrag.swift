import Common
import Foundation

@MainActor
package final class WindowDrag {
    package let windowId: FrameWindowId
    private let sourceColumn: Column
    private let sourceWorkspace: Workspace
    package private(set) var target: WindowDropTarget?

    fileprivate init(window: Window, column: Column, workspace: Workspace) {
        windowId = window.windowId
        sourceColumn = column
        sourceWorkspace = workspace
    }

    fileprivate func window(in session: AppSession) -> Window? {
        guard let window = session.windowsById[windowId], window.column === sourceColumn,
              session.focus.windowOrNil === window,
              window.nodeWorkspace === sourceWorkspace, sourceWorkspace.isVisible,
              !window.isFullscreenOverlay,
              session.currentlyManipulatedWithMouseWindowId == windowId
        else { return nil }
        return window
    }

    fileprivate func update(at pointer: CGPoint) {
        target = WindowDropTarget.resolve(at: pointer, previous: target)
    }
}

extension AppSession {
    @MainActor
    @discardableResult
    package func beginWindowDrag(_ window: Window) -> Bool {
        guard windowDrag == nil, currentlyManipulatedWithMouseWindowId == nil,
              windowsById[window.windowId] === window,
              let column = window.column, let workspace = window.nodeWorkspace,
              workspace.isVisible, !window.isFullscreenOverlay,
              window.lastAppliedLayoutPhysicalRect != nil
        else { return false }
        // AXMoved may arrive before the refresh that records the newly focused window.
        guard window.focusWindow() else { return false }
        currentlyManipulatedWithMouseWindowId = window.windowId
        windowDrag = WindowDrag(window: window, column: column, workspace: workspace)
        return true
    }

    @MainActor
    package func updateWindowDrag(at pointer: CGPoint) {
        guard let drag = windowDrag else { return }
        guard let window = drag.window(in: self) else {
            cancelWindowDrag()
            return
        }
        drag.update(at: pointer)
        let preview = drag.target.flatMap { $0.destination.isNoOp(for: window) ? nil : $0.preview }
        platformServices.showWindowDropPreview(preview)
    }

    @MainActor
    @discardableResult
    package func finishWindowDrag(at pointer: CGPoint) -> Bool {
        guard let drag = windowDrag else { return false }
        defer { cancelWindowDrag() }
        guard let window = drag.window(in: self) else { return false }
        // Resolve again against the current model; never commit a stale hover target.
        drag.update(at: pointer)
        guard let destination = drag.target?.destination, destination.apply(to: window) else { return false }
        return window.focusWindow()
    }

    @MainActor
    package func cancelWindowDrag() {
        guard let drag = windowDrag else { return }
        if currentlyManipulatedWithMouseWindowId == drag.windowId {
            currentlyManipulatedWithMouseWindowId = nil
        }
        windowDrag = nil
        platformServices.showWindowDropPreview(nil)
    }

    @MainActor
    func validateWindowDrag() {
        if let drag = windowDrag, drag.window(in: self) == nil { cancelWindowDrag() }
    }
}
