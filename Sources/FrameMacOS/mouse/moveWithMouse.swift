import AppKit
import Common
import FrameEngine

func movedObs(_ obs: AXObserver, ax: AXUIElement, notif: CFString, data: UnsafeMutableRawPointer?) {
    let windowId = ax.containingWindowId()
    let notif = notif as String
    let session = AppSession.fromCallbackContext(data)
    Task { @MainActor in
        let session = session ?? currentSession
        guard session === currentSession else { return }
        // Leave late move notifications to the release handler before any refresh can snap the window back.
        if !isLeftMouseButtonDown && hasPendingMouseMove(session: session) { return }
        guard let windowId, let window = Window.get(byPlatformWindowId: windowId), try await isManipulatedWithMouse(window) else {
            session.scheduleRefreshSession(.ax(notif))
            return
        }
        if session.windowDrag == nil {
            // Resizing a top/left edge also emits AXMoved. Do not start a drag for it.
            guard session.currentlyManipulatedWithMouseWindowId == nil,
                  let initialSize = mouseDownWindowSize(window), let actual = try await window.getRect(),
                  actual.size == initialSize,
                  isLeftMouseButtonDown, session.beginWindowDrag(window)
            else { return }
        }
        session.updateWindowDrag(at: session.platformServices.mouseLocation())
    }
}

extension CGPoint {
    @MainActor
    func findIn(tree: Column, virtual: Bool) -> Window? {
        let point = self
        let target: TreeNode? = tree.children.first(where: {
            (virtual ? $0.lastAppliedLayoutVirtualRect : $0.lastAppliedLayoutPhysicalRect)?.contains(point) == true
        })
        guard let target else { return nil }
        return switch target.tilingNodeOrNil {
            case .window(let window):
                window
            case .tilingContainer(let container):
                findIn(tree: container, virtual: virtual)
            case nil:
                illegalChildParentRelation(child: target, parent: target.parent)
        }
    }
}
