import AppKit
import FrameEngine

/// Owns a nonactivating, mouse-transparent panel, allocated only during a drag.
@MainActor
package final class WindowDropPreviewController {
    private var panel: NSPanelHud?

    package init() {}

    package func show(_ preview: WindowDropPreview?) {
        guard let preview, let primaryScreen = NSScreen.screens.first else {
            panel?.orderOut(nil)
            return
        }
        let panel: NSPanelHud
        if let existing = self.panel {
            panel = existing
        } else {
            panel = NSPanelHud()
            panel.ignoresMouseEvents = true
            panel.hasShadow = false
            panel.isOpaque = false
            panel.contentView = NSView()
            panel.contentView?.wantsLayer = true
            self.panel = panel
        }
        let rect = preview.rect
        let frame = CGRect(x: rect.minX, y: primaryScreen.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        let layer = panel.contentView?.layer
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(preview.isNewColumn ? 0.22 : 0.95).cgColor
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.borderWidth = preview.isNewColumn ? 2 : 0
        layer?.cornerRadius = preview.isNewColumn ? 6 : 2
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }
}
