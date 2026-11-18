@testable import FrameEngine
@testable import FrameMacOS
import FrameTestSupport
import XCTest

@MainActor
final class MouseReleaseTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testReleaseCommitsMoveWhenAXMovedHasNotStartedDrag() async throws {
        let workspace = currentSession.focus.workspace
        let column = workspace.addColumn(after: nil)
        let a = TestWindow.new(id: 1, parent: column)
        let b = TestWindow.new(id: 2, parent: column)
        let c = TestWindow.new(id: 3, parent: column)
        XCTAssertTrue(a.focusWindow())
        try await workspace.layoutWorkspace()
        let original = try XCTUnwrap(a.lastAppliedLayoutPhysicalRect)
        let target = try XCTUnwrap(c.lastAppliedLayoutPhysicalRect)
        a.putUserData(key: mouseDownGeometryKey, data: MouseDownWindowGeometry(rect: original))
        recordMouseDraggedEvent(session: currentSession)
        var moved = original
        moved.topLeftY = target.maxY - 20
        TestApp.shared.setWindowRect(windowId: a.platformWindowId, moved)
        XCTAssertNil(currentSession.windowDrag)
        XCTAssertTrue(hasPendingMouseMove(session: currentSession))

        try await beginPendingWindowDragAfterMouseUp(session: currentSession)
        XCTAssertTrue(currentSession.finishWindowDrag(at: CGPoint(x: target.center.x, y: target.maxY - 20)))

        XCTAssertEqual(column.children, [b, c, a])
        XCTAssertNil(currentSession.currentlyManipulatedWithMouseWindowId)
        clearMouseDownWindowGeometry()
        XCTAssertFalse(hasPendingMouseMove(session: currentSession))
    }

    func testReleaseDoesNotTreatSmallTopLeftResizeAsMove() async throws {
        let window = try await windowWithMouseDownSnapshot()
        let original = try XCTUnwrap(window.lastAppliedLayoutPhysicalRect)
        var resized = original
        resized.topLeftX += 1
        resized.width -= 1
        TestApp.shared.setWindowRect(windowId: window.platformWindowId, resized)
        recordMouseDraggedEvent(session: currentSession)

        try await beginPendingWindowDragAfterMouseUp(session: currentSession)

        XCTAssertNil(currentSession.windowDrag)
        XCTAssertNil(currentSession.currentlyManipulatedWithMouseWindowId)
    }

    func testMouseUpUsesReleasePointAfterPointerMovesElsewhere() async throws {
        let workspace = currentSession.focus.workspace
        let column = workspace.addColumn(after: nil)
        let a = TestWindow.new(id: 1, parent: column)
        let b = TestWindow.new(id: 2, parent: column)
        let c = TestWindow.new(id: 3, parent: column)
        XCTAssertTrue(a.focusWindow())
        try await workspace.layoutWorkspace()
        let original = try XCTUnwrap(a.lastAppliedLayoutPhysicalRect)
        let target = try XCTUnwrap(c.lastAppliedLayoutPhysicalRect)
        let futurePointer = original.center
        currentSession.platformServices.mouseLocation = { futurePointer }
        currentSession.platformServices.nativeFocusedWindow = {
            NativeFocusedWindowSnapshot(app: TestApp.shared, platformWindowId: a.platformWindowId)
        }
        currentSession.platformServices.refreshPlatformState = { .unavailable(reason: .screenLocked) }
        XCTAssertTrue(currentSession.beginWindowDrag(a))

        await GlobalObserver.handleLeftMouseUp(session: currentSession, at: CGPoint(x: target.center.x, y: target.maxY - 20))

        XCTAssertEqual(column.children, [b, c, a])
        XCTAssertNil(currentSession.windowDrag)
        XCTAssertNil(currentSession.currentlyManipulatedWithMouseWindowId)
    }

    func testContentSelectionDoesNotStartWindowDrag() async throws {
        _ = try await windowWithMouseDownSnapshot()
        recordMouseDraggedEvent(session: currentSession)

        try await beginPendingWindowDragAfterMouseUp(session: currentSession)

        XCTAssertNil(currentSession.windowDrag)
    }

    func testProgrammaticMoveWithoutPointerDragDoesNotStartDrag() async throws {
        let window = try await windowWithMouseDownSnapshot()
        var rect = try XCTUnwrap(window.lastAppliedLayoutPhysicalRect)
        rect.topLeftX += 100
        TestApp.shared.setWindowRect(windowId: window.platformWindowId, rect)

        try await beginPendingWindowDragAfterMouseUp(session: currentSession)

        XCTAssertNil(currentSession.windowDrag)
    }

    func testActiveResizeIsNotReclassifiedOnRelease() async throws {
        let window = try await windowWithMouseDownSnapshot()
        recordMouseDraggedEvent(session: currentSession)
        currentSession.currentlyManipulatedWithMouseWindowId = window.windowId

        XCTAssertFalse(hasPendingMouseMove(session: currentSession))
        try await beginPendingWindowDragAfterMouseUp(session: currentSession)

        XCTAssertNil(currentSession.windowDrag)
        XCTAssertEqual(currentSession.currentlyManipulatedWithMouseWindowId, window.windowId)
    }

    private func windowWithMouseDownSnapshot() async throws -> Window {
        let workspace = currentSession.focus.workspace
        let window = TestWindow.new(id: 1, parent: workspace.addColumn(after: nil))
        XCTAssertTrue(window.focusWindow())
        try await workspace.layoutWorkspace()
        let rect = try XCTUnwrap(window.lastAppliedLayoutPhysicalRect)
        window.putUserData(key: mouseDownGeometryKey, data: MouseDownWindowGeometry(rect: rect))
        return window
    }
}
