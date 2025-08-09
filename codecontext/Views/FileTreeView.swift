import AppKit
import SwiftUI

// MARK: - FileTreeView

/// NSOutlineView-based file tree for performance with large directories
struct FileTreeView: NSViewRepresentable {
    @Binding var fileTreeModel: FileTreeModel
    @Binding var filterText: String
    let onSelectionChange: (FileNode) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let outlineView = QuickLookOutlineView()

        // Configure outline view
        outlineView.configureStandardSettings()
        configureColumns(for: outlineView)

        // Set up coordinator
        context.coordinator.setupOutlineView(outlineView)

        // Configure scroll view
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollView.automaticallyAdjustsContentInsets = false

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let outlineView = nsView.documentView as? NSOutlineView else { return }

        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.dataSource.fileTreeModel = fileTreeModel
        coordinator.dataSource.filterText = filterText
        coordinator.delegate.fileTreeModel = fileTreeModel

        // Detect and apply updates
        let currentState = FileTreeUpdateStrategy.State(
            model: fileTreeModel,
            filterText: filterText
        )
        let updateType = FileTreeUpdateStrategy.determineUpdateType(
            current: currentState,
            previous: coordinator.lastState
        )
        coordinator.lastState = currentState

        FileTreeUpdateStrategy.applyUpdate(
            updateType,
            to: outlineView,
            model: fileTreeModel,
            filterText: filterText,
            coordinator: coordinator
        )
    }

    private func configureColumns(for outlineView: NSOutlineView) {
        struct ColumnConfig {
            let id: String
            let title: String
            let width: CGFloat
            let min: CGFloat?
            let max: CGFloat?
            let isOutline: Bool
        }

        let columns = [
            ColumnConfig(id: "name", title: "File", width: 200, min: 100, max: nil, isOutline: true),
            ColumnConfig(id: "tokens", title: "Tokens", width: 65, min: 55, max: 75, isOutline: false),
            ColumnConfig(id: "checkbox", title: "", width: 24, min: 24, max: 24, isOutline: false),
        ]

        for config in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(config.id))
            column.title = config.title
            column.width = config.width
            if let min = config.min { column.minWidth = min }
            if let max = config.max { column.maxWidth = max }
            outlineView.addTableColumn(column)
            if config.isOutline { outlineView.outlineTableColumn = column }
        }
    }
}

// MARK: - Coordinator

extension FileTreeView {
    class Coordinator: NSObject, FileTreeCoordinatorProtocol {
        var parent: FileTreeView
        weak var outlineView: NSOutlineView?

        let dataSource: FileTreeDataSource
        let delegate: FileTreeDelegate
        let quickLookHandler = QuickLookHandler()

        var lastState: FileTreeUpdateStrategy.State?
        private var isUpdatingProgrammatically = false

        init(_ parent: FileTreeView) {
            self.parent = parent
            dataSource = FileTreeDataSource(fileTreeModel: parent.fileTreeModel)
            delegate = FileTreeDelegate(fileTreeModel: parent.fileTreeModel)
            super.init()

            setupNotifications()
            setupDelegateCallbacks()
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func setupOutlineView(_ outlineView: QuickLookOutlineView) {
            self.outlineView = outlineView
            outlineView.dataSource = dataSource
            outlineView.delegate = delegate
            outlineView.onSpacebarPressed = quickLookHandler.handleSpacebarPress
        }

        private func setupNotifications() {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleOutlineViewRefresh),
                name: .outlineViewNeedsRefresh,
                object: nil
            )
        }

        private func setupDelegateCallbacks() {
            delegate.onCheckboxToggled = { [weak self] node in
                guard let self = self, !self.isUpdatingProgrammatically else { return }
                self.parent.onSelectionChange(node)
                self.refreshSelectionStatesForNode(node)
            }
        }

