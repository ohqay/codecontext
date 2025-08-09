import AppKit

/// Handles NSOutlineView delegate responsibilities
final class FileTreeDelegate: NSObject, NSOutlineViewDelegate {
    weak var fileTreeModel: FileTreeModel?
    let cellViewFactory = CellViewFactory()
    var onCheckboxToggled: ((FileNode) -> Void)?

    init(fileTreeModel: FileTreeModel) {
        self.fileTreeModel = fileTreeModel
        super.init()
    }

    func outlineView(
        _: NSOutlineView,
        viewFor tableColumn: NSTableColumn?,
        item: Any
    ) -> NSView? {
        guard let node = item as? FileNode,
              let columnId = tableColumn?.identifier.rawValue
        else {
            return nil
        }

        return cellViewFactory.createCellView(
            for: columnId,
            node: node,
            target: self,
            action: #selector(checkboxToggled(_:))
        )
    }

    @objc private func checkboxToggled(_ sender: NSButton) {
        guard let outlineView = sender.superview?.superview?.superview as? NSOutlineView else {
            return
        }

        outlineView.forEachVisibleNode { (_, node: FileNode) in
            if node.hashValue == sender.tag {
                onCheckboxToggled?(node)
                return true
            }
            return false
        }
    }

    func outlineView(_: NSOutlineView, shouldSelectItem _: Any) -> Bool {
        true
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard let node = notification.userInfo?["NSObject"] as? FileNode else { return }
        DispatchQueue.main.async {
            node.isExpanded = true
        }
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard let node = notification.userInfo?["NSObject"] as? FileNode else { return }
        DispatchQueue.main.async {
            node.isExpanded = false
        }
    }
}
