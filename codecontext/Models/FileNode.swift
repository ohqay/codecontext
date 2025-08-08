import Foundation

// Tree structure for file hierarchy
@MainActor
@Observable
final class FileNode: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    var children: [FileNode] = []
    var parent: FileNode?
    
    // Selection and token tracking
    var isSelected: Bool = false
    var isExpanded: Bool = false
    var tokenCount: Int = 0
    var aggregateTokenCount: Int = 0
    
    init(url: URL, isDirectory: Bool, parent: FileNode? = nil) {
        self.url = url
        self.name = url.lastPathComponent
        self.isDirectory = isDirectory
        self.parent = parent
    }
    
    static func == (lhs: FileNode, rhs: FileNode) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    // Recursively calculate aggregate token counts
    func updateAggregateTokens() {
        if isDirectory {
            aggregateTokenCount = children.reduce(0) { $0 + $1.aggregateTokenCount }
        } else {
            aggregateTokenCount = tokenCount
        }
        parent?.updateAggregateTokens()
    }
    
    // Recursively get all selected files
    func getSelectedFiles() -> [FileNode] {
        var selected: [FileNode] = []
        if !isDirectory && isSelected {
            selected.append(self)
        }
        for child in children {
            selected.append(contentsOf: child.getSelectedFiles())
        }
        return selected
    }
    
    // Toggle selection recursively for directories
    func toggleSelection() {
        isSelected.toggle()
        if isDirectory {
            for child in children {
                child.isSelected = isSelected
                if child.isDirectory {
                    child.toggleChildrenSelection()
                }
            }
        }
    }
    
    private func toggleChildrenSelection() {
        for child in children {
            child.isSelected = isSelected
            if child.isDirectory {
                child.toggleChildrenSelection()
            }
        }
    }
}

// Root container for the file tree
@MainActor
@Observable
final class FileTreeModel {
    var rootNode: FileNode?
    var allNodes: [FileNode] = []
    var selectedFiles: Set<URL> = []
    var totalSelectedTokens: Int = 0
    private let tokenizer: Tokenizer
    private var fileSystemWatcher: FileSystemWatcher?
    private var currentIgnoreRules: IgnoreRules?
    
    // Callback for file system changes
    var onFileSystemChange: (() -> Void)?
    
    init(tokenizer: Tokenizer? = nil) {
        self.tokenizer = tokenizer ?? HuggingFaceTokenizer()
    }
    
    func loadDirectory(at url: URL, ignoreRules: IgnoreRules) async {
        // Stop existing watcher if any
        stopWatching()
        
        // Store ignore rules for use in file change handling
        currentIgnoreRules = ignoreRules
        
        rootNode = FileNode(url: url, isDirectory: true)
        await scanDirectory(node: rootNode!, ignoreRules: ignoreRules)
        await calculateTokenCounts()
        
        // Start watching for file system changes
        startWatching(at: url)
    }
    
