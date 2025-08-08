import SwiftUI
import AppKit

// NSOutlineView-based file tree for performance with large directories
struct FileTreeView: NSViewRepresentable {
    @Binding var fileTreeModel: FileTreeModel
    @Binding var filterText: String
    let onSelectionChange: (FileNode) -> Void
    let onPreview: (FileNode) -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let outlineView = NSOutlineView()
        
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
        
        context.coordinator.outlineView = outlineView
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let outlineView = nsView.documentView as? NSOutlineView else { return }
        
        context.coordinator.parent = self
        outlineView.reloadData()
        
        // Expand root by default
        if let root = fileTreeModel.rootNode {
            outlineView.expandItem(root)
        }
    }
    
    class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        var parent: FileTreeView
        weak var outlineView: NSOutlineView?
        
        init(_ parent: FileTreeView) {
            self.parent = parent
        }
        
        // MARK: - DataSource
        
        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            if item == nil {
                return parent.fileTreeModel.rootNode != nil ? 1 : 0
            }
            guard let node = item as? FileNode else { return 0 }
            return node.children.count
        }
        
        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            if item == nil {
                return parent.fileTreeModel.rootNode!
            }
            guard let node = item as? FileNode else { return FileNode(url: URL(fileURLWithPath: "/"), isDirectory: false) }
            return node.children[index]
        }
        
        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let node = item as? FileNode else { return false }
            return node.isDirectory && !node.children.isEmpty
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
            guard let node = item as? FileNode else { return false }
            parent.onPreview(node)
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
    }
}

// SwiftUI wrapper for the file tree
struct FileTreeContainer: View {
    @State private var fileTreeModel = FileTreeModel()
    @Binding var workspace: SDWorkspace
    @Binding var filterText: String
    @State private var previewNode: FileNode?
    @State private var showingQuickLook = false
    
    var body: some View {
        FileTreeView(
            fileTreeModel: $fileTreeModel,
            filterText: $filterText,
            onSelectionChange: handleSelectionChange,
            onPreview: handlePreview
        )
        .task {
            await loadWorkspace()
        }
        .onChange(of: workspace) { _, _ in
            Task {
                await loadWorkspace()
            }
        }
        .sheet(isPresented: $showingQuickLook) {
            if let node = previewNode {
                QuickLookView(fileNode: node)
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
            customPatterns: workspace.customIgnore.split(separator: "\n").map(String.init)
        )
        
        await fileTreeModel.loadDirectory(at: url, ignoreRules: ignoreRules)
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
    
    private func handlePreview(_ node: FileNode) {
        if !node.isDirectory {
            previewNode = node
            showingQuickLook = true
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