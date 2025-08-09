import AppKit
import Foundation

/// Manages update detection and application for FileTreeView
enum FileTreeUpdateStrategy {
    enum UpdateType {
        case fullReload
        case filterChange
        case selectionOnly
        case expansionOnly
        case none
    }

    struct State: Equatable {
        let rootId: UUID?
        let filterText: String
        let nodeCount: Int
        let selectedCount: Int
        let expandedCount: Int

        init(model: FileTreeModel, filterText: String) {
            let nodes = model.allNodes
            rootId = model.rootNode?.id
            self.filterText = filterText.trimmed
            nodeCount = nodes.count
            selectedCount = nodes.filter { $0.isSelected }.count
            expandedCount = nodes.filter { $0.isExpanded }.count
        }
    }

    static func determineUpdateType(current: State, previous: State?) -> UpdateType {
        guard let previous = previous else { return .fullReload }

        if current.rootId != previous.rootId || current.nodeCount != previous.nodeCount {
            return .fullReload
        }
        if current.filterText != previous.filterText {
            return .filterChange
        }
        if current.selectedCount != previous.selectedCount {
            return .selectionOnly
        }
        if current.expandedCount != previous.expandedCount {
            return .expansionOnly
        }
        return .none
    }

    /// Apply the appropriate update to the outline view
    static func applyUpdate(
        _ type: UpdateType,
        to outlineView: NSOutlineView,
        model: FileTreeModel,
        filterText: String,
        coordinator: FileTreeCoordinatorProtocol
    ) {
        switch type {
        case .fullReload, .filterChange:
            performDataReload(
                outlineView: outlineView,
                model: model,
                filterText: filterText,
                preserveExpansion: type == .filterChange,
                coordinator: coordinator
            )
            coordinator.refreshTokenCounts(in: outlineView)

        case .selectionOnly:
            coordinator.refreshSelectionStates(in: outlineView)

        case .expansionOnly:
            updateExpansionStates(in: outlineView, model: model)
            coordinator.refreshTokenCounts(in: outlineView)

        case .none:
            break
        }
    }

    private static func performDataReload(
        outlineView: NSOutlineView,
        model: FileTreeModel,
        filterText: String,
        preserveExpansion: Bool,
        coordinator: FileTreeCoordinatorProtocol
    ) {
        let scrollPosition = outlineView.enclosingScrollView?.documentVisibleRect.origin.y ?? 0
        let expandedItems = preserveExpansion ? coordinator.getExpandedItems(in: outlineView) : []

        outlineView.reloadData()

        if let root = model.rootNode {
            outlineView.expandItem(root)

            let trimmedFilter = filterText.trimmed
            if !trimmedFilter.isEmpty {
                expandMatchingItems(outlineView, node: root, filter: trimmedFilter)
            } else if preserveExpansion {
                expandedItems.forEach { outlineView.expandItem($0) }
            } else {
                restoreExpansionStates(outlineView: outlineView, model: model)
            }
        }

        if scrollPosition > 0 {
            DispatchQueue.main.async {
                outlineView.enclosingScrollView?.documentView?.scroll(NSPoint(x: 0, y: scrollPosition))
            }
        }
    }

    private static func restoreExpansionStates(outlineView: NSOutlineView, model: FileTreeModel) {
        model.allNodes.filter { $0.isExpanded }.forEach { outlineView.expandItem($0) }
    }

    private static func expandMatchingItems(_ outlineView: NSOutlineView, node: FileNode, filter: String) {
        for child in node.children where child.isDirectory {
            if nodeMatchesFilter(child, filter: filter) {
                outlineView.expandItem(child)
                expandMatchingItems(outlineView, node: child, filter: filter)
            }
        }
    }

    private static func updateExpansionStates(in outlineView: NSOutlineView, model: FileTreeModel) {
        model.allNodes.filter { $0.isDirectory }.forEach { node in
            let isExpanded = outlineView.isItemExpanded(node)
            if isExpanded != node.isExpanded {
                if node.isExpanded {
                    outlineView.expandItem(node)
                } else {
                    outlineView.collapseItem(node)
                }
            }
        }
    }

    /// Check if a node or its descendants match the filter
    static func nodeMatchesFilter(_ node: FileNode, filter: String) -> Bool {
        guard !filter.isEmpty else { return false }

        if node.name.localizedStandardContains(filter) ||
            node.url.path.localizedStandardContains(filter)
        {
            return true
        }

        return node.isDirectory && node.children.contains {
            nodeMatchesFilter($0, filter: filter)
        }
    }
}

/// Protocol for coordinator methods needed by update strategy
protocol FileTreeCoordinatorProtocol: AnyObject {
    func refreshTokenCounts(in outlineView: NSOutlineView)
    func refreshSelectionStates(in outlineView: NSOutlineView)
    func getExpandedItems(in outlineView: NSOutlineView) -> [FileNode]
}

// Helper extension for string trimming
extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
