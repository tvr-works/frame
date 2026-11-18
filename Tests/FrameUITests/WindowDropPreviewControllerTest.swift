@testable import FrameEngine
@testable import FrameUI
import AppKit
import XCTest

@MainActor
final class WindowDropPreviewControllerTest: XCTestCase {
    func testPreviewDoesNotTakeFocusOrInterceptMouseAndClearsOnCancel() throws {
        let screen = try availableScreen()
        let app = NSApplication.shared
        let windowsBefore = Set(app.windows.map(ObjectIdentifier.init))
        let keyWindowBefore = app.keyWindow
        let controller = WindowDropPreviewController()
        defer { controller.show(nil) }
        let rect = Rect(topLeftX: screen.frame.minX + 100, topLeftY: 100, width: 300, height: 4)

        controller.show(WindowDropPreview(rect: rect, isNewColumn: false))

        let panel = try XCTUnwrap(app.windows.first { !windowsBefore.contains(ObjectIdentifier($0)) } as? NSPanel)
        defer { panel.close() }
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(app.keyWindow === keyWindowBefore)
        XCTAssertEqual(panel.frame.size, CGSize(width: 300, height: 4))
        XCTAssertEqual(panel.contentView?.bounds.size, panel.frame.size)
        XCTAssertFalse(panel.isOpaque)

        controller.show(nil)
        XCTAssertFalse(panel.isVisible)
        XCTAssertTrue(app.keyWindow === keyWindowBefore)
    }

    func testPreviewFollowsDesktopCoordinatesAcrossScreensWithoutCreatingMorePanels() throws {
        let primary = try availableScreen()
        let app = NSApplication.shared
        let windowsBefore = Set(app.windows.map(ObjectIdentifier.init))
        let controller = WindowDropPreviewController()
        defer { controller.show(nil) }
        var previewPanel: NSWindow?

        for screen in NSScreen.screens {
            let expected = CGRect(x: screen.frame.minX + 100, y: screen.frame.minY + 100, width: 24, height: 300)
            let rect = Rect(topLeftX: expected.minX, topLeftY: primary.frame.maxY - expected.maxY,
                            width: expected.width, height: expected.height)
            controller.show(WindowDropPreview(rect: rect, isNewColumn: true))
            let panels = app.windows.filter { !windowsBefore.contains(ObjectIdentifier($0)) }
            XCTAssertEqual(panels.count, 1)
            let panel = try XCTUnwrap(panels.first)
            XCTAssertEqual(panel.frame, expected)
            XCTAssertEqual(panel.contentView?.bounds.size, expected.size)
            if let previewPanel { XCTAssertTrue(previewPanel === panel) }
            previewPanel = panel
        }
        previewPanel?.close()
    }

    private func availableScreen() throws -> NSScreen {
        guard let screen = NSScreen.screens.first else { throw XCTSkip("A WindowServer display is required for native preview tests") }
        return screen
    }
}
