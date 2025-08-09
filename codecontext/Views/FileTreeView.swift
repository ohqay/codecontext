import SwiftUI
import AppKit
import QuickLook
import Quartz

// Custom NSOutlineView that handles keyboard shortcuts for Quick Look
class QuickLookOutlineView: NSOutlineView {
    var onSpacebarPressed: ((Any?) -> Void)?
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 { // Spacebar keycode
            if let selectedItem = item(atRow: selectedRow) {
                onSpacebarPressed?(selectedItem)
                return
            }
        }
        super.keyDown(with: event)
    }
}

// NSOutlineView-based file tree for performance with large directories
struct FileTreeView: NSViewRepresentable {
    @Binding var fileTreeModel: FileTreeModel
    @Binding var filterText: String
    let onSelectionChange: (FileNode) -> Void
    
    // Internal state tracking for selective updates
    struct StateSnapshot: Equatable {
        let rootNodeId: UUID?
        let filterText: String
        let allNodeIds: Set<UUID>
        let selectedNodeIds: Set<UUID>
        let expandedNodeIds: Set<UUID>
        
        static func from(fileTreeModel: FileTreeModel, filterText: String) -> StateSnapshot {
            let allNodes = fileTreeModel.allNodes
            return StateSnapshot(
                rootNodeId: fileTreeModel.rootNode?.id,
                filterText: filterText.trimmingCharacters(in: .whitespacesAndNewlines),
                allNodeIds: Set(allNodes.map { $0.id }),
                selectedNodeIds: Set(allNodes.filter { $0.isSelected }.map { $0.id }),
                expandedNodeIds: Set(allNodes.filter { $0.isExpanded }.map { $0.id })
            )
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let outlineView = QuickLookOutlineView()
        
        outlineView.delegate = context.coordinator
        outlineView.dataSource = context.coordinator
        outlineView.headerView = nil
        outlineView.rowSizeStyle = .medium
        outlineView.autoresizesOutlineColumn = false
        outlineView.indentationPerLevel = 24
        outlineView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        
        // Create columns - reordered: name, tokens, checkbox
        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = "File"
        nameColumn.width = 200
        nameColumn.minWidth = 100
        outlineView.addTableColumn(nameColumn)
        outlineView.outlineTableColumn = nameColumn
        
        let tokenColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("tokens"))
        tokenColumn.title = "Tokens"
        tokenColumn.width = 80
        tokenColumn.minWidth = 60
        tokenColumn.maxWidth = 120
        outlineView.addTableColumn(tokenColumn)
        
        let checkColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("checkbox"))
        checkColumn.title = ""
        checkColumn.width = 30
        checkColumn.minWidth = 30
        checkColumn.maxWidth = 30
        outlineView.addTableColumn(checkColumn)
        
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        
        // Set up spacebar handler
        outlineView.onSpacebarPressed = context.coordinator.handleSpacebarPress
        
        context.coordinator.outlineView = outlineView
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let outlineView = nsView.documentView as? NSOutlineView else { return }
        
        let coordinator = context.coordinator
        coordinator.parent = self
        
        // Create snapshots to detect what changed
        let currentSnapshot = StateSnapshot.from(fileTreeModel: fileTreeModel, filterText: filterText)
        let previousSnapshot = coordinator.lastSnapshot
        
        // Store current snapshot for next update
        coordinator.lastSnapshot = currentSnapshot
        
        // Determine what type of update is needed
        let updateType = determineUpdateType(current: currentSnapshot, previous: previousSnapshot)
        
