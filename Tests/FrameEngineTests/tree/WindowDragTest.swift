@testable import FrameEngine
import FrameTestSupport
import XCTest

private struct DragTestMonitor: Monitor {
    let systemMonitorIndex = 2
    let name = "Portrait secondary"
    let rect = Rect(topLeftX: 1920, topLeftY: -200, width: 1000, height: 1600)
    var visibleRect: Rect { rect }
    let isMain = false
    var width: CGFloat { rect.width }
    var height: CGFloat { rect.height }
}

@MainActor
final class WindowDragTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testHoverDoesNotReorderAndReleaseCommitsOnce() async throws {
        let workspace = currentSession.focus.workspace
        let column = workspace.addColumn(after: nil)
        let a = TestWindow.new(id: 1, parent: column)
        let b = TestWindow.new(id: 2, parent: column)
        let c = TestWindow.new(id: 3, parent: column)
        XCTAssertTrue(a.focusWindow())
        try await workspace.layoutWorkspace()
        let origin = try XCTUnwrap(a.lastAppliedLayoutPhysicalRect)
        let target = try XCTUnwrap(c.lastAppliedLayoutPhysicalRect)
        let point = CGPoint(x: target.center.x, y: target.maxY - 20)
        var previews: [Bool] = []
        currentSession.platformServices.showWindowDropPreview = { previews.append($0 != nil) }

        XCTAssertTrue(currentSession.beginWindowDrag(a))
        currentSession.updateWindowDrag(at: point)
        try await workspace.layoutWorkspace()
        XCTAssertEqual(column.children, [a, b, c])
        XCTAssertEqual(a.lastAppliedLayoutPhysicalRect?.topLeftCorner, origin.topLeftCorner)
        XCTAssertEqual(currentSession.windowDrag?.target?.destination, .insert(column: column, slot: 3))

