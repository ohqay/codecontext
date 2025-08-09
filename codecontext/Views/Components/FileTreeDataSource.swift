import AppKit

/// Handles NSOutlineView data source responsibilities
final class FileTreeDataSource: NSObject, NSOutlineViewDataSource {
    weak var fileTreeModel: FileTreeModel?
    var filterText: String = ""

    init(fileTreeModel: FileTreeModel) {
        self.fileTreeModel = fileTreeModel
        super.init()
    }

    func outlineView(_: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return fileTreeModel?.rootNode != nil ? 1 : 0
        }
        guard let node = item as? FileNode else { return 0 }
        return filteredChildren(of: node).count
    }

    func outlineView(_: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return fileTreeModel!.rootNode!
        }
        guard let node = item as? FileNode else {
            return FileNode(url: URL(fileURLWithPath: "/"), isDirectory: false)
        }
        let children = filteredChildren(of: node)
        return children[index]
    }

    func outlineView(_: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? FileNode else { return false }
        return node.isDirectory && !filteredChildren(of: node).isEmpty
    }

    /// Filter children based on the current filter text
    private func filteredChildren(of node: FileNode) -> [FileNode] {
        let trimmedFilter = filterText.trimmed

        if trimmedFilter.isEmpty {
            return node.children
        }

        return node.children.filter {
            FileTreeUpdateStrategy.nodeMatchesFilter($0, filter: trimmedFilter)
        }
    }
}