        switch updateType {
        case .fullReload:
            performFullReload(outlineView: outlineView, coordinator: coordinator)
            // After a full reload, ensure token labels reflect latest counts
            coordinator.refreshTokenCounts(in: outlineView)
        case .filterChange:
            performFilterUpdate(outlineView: outlineView, coordinator: coordinator)
            coordinator.refreshTokenCounts(in: outlineView)
        case .selectionOnly:
            performSelectionUpdate(outlineView: outlineView, coordinator: coordinator)
        case .expansionOnly:
            performExpansionUpdate(outlineView: outlineView, coordinator: coordinator)
            coordinator.refreshTokenCounts(in: outlineView)
        case .none:
            break // No update needed
        }
    }
    
    private enum UpdateType {
        case fullReload
        case filterChange
        case selectionOnly
        case expansionOnly
        case none
    }
    
    private func determineUpdateType(current: StateSnapshot, previous: StateSnapshot?) -> UpdateType {
        guard let previous = previous else {
            return .fullReload // First time setup
        }
        
        // If root changed or nodes were added/removed, full reload needed
        if current.rootNodeId != previous.rootNodeId ||
           current.allNodeIds != previous.allNodeIds {
            return .fullReload
        }
        
        // If filter changed, need to refresh visible items and expansion
        if current.filterText != previous.filterText {
            return .filterChange
        }
        
        // If only selections changed, update checkboxes
        if current.selectedNodeIds != previous.selectedNodeIds {
            return .selectionOnly
        }
        
        // If only expansions changed, update expansion states
        if current.expandedNodeIds != previous.expandedNodeIds {
            return .expansionOnly
        }
        
        return .none
    }
    
    private func performFullReload(outlineView: NSOutlineView, coordinator: Coordinator) {
        // Preserve scroll position during reload
        let scrollPosition = (outlineView.enclosingScrollView?.documentVisibleRect.origin.y) ?? 0
        
        outlineView.reloadData()
        
        // Expand root and apply filtering
        if let root = fileTreeModel.rootNode {
            outlineView.expandItem(root)
            
            if !filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                expandMatchingItems(outlineView, node: root)
            } else {
                // Restore previous expansion states
                restoreExpansionStates(outlineView: outlineView, coordinator: coordinator)
            }
        }
        
        // Restore scroll position
        if scrollPosition > 0 {
            DispatchQueue.main.async {
                outlineView.enclosingScrollView?.documentView?.scroll(NSPoint(x: 0, y: scrollPosition))
            }
        }
    }
    
    private func performFilterUpdate(outlineView: NSOutlineView, coordinator: Coordinator) {
        // Save expanded items before filter change
        let expandedItems = coordinator.getExpandedItems(in: outlineView)
        
        outlineView.reloadData()
        
        if let root = fileTreeModel.rootNode {
            outlineView.expandItem(root)
            
            if !filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                expandMatchingItems(outlineView, node: root)
            } else {
                // Restore previous expansion states when clearing filter
                restoreExpandedItems(outlineView: outlineView, expandedItems: expandedItems)
            }
        }
    }
    
    private func performSelectionUpdate(outlineView: NSOutlineView, coordinator: Coordinator) {
        // Update only the checkbox views for changed selections
        coordinator.refreshSelectionStates(in: outlineView)
    }
    
    private func performExpansionUpdate(outlineView: NSOutlineView, coordinator: Coordinator) {
        // Update expansion states without full reload
        coordinator.updateExpansionStates(in: outlineView)
    }
    
    private func restoreExpansionStates(outlineView: NSOutlineView, coordinator: Coordinator) {
        guard let lastSnapshot = coordinator.lastSnapshot else { return }
        
        // Find nodes to expand based on their IDs
        for nodeId in lastSnapshot.expandedNodeIds {
            if let node = fileTreeModel.allNodes.first(where: { $0.id == nodeId }) {
                outlineView.expandItem(node)
            }
        }
    }
    
    private func restoreExpandedItems(outlineView: NSOutlineView, expandedItems: [FileNode]) {
        for item in expandedItems {
            outlineView.expandItem(item)
        }
    }
    
    /// Recursively expand directories that contain filtered items
    private func expandMatchingItems(_ outlineView: NSOutlineView, node: FileNode) {
        for child in node.children {
            if child.isDirectory {
                let hasMatching = hasMatchingDescendant(child, filter: filterText.trimmingCharacters(in: .whitespacesAndNewlines))
                if hasMatching {
                    outlineView.expandItem(child)
                    expandMatchingItems(outlineView, node: child)
                }
            }
        }
    }
    
    /// Helper method to check if a directory has matching descendants (shared logic)
    private func hasMatchingDescendant(_ node: FileNode, filter: String) -> Bool {
        if filter.isEmpty { return false }
        
        // Check if the directory name itself matches
        if node.name.localizedStandardContains(filter) ||
           node.url.path.localizedStandardContains(filter) {
            return true
        }
        
        // Check all children recursively
        for child in node.children {
            if child.isDirectory {
                if hasMatchingDescendant(child, filter: filter) {
                    return true
                }
            } else {
                if child.name.localizedStandardContains(filter) ||
                   child.url.path.localizedStandardContains(filter) {
                    return true
                }
            }
        }
        
        return false
    }
    
    class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
        var parent: FileTreeView
        weak var outlineView: NSOutlineView?
        private var currentPreviewFile: FileNode?
        var lastSnapshot: StateSnapshot?
        private var isUpdatingProgrammatically = false
        
        init(_ parent: FileTreeView) {
            self.parent = parent
            super.init()
            setupNotificationObservers()
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
        
        private func setupNotificationObservers() {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleOutlineViewRefresh),
                name: .outlineViewNeedsRefresh,
                object: nil
            )
        }
        
        @objc private func handleOutlineViewRefresh() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let outlineView = self.outlineView else { return }
                
                // Ensure aggregate token counts are up to date
                self.parent.fileTreeModel.rootNode?.updateAggregateTokens()
                
                // Update token labels for visible rows and keep selections in sync
                self.refreshTokenCounts(in: outlineView)
                self.refreshSelectionStates(in: outlineView)
            }
        }
        
        func handleSpacebarPress(_ item: Any?) {
            guard let node = item as? FileNode, !node.isDirectory else { return }
            
            currentPreviewFile = node
            
            if QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared()?.isVisible == true {
                QLPreviewPanel.shared()?.orderOut(nil)
            } else {
                let panel = QLPreviewPanel.shared()
                panel?.dataSource = self
                panel?.delegate = self
                panel?.makeKeyAndOrderFront(nil)
            }
        }
        
        // MARK: - DataSource
        
        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            if item == nil {
                return parent.fileTreeModel.rootNode != nil ? 1 : 0
            }
            guard let node = item as? FileNode else { return 0 }
            return filteredChildren(of: node).count
        }
        
        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            if item == nil {
                return parent.fileTreeModel.rootNode!
            }
            guard let node = item as? FileNode else { return FileNode(url: URL(fileURLWithPath: "/"), isDirectory: false) }
            let children = filteredChildren(of: node)
            return children[index]
        }
        
        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let node = item as? FileNode else { return false }
            return node.isDirectory && !filteredChildren(of: node).isEmpty
        }
        
        /// Filter children based on the current filter text
        private func filteredChildren(of node: FileNode) -> [FileNode] {
            let filterText = parent.filterText.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // If no filter text, return all children
            if filterText.isEmpty {
                return node.children
            }
            
            return node.children.filter { child in
                // For directories, include if any descendant matches the filter
                if child.isDirectory {
                    return hasMatchingDescendant(child, filter: filterText)
                } else {
                    // For files, match against filename or path
                    return child.name.localizedStandardContains(filterText) ||
                           child.url.path.localizedStandardContains(filterText)
                }
            }
        }
        
        /// Recursively check if a directory has any descendant that matches the filter
        private func hasMatchingDescendant(_ node: FileNode, filter: String) -> Bool {
            return parent.hasMatchingDescendant(node, filter: filter)
        }
        
        // MARK: - Delegate
        
        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let node = item as? FileNode else { return nil }
            guard let columnId = tableColumn?.identifier.rawValue else { return nil }
            
            switch columnId {
            case "checkbox":
                return makeCheckboxView(for: node)
            case "name":
                return makeNameView(for: node)
            case "tokens":
                return makeTokenView(for: node)
            default:
                return nil
            }
        }
        
        private func makeCheckboxView(for node: FileNode) -> NSView {
            let container = NSView()
            let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(checkboxToggled(_:)))
            checkbox.state = node.isSelected ? .on : .off
            checkbox.tag = node.hashValue
            checkbox.translatesAutoresizingMaskIntoConstraints = false
            
            container.addSubview(checkbox)
            NSLayoutConstraint.activate([
                checkbox.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                checkbox.centerYAnchor.constraint(equalTo: container.centerYAnchor)
            ])
            
            return container
        }
        
        private func makeNameView(for node: FileNode) -> NSView {
            let container = NSView()
            
            let imageView = NSImageView()
            imageView.image = node.isDirectory ?
                NSImage(systemSymbolName: "folder", accessibilityDescription: "Folder") :
                NSImage(systemSymbolName: "doc", accessibilityDescription: "File")
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            
            let textField = NSTextField(labelWithString: node.name)
            textField.font = .systemFont(ofSize: 13)
            textField.lineBreakMode = .byTruncatingTail
            textField.translatesAutoresizingMaskIntoConstraints = false
            
            container.addSubview(imageView)
            container.addSubview(textField)
            
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
                imageView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 20),
                imageView.heightAnchor.constraint(equalToConstant: 20),
                
                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: container.centerYAnchor)
            ])
            
            return container
        }
        
        private func makeTokenView(for node: FileNode) -> NSView {
            let container = NSView()
            
            // Always use aggregateTokenCount which includes the sum for directories
            let tokenCount = node.aggregateTokenCount
            let formattedString = formatTokenCount(tokenCount)
            
            let textField = NSTextField(labelWithString: formattedString)
            textField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            textField.alignment = .right
            textField.textColor = .secondaryLabelColor
            textField.translatesAutoresizingMaskIntoConstraints = false
            
            container.addSubview(textField)
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: container.centerYAnchor)
            ])
            
            return container
        }
        
        private func formatTokenCount(_ count: Int) -> String {
            if count == 0 { return "" }
            // Always use "k" notation for consistency
            let thousands = Double(count) / 1000.0
            if thousands < 1.0 {
                // For values less than 1000, show with 2 decimal places
                return String(format: "%.2fk", thousands)
            } else if thousands < 10.0 {
                // For 1k-10k, show with 1 decimal place
                return String(format: "%.1fk", thousands)
            } else if thousands < 1000.0 {
                // For 10k-999k, show as integer
                return String(format: "%.0fk", thousands)
            } else {
                // For 1M+, switch to M notation
                return String(format: "%.1fM", Double(count) / 1000000)
            }
        }
        
        @objc private func checkboxToggled(_ sender: NSButton) {
            // Prevent UI update loops during programmatic changes
            guard !isUpdatingProgrammatically else { return }
            
            // Find the node by iterating through visible items
            for row in 0..<outlineView!.numberOfRows {
                if let node = outlineView!.item(atRow: row) as? FileNode,
                   node.hashValue == sender.tag {
                    parent.onSelectionChange(node)
                    // Use selective update instead of full reload
                    refreshSelectionStatesForNode(node, in: outlineView!)
                    break
                }
            }
        }
        
        // MARK: - Selective Update Methods
        
        /// Refresh selection states for all visible checkboxes without full reload
        func refreshSelectionStates(in outlineView: NSOutlineView) {
            isUpdatingProgrammatically = true
            defer { isUpdatingProgrammatically = false }
            
            for row in 0..<outlineView.numberOfRows {
                if let node = outlineView.item(atRow: row) as? FileNode {
                    refreshSelectionStatesForNode(node, in: outlineView, row: row)
                }
            }
        }
        
        /// Refresh token labels for all visible rows (tokens column index = 1)
        func refreshTokenCounts(in outlineView: NSOutlineView) {
            for row in 0..<outlineView.numberOfRows {
                guard let node = outlineView.item(atRow: row) as? FileNode else { continue }
                
                if let tokenView = outlineView.view(atColumn: 1, row: row, makeIfNecessary: false),
                   let label = tokenView.subviews.first as? NSTextField {
                    let display = formatTokenCount(node.aggregateTokenCount)
                    if label.stringValue != display {
                        label.stringValue = display
                    }
                }
            }
        }
        
        /// Refresh selection state for a specific node and its children
        private func refreshSelectionStatesForNode(_ node: FileNode, in outlineView: NSOutlineView, row: Int? = nil) {
            let nodeRow = row ?? outlineView.row(forItem: node)
            guard nodeRow >= 0 else { return }
            
            // Update the checkbox in the last column (column 2 after reordering)
            if let checkboxView = outlineView.view(atColumn: 2, row: nodeRow, makeIfNecessary: false),
               let checkbox = checkboxView.subviews.first as? NSButton {
                let newState: NSControl.StateValue = node.isSelected ? .on : .off
                if checkbox.state != newState {
                    checkbox.state = newState
                }
            }
            
            // If this is a directory and it's expanded, update its children
            if node.isDirectory && outlineView.isItemExpanded(node) {
                for child in node.children {
                    let childRow = outlineView.row(forItem: child)
                    if childRow >= 0 {
                        refreshSelectionStatesForNode(child, in: outlineView, row: childRow)
                    }
                }
            }
        }
        
        /// Update expansion states without full reload
        func updateExpansionStates(in outlineView: NSOutlineView) {
            guard lastSnapshot != nil else { return }
            
            // Get current expansion states from model
            let shouldBeExpanded = Set(parent.fileTreeModel.allNodes.filter { $0.isExpanded }.map { $0.id })
            
            // Compare with what should be expanded and update accordingly
            for node in parent.fileTreeModel.allNodes.filter({ $0.isDirectory }) {
                let isCurrentlyExpanded = outlineView.isItemExpanded(node)
                let shouldExpand = shouldBeExpanded.contains(node.id)
                
                if isCurrentlyExpanded != shouldExpand {
                    if shouldExpand {
                        outlineView.expandItem(node)
                    } else {
                        outlineView.collapseItem(node)
                    }
                }
            }
        }
        
        /// Get list of currently expanded items
        func getExpandedItems(in outlineView: NSOutlineView) -> [FileNode] {
            var expandedItems: [FileNode] = []
            
            func collectExpanded(node: FileNode) {
                if outlineView.isItemExpanded(node) {
                    expandedItems.append(node)
                }
                for child in node.children {
                    if child.isDirectory {
                        collectExpanded(node: child)
                    }
                }
            }
            
            if let root = parent.fileTreeModel.rootNode {
                collectExpanded(node: root)
            }
            
            return expandedItems
        }
        
        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
            return true
        }
        
        func outlineViewItemDidExpand(_ notification: Notification) {
            guard let node = notification.userInfo?["NSObject"] as? FileNode else { return }
            // Use async update to prevent synchronization issues
            DispatchQueue.main.async {
                node.isExpanded = true
            }
        }
        
        func outlineViewItemDidCollapse(_ notification: Notification) {
            guard let node = notification.userInfo?["NSObject"] as? FileNode else { return }
            // Use async update to prevent synchronization issues
            DispatchQueue.main.async {
                node.isExpanded = false
            }
        }
        
        // MARK: - QLPreviewPanelDataSource
        
        func numberOfPreviewItems(in panel: QLPreviewPanel) -> Int {
            return currentPreviewFile != nil ? 1 : 0
        }
        
        func previewPanel(_ panel: QLPreviewPanel, previewItemAt index: Int) -> QLPreviewItem {
            return currentPreviewFile?.url as? QLPreviewItem ?? URL(fileURLWithPath: "/") as QLPreviewItem
        }
        
        // MARK: - QLPreviewPanelDelegate
        
        func previewPanel(_ panel: QLPreviewPanel, handle event: NSEvent) -> Bool {
            if event.type == .keyDown && event.keyCode == 49 { // Spacebar
                panel.orderOut(nil)
                return true
            }
            if event.type == .keyDown && event.keyCode == 53 { // Escape
                panel.orderOut(nil)
                return true
            }
            return false
        }
    }
}