        @objc private func handleOutlineViewRefresh() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let outlineView = self.outlineView else { return }
                self.parent.fileTreeModel.rootNode?.updateAggregateTokens()
                self.refreshTokenCounts(in: outlineView)
                self.refreshSelectionStates(in: outlineView)
            }
        }

        // MARK: - FileTreeCoordinatorProtocol

        func refreshSelectionStates(in outlineView: NSOutlineView) {
            isUpdatingProgrammatically = true
            defer { isUpdatingProgrammatically = false }

            outlineView.forEachVisibleNode { (row, node: FileNode) in
                refreshSelectionStatesForNode(node, row: row)
                return false
            }
        }

        func refreshTokenCounts(in outlineView: NSOutlineView) {
            outlineView.forEachVisibleNode { (row, node: FileNode) in
                guard let tokenView = outlineView.view(atColumn: 1, row: row, makeIfNecessary: false),
                      let label = tokenView.subviews.first as? NSTextField
                else {
                    return false
                }

                let display = AppConfiguration.formatTokenCount(node.aggregateTokenCount)
                if label.stringValue != display {
                    label.stringValue = display
                }
                return false
            }
        }

        func getExpandedItems(in outlineView: NSOutlineView) -> [FileNode] {
            func collectExpanded(from node: FileNode) -> [FileNode] {
                var items: [FileNode] = []
                if outlineView.isItemExpanded(node) { items.append(node) }
                items.append(contentsOf: node.children
                    .filter { $0.isDirectory }
                    .flatMap { collectExpanded(from: $0) })
                return items
            }

            return parent.fileTreeModel.rootNode.map { collectExpanded(from: $0) } ?? []
        }

        private func refreshSelectionStatesForNode(_ node: FileNode, row: Int? = nil) {
            guard let outlineView = outlineView else { return }
            let nodeRow = row ?? outlineView.row(forItem: node)
            guard nodeRow >= 0 else { return }

            if let checkboxView = outlineView.view(atColumn: 2, row: nodeRow, makeIfNecessary: false),
               let checkbox = checkboxView.subviews.first as? NSButton
            {
                let newState: NSControl.StateValue = node.isSelected ? .on : .off
                if checkbox.state != newState {
                    checkbox.state = newState
                }
            }

            if node.isDirectory && outlineView.isItemExpanded(node) {
                for child in node.children {
                    refreshSelectionStatesForNode(child)
                }
            }
        }
    }
}

// MARK: - FileTreeContainer

/// SwiftUI wrapper for the file tree
struct FileTreeContainer: View {
    @State private var fileTreeModel = FileTreeModel()
    @Binding var workspace: SDWorkspace
    @Binding var filterText: String
    @Binding var selectedTokenCount: Int

    var body: some View {
        FileTreeView(
            fileTreeModel: $fileTreeModel,
            filterText: $filterText,
            onSelectionChange: handleSelectionChange
        )
        .task {
            await loadWorkspace()
        }
        .onChange(of: workspace) { _, _ in
            Task { await loadWorkspace() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .requestRefresh)) { _ in
            Task { await refreshWorkspace() }
        }
    }

    private func loadWorkspace() async {
        print("FileTreeContainer: Loading workspace \(workspace.name)")
        selectedTokenCount = await WorkspaceLoader.performOperation(
            workspace: workspace,
            fileTreeModel: fileTreeModel,
            isRefresh: false
        )
        setupFileSystemCallback()
        print("FileTreeContainer: Workspace loaded with \(fileTreeModel.allNodes.count) nodes")
    }

    private func refreshWorkspace() async {
        selectedTokenCount = await WorkspaceLoader.performOperation(
            workspace: workspace,
            fileTreeModel: fileTreeModel,
            isRefresh: true
        )
        await MainActor.run {
            WorkspaceLoader.updateSelection(workspace: workspace, fileTreeModel: fileTreeModel)
        }
    }

    private func handleSelectionChange(_ node: FileNode) {
        Task { @MainActor in
            fileTreeModel.updateSelection(node)
            WorkspaceLoader.updateSelection(workspace: workspace, fileTreeModel: fileTreeModel)
            selectedTokenCount = fileTreeModel.totalSelectedTokens
        }
    }

    private func setupFileSystemCallback() {
        fileTreeModel.onFileSystemChange = {
            Task { @MainActor in
                NotificationCenter.default.post(name: .fileSystemChanged, object: nil)
                WorkspaceLoader.updateSelection(workspace: workspace, fileTreeModel: fileTreeModel)
            }
        }
    }
}
