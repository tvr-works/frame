@testable import FrameEngine
import FrameTestSupport
import XCTest

@MainActor
final class WindowInsertionTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testReorderPreservesOtherWindowsAndWeight() {
        let column = Workspace.get(byName: "a").addColumn(after: nil)
        let a = TestWindow.new(id: 1, parent: column, adaptiveWeight: 80)
        let b = TestWindow.new(id: 2, parent: column)
        let c = TestWindow.new(id: 3, parent: column)

        XCTAssertTrue(a.insert(into: column, at: 3))
        XCTAssertEqual(column.children, [b, c, a])
        XCTAssertEqual(a.getWeight(.v), 80)
        XCTAssertTrue(a.insert(into: column, at: 0))
        XCTAssertEqual(column.children, [a, b, c])
    }

    func testBothSidesOfOriginalSlotAreNoops() {
        let column = Workspace.get(byName: "a").addColumn(after: nil)
        let a = TestWindow.new(id: 1, parent: column)
        let b = TestWindow.new(id: 2, parent: column)
        for slot in [1, 2] {
            XCTAssertTrue(b.insert(into: column, at: slot))
            XCTAssertEqual(column.children, [a, b])
        }
    }

    func testTransferInsertsWithoutDisplacingTargetAndUsesAutomaticWeight() {
        let source = Workspace.get(byName: "a").addColumn(after: nil)
        let destination = Workspace.get(byName: "b").addColumn(after: nil)
        let a = TestWindow.new(id: 1, parent: source, adaptiveWeight: 80)
        let b = TestWindow.new(id: 2, parent: destination, adaptiveWeight: 40)
        let c = TestWindow.new(id: 3, parent: destination, adaptiveWeight: 60)

        XCTAssertTrue(a.insert(into: destination, at: 1))
        XCTAssertEqual(destination.children, [b, a, c])
        XCTAssertTrue(source.children.isEmpty)
        XCTAssertEqual(a.getWeight(.v), 50)
    }

    func testInvalidSlotDoesNotUnbindWindow() {
        let column = Workspace.get(byName: "a").addColumn(after: nil)
        let a = TestWindow.new(id: 1, parent: column)
        XCTAssertFalse(a.insert(into: column, at: -1))
        XCTAssertFalse(a.insert(into: column, at: 2))
        XCTAssertEqual(column.children, [a])
    }
}
