import AppKit
import FrameEngine

var isLeftMouseButtonDown: Bool { NSEvent.pressedMouseButtons == 1 }

struct MouseDownWindowGeometry {
    let rect: Rect
    var sawMouseDraggedEvent = false

    func wasMoved(to current: Rect) -> Bool {
        sawMouseDraggedEvent && current.size == rect.size && current.topLeftCorner != rect.topLeftCorner
    }
}

let mouseDownGeometryKey = TreeNodeUserDataKey<MouseDownWindowGeometry>(key: "mouseDownGeometry")

@MainActor
func recordMouseDownWindowGeometry(session: AppSession) async throws {
    guard session === currentSession else { return }
    clearMouseDownWindowGeometry()
    guard let focused = try await session.platformServices.nativeFocusedWindow(),
          let window = Window.get(byPlatformWindowId: focused.platformWindowId),
          window.app.pid == focused.app.pid,
          let rect = try await window.getRect(), isLeftMouseButtonDown, session === currentSession
    else { return }
    window.putUserData(key: mouseDownGeometryKey, data: MouseDownWindowGeometry(rect: rect))
}

@MainActor
func clearMouseDownWindowGeometry() {
    for window in Window.allWindows { window.cleanUserData(key: mouseDownGeometryKey) }
}

@MainActor
func mouseDownWindowSize(_ window: Window) -> CGSize? {
    window.getUserData(key: mouseDownGeometryKey)?.rect.size
}

@MainActor
func recordMouseDraggedEvent(session: AppSession) {
    for window in session.windowsById.values {
        guard var geometry = window.getUserData(key: mouseDownGeometryKey) else { continue }
        geometry.sawMouseDraggedEvent = true
        window.putUserData(key: mouseDownGeometryKey, data: geometry)
    }
}

@MainActor
func hasPendingMouseMove(session: AppSession) -> Bool {
    session.currentlyManipulatedWithMouseWindowId == nil && session.windowsById.values.contains {
        $0.getUserData(key: mouseDownGeometryKey)?.sawMouseDraggedEvent == true
    }
}

/// A quick drag can finish before macOS delivers AXMoved. Resolve it from native geometry on release.
@MainActor
func beginPendingWindowDragAfterMouseUp(session: AppSession) async throws {
    guard session.windowDrag == nil, session.currentlyManipulatedWithMouseWindowId == nil,
          let window = session.focus.windowOrNil,
          let geometry = window.getUserData(key: mouseDownGeometryKey),
          let current = try await window.getRect(), geometry.wasMoved(to: current)
    else { return }
    _ = session.beginWindowDrag(window)
}

@MainActor
func isManipulatedWithMouse(_ window: Window) async throws -> Bool {
    try await (!window.isHiddenInCorner && // Don't allow to resize/move windows of hidden workspaces
        isLeftMouseButtonDown &&
        (currentSession.currentlyManipulatedWithMouseWindowId == nil ||
            window.windowId == currentSession.currentlyManipulatedWithMouseWindowId))
        .andAsync { @Sendable @MainActor in
            guard let nativeFocused = try await getNativeFocusedWindow() else { return false }
            return nativeFocused.app.pid == window.app.pid && nativeFocused.platformWindowId == window.platformWindowId
        }
}
