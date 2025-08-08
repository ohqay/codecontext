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
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let outlineView = QuickLookOutlineView()
        
        outlineView.delegate = context.coordinator
        outlineView.dataSource = context.coordinator
        outlineView.headerView = nil
        outlineView.rowSizeStyle = .default
        outlineView.autoresizesOutlineColumn = false
        outlineView.indentationPerLevel = 16
        outlineView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        
        // Create columns
        let checkColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("checkbox"))
        checkColumn.title = ""
        checkColumn.width = 30
        checkColumn.minWidth = 30
        checkColumn.maxWidth = 30
        outlineView.addTableColumn(checkColumn)
        
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
        
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        
        // Set up spacebar handler
        outlineView.onSpacebarPressed = context.coordinator.handleSpacebarPress
        
        context.coordinator.outlineView = outlineView
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let outlineView = nsView.documentView as? NSOutlineView else { return }
        
        context.coordinator.parent = self
        outlineView.reloadData()
        
        // Expand root by default and auto-expand when filtering
        if let root = fileTreeModel.rootNode {
            outlineView.expandItem(root)
            
            // If we have a filter, expand all matching directories to show results
            if !filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                expandMatchingItems(outlineView, node: root)
            }
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
        
        init(_ parent: FileTreeView) {
            self.parent = parent
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
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),
                
                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: container.centerYAnchor)
            ])
            
            return container
        }
        
        private func makeTokenView(for node: FileNode) -> NSView {
            let tokenCount = node.isDirectory ? node.aggregateTokenCount : node.tokenCount
            let textField = NSTextField(labelWithString: formatTokenCount(tokenCount))
            textField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            textField.alignment = .right
            textField.textColor = .secondaryLabelColor
            return textField
        }
        
        private func formatTokenCount(_ count: Int) -> String {
            if count == 0 { return "" }
            if count < 1000 { return "\(count)" }
            if count < 10000 { return String(format: "%.1fk", Double(count) / 1000) }
            if count < 1000000 { return "\(count / 1000)k" }
            return String(format: "%.1fM", Double(count) / 1000000)
        }
        
        @objc private func checkboxToggled(_ sender: NSButton) {
            // Find the node by iterating through visible items
            for row in 0..<outlineView!.numberOfRows {
                if let node = outlineView!.item(atRow: row) as? FileNode,
                   node.hashValue == sender.tag {
                    parent.onSelectionChange(node)
                    outlineView?.reloadItem(node, reloadChildren: true)
                    break
                }
            }
        }
        
        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
            return true
        }
        
        func outlineViewItemDidExpand(_ notification: Notification) {
            guard let node = notification.userInfo?["NSObject"] as? FileNode else { return }
            node.isExpanded = true
        }
        
        func outlineViewItemDidCollapse(_ notification: Notification) {
            guard let node = notification.userInfo?["NSObject"] as? FileNode else { return }
            node.isExpanded = false
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
        
        await fileTreeModel.loadDirectory(at: url, ignoreRules: ignoreRules)
        
        // Set up file system change notification
        fileTreeModel.onFileSystemChange = {
            Task { @MainActor in
                // Post notification to trigger workspace detail view refresh
                NotificationCenter.default.post(name: .fileSystemChanged, object: nil)
                
                // Update workspace selection state in case files were added/removed
                updateWorkspaceSelection()
            }
        }
        
        // Restore saved selections after loading the directory
        if !workspace.selectionJSON.isEmpty {
            await MainActor.run {
                fileTreeModel.restoreSelections(from: workspace.selectionJSON)
            }
        }
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
        fileTreeModel.updateSelection(node)
        // Update workspace selection state
        updateWorkspaceSelection()
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
        }
    }
    
    private func updateWorkspaceSelection() {
        let selectedFiles = fileTreeModel.rootNode?.getSelectedFiles() ?? []
        let selectedPaths = Set(selectedFiles.map { $0.url.path })
        
        // Convert to JSON for storage
        if let data = try? JSONEncoder().encode(selectedPaths),
           let json = String(data: data, encoding: .utf8) {
            workspace.selectionJSON = json
        }
    }
}