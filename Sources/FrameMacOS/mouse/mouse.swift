import AppKit
import FrameEngine

var isLeftMouseButtonDown: Bool { NSEvent.pressedMouseButtons == 1 }

private let mouseDownSizeKey = TreeNodeUserDataKey<CGSize>(key: "mouseDownSize")

@MainActor
func recordMouseDownWindowSize(session: AppSession) async throws {
    guard session === currentSession else { return }
    clearMouseDownWindowSizes()
    guard let focused = try await session.platformServices.nativeFocusedWindow(),
          let window = Window.get(byPlatformWindowId: focused.platformWindowId),
          window.app.pid == focused.app.pid,
          let size = try await window.getSize(), isLeftMouseButtonDown, session === currentSession
    else { return }
    window.putUserData(key: mouseDownSizeKey, data: size)
}

@MainActor
func clearMouseDownWindowSizes() {
    for window in Window.allWindows { window.cleanUserData(key: mouseDownSizeKey) }
}

@MainActor
func mouseDownWindowSize(_ window: Window) -> CGSize? {
    window.getUserData(key: mouseDownSizeKey)
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
