@testable import FrameEngine
import FrameTestSupport
import XCTest

@MainActor
final class WindowDropTargetTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testSingleWindowUsesExplicitStackOrSideTargets() async throws {
        let workspace = currentSession.focus.workspace
        let column = workspace.addColumn(after: nil)
        let window = TestWindow.new(id: 1, parent: column)
        try await workspace.layoutWorkspace()
        let rect = try XCTUnwrap(window.lastAppliedLayoutPhysicalRect)
        XCTAssertEqual(target(rect.center.x, rect.minY + 20), .insert(column: column, slot: 0))
        XCTAssertEqual(target(rect.center.x, rect.maxY - 20), .insert(column: column, slot: 1))
        XCTAssertEqual(target(mainMonitor.visibleRect.minX + 1, rect.center.y), .newColumn(workspace: workspace, before: column))
        XCTAssertEqual(target(mainMonitor.visibleRect.maxX - 1, rect.center.y), .newColumn(workspace: workspace, before: nil))
    }

    func testSlotResolutionAndInsertionPreserveInterveningOrder() async throws {
        let column = currentSession.focus.workspace.addColumn(after: nil)
        let a = TestWindow.new(id: 1, parent: column)
        let b = TestWindow.new(id: 2, parent: column)
        let c = TestWindow.new(id: 3, parent: column)
        try await currentSession.focus.workspace.layoutWorkspace()
        let rect = try XCTUnwrap(c.lastAppliedLayoutPhysicalRect)
        let destination = try XCTUnwrap(target(rect.center.x, rect.maxY - 20))
        XCTAssertEqual(destination, .insert(column: column, slot: 3))
        XCTAssertTrue(destination.apply(to: a))
        XCTAssertEqual(column.children, [b, c, a])
    }

    func testColumnBoundaryWorksWithZeroGaps() async throws {
        currentSession.config.gaps = .zero
        let workspace = currentSession.focus.workspace
        let left = workspace.addColumn(after: nil)
        let right = workspace.addColumn(after: nil)
        let a = TestWindow.new(id: 1, parent: left)
        _ = TestWindow.new(id: 2, parent: left)
        _ = TestWindow.new(id: 3, parent: right)
        try await workspace.layoutWorkspace()
        let l = try XCTUnwrap(left.lastAppliedLayoutPhysicalRect)
        let r = try XCTUnwrap(right.lastAppliedLayoutPhysicalRect)
        let point = CGPoint(x: (l.maxX + r.minX) / 2, y: l.center.y)
        let destination = try XCTUnwrap(WindowDropTarget.resolve(at: point)?.destination)
        XCTAssertEqual(destination, .newColumn(workspace: workspace, before: right))
        XCTAssertTrue(destination.apply(to: a))
        XCTAssertEqual(workspace.columns.count, 3)
        XCTAssertEqual(workspace.columns[1].children, [a])
    }

    func testDroppingBesideSoleWindowDoesNotRecreateItsColumn() {
        let workspace = currentSession.focus.workspace
        let column = workspace.addColumn(after: nil)
        let a = TestWindow.new(id: 1, parent: column)
        for before in [column, nil] {
            XCTAssertTrue(WindowDropDestination.newColumn(workspace: workspace, before: before).apply(to: a))
            XCTAssertEqual(workspace.columns, [column])
        }
    }

    func testEmptyWorkspaceAndOutsideDisplays() {
        let workspace = currentSession.focus.workspace
        XCTAssertEqual(target(500, 500), .newColumn(workspace: workspace, before: nil))
        XCTAssertNil(target(-100, -100))
        XCTAssertTrue(workspace.columns.isEmpty)
    }

    func testHysteresisDoesNotPreventEnteringColumnEdgeZone() async throws {
        let workspace = currentSession.focus.workspace
        let column = workspace.addColumn(after: nil)
        let window = TestWindow.new(id: 1, parent: column)
        try await workspace.layoutWorkspace()
        let rect = try XCTUnwrap(window.lastAppliedLayoutPhysicalRect)
        let previous = try XCTUnwrap(WindowDropTarget.resolve(at: CGPoint(x: rect.center.x, y: rect.minY + 20)))
        let next = WindowDropTarget.resolve(at: CGPoint(x: mainMonitor.visibleRect.minX + 1, y: rect.minY + 20), previous: previous)
        XCTAssertEqual(next?.destination, .newColumn(workspace: workspace, before: column))
    }

    func testStaleColumnCannotReceiveDrop() {
        let workspace = currentSession.focus.workspace
        let source = workspace.addColumn(after: nil)
        let target = workspace.addColumn(after: nil)
        let a = TestWindow.new(id: 1, parent: source)
        let destination = WindowDropDestination.insert(column: target, slot: 0)
        target.unbindFromParent()
        XCTAssertFalse(destination.apply(to: a))
        XCTAssertEqual(source.children, [a])
    }

    func testEntireConfiguredGapCreatesColumn() async throws {
        currentSession.config.gaps = .zero
        currentSession.config.gaps.inner.horizontal = .constant(80)
        let workspace = currentSession.focus.workspace
        let left = workspace.addColumn(after: nil)
        let right = workspace.addColumn(after: nil)
        _ = TestWindow.new(id: 1, parent: left)
        _ = TestWindow.new(id: 2, parent: right)
        try await workspace.layoutWorkspace()
        let l = try XCTUnwrap(left.lastAppliedLayoutPhysicalRect)
        let r = try XCTUnwrap(right.lastAppliedLayoutPhysicalRect)
        for x in [l.maxX + 1, (l.maxX + r.minX) / 2, r.minX - 1] {
            XCTAssertEqual(target(x, l.center.y), .newColumn(workspace: workspace, before: right))
        }
    }

    func testMidpointTargetRemainsStableUntilPointerLeavesDeadBand() async throws {
        let workspace = currentSession.focus.workspace
        let column = workspace.addColumn(after: nil)
        let window = TestWindow.new(id: 1, parent: column)
        try await workspace.layoutWorkspace()
        let rect = try XCTUnwrap(window.lastAppliedLayoutPhysicalRect)
        let upper = try XCTUnwrap(WindowDropTarget.resolve(at: CGPoint(x: rect.center.x, y: rect.center.y - 10)))
        XCTAssertEqual(WindowDropTarget.resolve(at: CGPoint(x: rect.center.x, y: rect.center.y + 2), previous: upper)?.destination,
                       .insert(column: column, slot: 0))
        XCTAssertEqual(WindowDropTarget.resolve(at: CGPoint(x: rect.center.x, y: rect.center.y + 6), previous: upper)?.destination,
                       .insert(column: column, slot: 1))
    }

    private func target(_ x: CGFloat, _ y: CGFloat) -> WindowDropDestination? {
        WindowDropTarget.resolve(at: CGPoint(x: x, y: y))?.destination
    }
}