    private func scanDirectory(node: FileNode, ignoreRules: IgnoreRules) async {
        guard node.isDirectory else { return }
        
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: node.url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        
        for itemURL in contents {
            // Check if ignored
            if ignoreRules.isIgnored(path: itemURL.path, isDirectory: itemURL.hasDirectoryPath) {
                continue
            }
            
            let isDir = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let childNode = FileNode(url: itemURL, isDirectory: isDir, parent: node)
            node.children.append(childNode)
            allNodes.append(childNode)
            
            if isDir {
                await scanDirectory(node: childNode, ignoreRules: ignoreRules)
            }
        }
        
        // Sort children: directories first, then alphabetically
        node.children.sort { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
    
    private func calculateTokenCounts() async {
        for node in allNodes where !node.isDirectory {
            if let data = try? Data(contentsOf: node.url),
               let content = String(data: data, encoding: .utf8) {
                do {
                    node.tokenCount = try await tokenizer.countTokens(content)
                } catch {
                    print("Warning: Failed to count tokens for \(node.name): \(error)")
                    node.tokenCount = 0
                }
            }
        }
        
        // Update aggregate counts
        rootNode?.updateAggregateTokens()
    }
    
    func updateSelection(_ node: FileNode) {
        node.toggleSelection()
        updateTotalSelectedTokens()
    }
    
    private func updateTotalSelectedTokens() {
        let selectedFiles = rootNode?.getSelectedFiles() ?? []
        totalSelectedTokens = selectedFiles.reduce(0) { $0 + $1.tokenCount }
    }
    
    // Restore selections from saved JSON data
    func restoreSelections(from selectionJSON: String) {
        guard !selectionJSON.isEmpty,
              let jsonData = selectionJSON.data(using: .utf8),
              let savedPaths = try? JSONDecoder().decode(Set<String>.self, from: jsonData) else {
            return
        }
        
        // Clear existing selections
        allNodes.forEach { $0.isSelected = false }
        
        // Restore selections for files that still exist
        for node in allNodes where !node.isDirectory {
            if savedPaths.contains(node.url.path) {
                node.isSelected = true
            }
        }
        
        updateTotalSelectedTokens()
    }
    
    // Refresh the file tree by rescanning the directory
    func refresh(ignoreRules: IgnoreRules) async {
        guard let rootURL = rootNode?.url else { return }
        
        // Save current selections before refreshing
        let currentSelections = Set(allNodes.compactMap { node in
            node.isSelected && !node.isDirectory ? node.url.path : nil
        })
        
        // Clear existing data
        allNodes.removeAll()
        rootNode = nil
        
        // Rescan directory
        rootNode = FileNode(url: rootURL, isDirectory: true)
        await scanDirectory(node: rootNode!, ignoreRules: ignoreRules)
        await calculateTokenCounts()
        
        // Restore selections for files that still exist
        for node in allNodes where !node.isDirectory {
            if currentSelections.contains(node.url.path) {
                node.isSelected = true
            }
        }
        
        updateTotalSelectedTokens()
    }
    
    // MARK: - File System Watching
    
    private func startWatching(at url: URL) {
        fileSystemWatcher = FileSystemWatcher(url: url, debounceInterval: 0.5)
        fileSystemWatcher?.onChanges = { [weak self] changes in
            Task { @MainActor in
                await self?.handleFileSystemChanges(changes)
            }
        }
        
        do {
            try fileSystemWatcher?.startWatching()
            print("Started watching directory: \(url.path)")
        } catch {
            print("Failed to start file system watching: \(error)")
        }
    }
    
    private func stopWatching() {
        fileSystemWatcher?.stopWatching()
        fileSystemWatcher = nil
    }
    
    private func handleFileSystemChanges(_ changes: [FileSystemWatcher.FileChange]) async {
        guard let rootURL = rootNode?.url,
              let ignoreRules = currentIgnoreRules else { return }
        
        print("Detected \(changes.count) file system change(s)")
        
        // Save current selections before updating
        let currentSelections = Set(allNodes.compactMap { node in
            node.isSelected && !node.isDirectory ? node.url.path : nil
        })
        
        var needsFullRefresh = false
        var modifiedFiles: [URL] = []
        
        for change in changes {
            switch change.changeType {
            case .created, .deleted, .renamed:
                // These require a full refresh of the tree structure
                needsFullRefresh = true
            case .modified:
                // Track modified files for incremental token updates
                modifiedFiles.append(change.url)
            case .unknown:
                needsFullRefresh = true
            }
        }
        
        if needsFullRefresh {
            // Perform a full refresh for structural changes
            await performFullRefresh(rootURL: rootURL, ignoreRules: ignoreRules, preservedSelections: currentSelections)
        } else if !modifiedFiles.isEmpty {
            // Perform incremental updates for file modifications only
            await performIncrementalUpdate(modifiedFiles: modifiedFiles)
        }
        
        // Notify UI of changes
        onFileSystemChange?()
    }
    
    private func performFullRefresh(rootURL: URL, ignoreRules: IgnoreRules, preservedSelections: Set<String>) async {
        // Clear existing data
        allNodes.removeAll()
        rootNode = nil
        
        // Rescan directory
        rootNode = FileNode(url: rootURL, isDirectory: true)
        await scanDirectory(node: rootNode!, ignoreRules: ignoreRules)
        await calculateTokenCounts()
        
        // Restore selections for files that still exist
        for node in allNodes where !node.isDirectory {
            if preservedSelections.contains(node.url.path) {
                node.isSelected = true
            }
        }
        
        updateTotalSelectedTokens()
    }
    
    private func performIncrementalUpdate(modifiedFiles: [URL]) async {
        // Only recalculate tokens for modified files
        for fileURL in modifiedFiles {
            // Find the corresponding node
            if let node = allNodes.first(where: { $0.url == fileURL && !$0.isDirectory }) {
                // Recalculate token count for this file only
                if let data = try? Data(contentsOf: fileURL),
                   let content = String(data: data, encoding: .utf8) {
                    do {
                        let oldTokenCount = node.tokenCount
                        node.tokenCount = try await tokenizer.countTokens(content)
                        
                        if oldTokenCount != node.tokenCount {
                            print("Updated token count for \(node.name): \(oldTokenCount) -> \(node.tokenCount)")
                            // Update aggregate counts up the tree
                            node.parent?.updateAggregateTokens()
                        }
                    } catch {
                        print("Warning: Failed to update tokens for \(node.name): \(error)")
                    }
                }
            }
        }
        
        updateTotalSelectedTokens()
    }
}