// SwiftUI wrapper for the file tree
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
            Task {
                await loadWorkspace()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .requestRefresh)) { _ in
            Task {
                await refreshWorkspace()
            }
        }
    }
    
    private func loadWorkspace() async {
        guard let url = resolveURL(from: workspace) else { return }
        
        let ignoreRules = IgnoreRules(
            respectGitIgnore: workspace.respectGitIgnore,
            respectDotIgnore: workspace.respectDotIgnore,
            showHiddenFiles: workspace.showHiddenFiles,
            excludeNodeModules: workspace.excludeNodeModules,
            excludeGit: workspace.excludeGit,
            excludeBuild: workspace.excludeBuild,
            excludeDist: workspace.excludeDist,
            excludeNext: workspace.excludeNext,
            excludeVenv: workspace.excludeVenv,
            excludeDSStore: workspace.excludeDSStore,
            excludeDerivedData: workspace.excludeDerivedData,
            customPatterns: workspace.customIgnore.split(separator: "\n").map(String.init),
            rootPath: url.path
        )
        
        // Clear previous selections when loading a new directory
        workspace.selectionJSON = "{}"
        
        await fileTreeModel.loadDirectory(at: url, ignoreRules: ignoreRules)
        
        // Initialize token count to 0 when loading
        selectedTokenCount = 0
        
        // Set up file system change notification
        fileTreeModel.onFileSystemChange = {
            Task { @MainActor in
                // Post notification to trigger workspace detail view refresh
                NotificationCenter.default.post(name: .fileSystemChanged, object: nil)
                
                // Update workspace selection state in case files were added/removed
                updateWorkspaceSelection()
            }
        }
        
        // Don't restore selections on fresh load - start with clean slate
        // User can explicitly restore if needed
    }
    
    private func resolveURL(from workspace: SDWorkspace) -> URL? {
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: workspace.bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
            _ = url.startAccessingSecurityScopedResource()
            return url
        } catch {
            return nil
        }
    }
    
    private func handleSelectionChange(_ node: FileNode) {
        // Use async update to prevent race conditions with UI updates
        Task { @MainActor in
            fileTreeModel.updateSelection(node)
            // Update workspace selection state
            updateWorkspaceSelection()
            // Update token count for real-time display
            selectedTokenCount = fileTreeModel.totalSelectedTokens
        }
    }
    
    
    private func refreshWorkspace() async {
        guard let url = resolveURL(from: workspace) else { return }
        
        let ignoreRules = IgnoreRules(
            respectGitIgnore: workspace.respectGitIgnore,
            respectDotIgnore: workspace.respectDotIgnore,
            showHiddenFiles: workspace.showHiddenFiles,
            excludeNodeModules: workspace.excludeNodeModules,
            excludeGit: workspace.excludeGit,
            excludeBuild: workspace.excludeBuild,
            excludeDist: workspace.excludeDist,
            excludeNext: workspace.excludeNext,
            excludeVenv: workspace.excludeVenv,
            excludeDSStore: workspace.excludeDSStore,
            excludeDerivedData: workspace.excludeDerivedData,
            customPatterns: workspace.customIgnore.split(separator: "\n").map(String.init),
            rootPath: url.path
        )
        
        await fileTreeModel.refresh(ignoreRules: ignoreRules)
        
        // Re-establish file system change callback after refresh
        fileTreeModel.onFileSystemChange = {
            Task { @MainActor in
                NotificationCenter.default.post(name: .fileSystemChanged, object: nil)
                updateWorkspaceSelection()
            }
        }
        
        // Update workspace selection state after refresh
        await MainActor.run {
            updateWorkspaceSelection()
            // Update token count after refresh
            selectedTokenCount = fileTreeModel.totalSelectedTokens
        }
    }
    
    private func updateWorkspaceSelection() {
        let selectedFiles = fileTreeModel.rootNode?.getSelectedFiles() ?? []
        let selectedPaths = Set(selectedFiles.map { $0.url.path })
        
        // Convert to JSON for storage
        if let data = try? JSONEncoder().encode(selectedPaths),
           let json = String(data: data, encoding: .utf8) {
            // Only update if actually changed
            if workspace.selectionJSON != json {
                workspace.selectionJSON = json
            }
        }
    }
    
}