        XCTAssertTrue(currentSession.finishWindowDrag(at: point))
        XCTAssertEqual(column.children, [b, c, a])
        XCTAssertFalse(currentSession.finishWindowDrag(at: point))
        XCTAssertNil(currentSession.windowDrag)
        XCTAssertNil(currentSession.currentlyManipulatedWithMouseWindowId)
        XCTAssertEqual(previews, [true, false])
    }

    func testReturnToOriginalSlotAndCancellationLeaveOrderUnchanged() async throws {
        let workspace = currentSession.focus.workspace
        let column = workspace.addColumn(after: nil)
        let a = TestWindow.new(id: 1, parent: column)
        let b = TestWindow.new(id: 2, parent: column)
        XCTAssertTrue(a.focusWindow())
        try await workspace.layoutWorkspace()
        let original = try XCTUnwrap(a.lastAppliedLayoutPhysicalRect).center
        let away = try XCTUnwrap(b.lastAppliedLayoutPhysicalRect).center
        XCTAssertTrue(currentSession.beginWindowDrag(a))
        currentSession.updateWindowDrag(at: away)
        XCTAssertTrue(currentSession.finishWindowDrag(at: original))
        XCTAssertEqual(column.children, [a, b])
        XCTAssertTrue(currentSession.beginWindowDrag(a))
        currentSession.updateWindowDrag(at: away)
        currentSession.cancelWindowDrag()
        XCTAssertEqual(column.children, [a, b])
        XCTAssertNil(currentSession.currentlyManipulatedWithMouseWindowId)
    }

    func testCrossMonitorDropStacksWithSingleWindowAndRetainsFocus() async throws {
        let primary = currentSession.platformServices.mainMonitor()
        let secondary = DragTestMonitor()
        currentSession.platformServices.monitors = { [primary, secondary] }
        let sourceWorkspace = currentSession.focus.workspace
        let destinationWorkspace = Workspace.get(byName: "destination")
        XCTAssertTrue(secondary.setActiveWorkspace(destinationWorkspace))
        let source = sourceWorkspace.addColumn(after: nil)
        let destination = destinationWorkspace.addColumn(after: nil)
        let a = TestWindow.new(id: 1, parent: source)
        let b = TestWindow.new(id: 2, parent: destination)
        XCTAssertTrue(a.focusWindow())
        try await sourceWorkspace.layoutWorkspace()
        try await destinationWorkspace.layoutWorkspace()
        let target = try XCTUnwrap(b.lastAppliedLayoutPhysicalRect)
        let point = CGPoint(x: target.center.x, y: target.maxY - 20)

        XCTAssertTrue(currentSession.beginWindowDrag(a))
        currentSession.updateWindowDrag(at: point)
        XCTAssertTrue(a.nodeWorkspace === sourceWorkspace)
        XCTAssertTrue(currentSession.finishWindowDrag(at: point))
        currentSession.refreshModel()
        XCTAssertEqual(destinationWorkspace.columns, [destination])
        XCTAssertEqual(destination.children, [b, a])
        XCTAssertTrue(sourceWorkspace.columns.isEmpty)
        XCTAssertTrue(currentSession.focus.windowOrNil === a)
        XCTAssertTrue(currentSession.focus.workspace === destinationWorkspace)
    }

    func testCrossMonitorEmptyWorkspaceCreatesFirstColumn() async throws {
        let primary = currentSession.platformServices.mainMonitor()
        let secondary = DragTestMonitor()
        currentSession.platformServices.monitors = { [primary, secondary] }
        let sourceWorkspace = currentSession.focus.workspace
        let destinationWorkspace = Workspace.get(byName: "empty")
        XCTAssertTrue(secondary.setActiveWorkspace(destinationWorkspace))
        let column = sourceWorkspace.addColumn(after: nil)
        let window = TestWindow.new(id: 1, parent: column)
        XCTAssertTrue(window.focusWindow())
        try await sourceWorkspace.layoutWorkspace()
        XCTAssertTrue(currentSession.beginWindowDrag(window))
        XCTAssertTrue(currentSession.finishWindowDrag(at: secondary.rect.center))
        XCTAssertEqual(destinationWorkspace.columns.count, 1)
        XCTAssertEqual(destinationWorkspace.columns[0].children, [window])
    }

    func testInvalidDropRestoresManagedMembership() async throws {
        let column = currentSession.focus.workspace.addColumn(after: nil)
        let window = TestWindow.new(id: 1, parent: column)
        XCTAssertTrue(window.focusWindow())
        try await currentSession.focus.workspace.layoutWorkspace()
        let original = try XCTUnwrap(window.lastAppliedLayoutPhysicalRect)
        XCTAssertTrue(currentSession.beginWindowDrag(window))
        TestApp.shared.setWindowRect(windowId: window.platformWindowId, Rect(topLeftX: -500, topLeftY: -500, width: 500, height: 500))
        XCTAssertFalse(currentSession.finishWindowDrag(at: CGPoint(x: -500, y: -500)))
        try await currentSession.focus.workspace.layoutWorkspace()
        let restored = try await window.getRect()
        XCTAssertEqual(restored?.topLeftCorner, original.topLeftCorner)
        XCTAssertEqual(restored?.size, original.size)
        XCTAssertEqual(column.children, [window])
        XCTAssertNil(currentSession.windowDrag)
        XCTAssertNil(currentSession.currentlyManipulatedWithMouseWindowId)
    }

    func testFocusLossAndExternalMoveCancelDrag() async throws {
        let workspace = currentSession.focus.workspace
        let source = workspace.addColumn(after: nil)
        let destination = workspace.addColumn(after: nil)
        let a = TestWindow.new(id: 1, parent: source)
        let b = TestWindow.new(id: 2, parent: destination)
        XCTAssertTrue(a.focusWindow())
        try await workspace.layoutWorkspace()
        XCTAssertTrue(currentSession.beginWindowDrag(a))
        XCTAssertTrue(b.focusWindow())
        currentSession.refreshModel()
        XCTAssertNil(currentSession.windowDrag)
        XCTAssertNil(currentSession.currentlyManipulatedWithMouseWindowId)

        XCTAssertTrue(a.focusWindow())
        XCTAssertTrue(currentSession.beginWindowDrag(a))
        XCTAssertTrue(a.insert(into: destination, at: 0))
        currentSession.refreshModel()
        XCTAssertNil(currentSession.windowDrag)
        XCTAssertEqual(destination.children, [a, b])
    }

    func testResizeAndFullscreenOverlayCannotStartDrag() async throws {
        let column = currentSession.focus.workspace.addColumn(after: nil)
        let window = TestWindow.new(id: 1, parent: column)
        XCTAssertTrue(window.focusWindow())
        try await currentSession.focus.workspace.layoutWorkspace()
        currentSession.currentlyManipulatedWithMouseWindowId = window.windowId
        XCTAssertFalse(currentSession.beginWindowDrag(window))
        currentSession.currentlyManipulatedWithMouseWindowId = nil
        window.isFullscreenOverlay = true
        XCTAssertFalse(currentSession.beginWindowDrag(window))
    }

    func testClosingDraggedWindowClearsPreviewAndManipulation() async throws {
        let column = currentSession.focus.workspace.addColumn(after: nil)
        let window = TestWindow.new(id: 1, parent: column)
        XCTAssertTrue(window.focusWindow())
        try await currentSession.focus.workspace.layoutWorkspace()
        XCTAssertTrue(currentSession.beginWindowDrag(window))
        window.garbageCollect()
        currentSession.refreshModel()
        XCTAssertNil(currentSession.windowDrag)
        XCTAssertNil(currentSession.currentlyManipulatedWithMouseWindowId)
    }

    func testDisconnectedDestinationMonitorCannotReceiveDrop() async throws {
        let primary = currentSession.platformServices.mainMonitor()
        let secondary = DragTestMonitor()
        currentSession.platformServices.monitors = { [primary, secondary] }
        let sourceWorkspace = currentSession.focus.workspace
        let destinationWorkspace = Workspace.get(byName: "destination")
        XCTAssertTrue(secondary.setActiveWorkspace(destinationWorkspace))
        let source = sourceWorkspace.addColumn(after: nil)
        let window = TestWindow.new(id: 1, parent: source)
        XCTAssertTrue(window.focusWindow())
        try await sourceWorkspace.layoutWorkspace()
        XCTAssertTrue(currentSession.beginWindowDrag(window))
        currentSession.updateWindowDrag(at: secondary.rect.center)
        XCTAssertNotNil(currentSession.windowDrag?.target)
        currentSession.platformServices.monitors = { [primary] }
        XCTAssertFalse(currentSession.finishWindowDrag(at: secondary.rect.center))
        XCTAssertTrue(window.nodeWorkspace === sourceWorkspace)
        XCTAssertTrue(destinationWorkspace.columns.isEmpty)
        XCTAssertNil(currentSession.windowDrag)
    }
}
