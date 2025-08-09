import AppKit
import Quartz
import QuickLook

/// Custom NSOutlineView that handles keyboard shortcuts for Quick Look
class QuickLookOutlineView: NSOutlineView {
    enum KeyCode {
        static let spacebar: UInt16 = 49
        static let escape: UInt16 = 53
    }

    var onSpacebarPressed: ((Any?) -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == KeyCode.spacebar,
           let selectedItem = item(atRow: selectedRow)
        {
            onSpacebarPressed?(selectedItem)
            return
        }
        super.keyDown(with: event)
    }
}

/// Handles all Quick Look preview functionality
final class QuickLookHandler: NSObject {
    private var currentPreviewFile: FileNode?

    func handleSpacebarPress(_ item: Any?) {
        guard let node = item as? FileNode, !node.isDirectory else { return }

        currentPreviewFile = node

        if QLPreviewPanel.sharedPreviewPanelExists(),
           QLPreviewPanel.shared()?.isVisible == true
        {
            QLPreviewPanel.shared()?.orderOut(nil)
        } else {
            let panel = QLPreviewPanel.shared()
            panel?.dataSource = self
            panel?.delegate = self
            panel?.makeKeyAndOrderFront(nil)
        }
    }
}

// MARK: - QLPreviewPanelDataSource

extension QuickLookHandler: QLPreviewPanelDataSource {
    func numberOfPreviewItems(in _: QLPreviewPanel) -> Int {
        currentPreviewFile != nil ? 1 : 0
    }

    func previewPanel(_: QLPreviewPanel, previewItemAt _: Int) -> QLPreviewItem {
        currentPreviewFile?.url as? QLPreviewItem ??
            URL(fileURLWithPath: "/") as QLPreviewItem
    }
}

// MARK: - QLPreviewPanelDelegate

extension QuickLookHandler: QLPreviewPanelDelegate {
    func previewPanel(_ panel: QLPreviewPanel, handle event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }

        if event.keyCode == QuickLookOutlineView.KeyCode.spacebar ||
            event.keyCode == QuickLookOutlineView.KeyCode.escape
        {
            panel.orderOut(nil)
            return true
        }
        return false
    }
}
