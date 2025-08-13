import Foundation

// Helper extension for chunking arrays
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

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
        name = url.lastPathComponent
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
            // First ensure all children have their aggregate counts updated
            for child in children {
                child.updateAggregateTokens()
            }
            // Then sum them up
            aggregateTokenCount = children.reduce(0) { $0 + $1.aggregateTokenCount }
        } else {
            // For files, aggregate count is just the token count
            aggregateTokenCount = tokenCount
        }
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
    // NOTE: This is now only used for UI state, actual selection logic is in SelectionManager
    func toggleSelection() {
        isSelected.toggle()
        // Child selection is now handled by FileTreeModel.applySelectionUpdate
    }

    // Count total files in this node and children
    func countFiles() -> Int {
        if !isDirectory {
            return 1
        }
        return children.reduce(0) { $0 + $1.countFiles() }
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
    private let tokenProcessor: TokenProcessor
    let selectionManager: SelectionManager
    private var fileSystemWatcher: FileSystemWatcher?
    private var currentIgnoreRules: IgnoreRules?
    private var selectionTask: Task<Void, Never>?

    // Callback for file system changes
    var onFileSystemChange: (() -> Void)?

    init() {
        tokenProcessor = TokenProcessor()
        selectionManager = SelectionManager()
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
        // Process files in batches to avoid memory spikes
        let batchSize = AppConfiguration.processingBatchSize
        let fileNodes = allNodes.filter { !$0.isDirectory }

        // Process files off the main thread using TokenProcessor
        for batch in fileNodes.chunked(into: batchSize) {
            let urls = batch.map { $0.url }

            // Process batch in background
            if let results = try? await tokenProcessor.processFiles(urls, maxConcurrency: 8) {
                // Update token counts back on MainActor
                await MainActor.run {
                    for result in results {
                        if let node = batch.first(where: { $0.url == result.url }) {
                            node.tokenCount = result.tokenCount
                            node.aggregateTokenCount = result.tokenCount
                        }
                    }
                }
            }
        }

        // Update aggregate counts
        rootNode?.updateAggregateTokens()

        // Notify outline view that token values changed so visible rows update
        NotificationCenter.default.post(name: .outlineViewNeedsRefresh, object: nil)
    }

    private func calculateTokensForNode(_ node: FileNode) async {
        // This method is now mostly replaced by batch processing in calculateTokenCounts
        // Keep it for individual file updates if needed

        if let result = await tokenProcessor.processFile(node.url) {
            await MainActor.run {
                node.tokenCount = result.tokenCount
                node.aggregateTokenCount = result.tokenCount
            }
        } else {
            await MainActor.run {
                node.tokenCount = 0
                node.aggregateTokenCount = 0
            }
        }
    }

    func updateSelection(_ node: FileNode) {
        // Cancel any existing selection task
        selectionTask?.cancel()

        // Collect affected paths on main thread first
        let nodePath = node.url.path
        let (affectedPaths, affectedFiles) = collectAffectedPathsAndFiles(node: node)

        // Cancel any existing selection task to prevent conflicts
        selectionTask?.cancel()
        
        // Handle selection asynchronously
        selectionTask = Task {
            // Check for cancellation before heavy work
            if Task.isCancelled { return }
            
            // Update selection state off main thread
            let update = await selectionManager.toggleSelection(
                for: nodePath,
                affectedPaths: affectedPaths,
                affectedFiles: affectedFiles
            )

            // Check for cancellation before UI updates
            if Task.isCancelled { return }

            // Apply UI updates in batch on main thread
            await MainActor.run {
                applySelectionUpdate(update, to: node)
            }

            // Calculate tokens in background (only for files)
            if !affectedFiles.isEmpty {
                // Check for cancellation before expensive token calculation
                if Task.isCancelled { return }
                
                let (_, selectedFiles, _) = await selectionManager.getSelectionState()
                await selectionManager.updateTokenCounts(
                    for: selectedFiles,
                    tokenProcessor: tokenProcessor
                )

                // Check for cancellation before final UI update
                if Task.isCancelled { return }

                // Update token count on UI
                let (_, _, tokens) = await selectionManager.getSelectionState()
                await MainActor.run {
                    self.totalSelectedTokens = tokens
                }
            }
        }
    }

    private func collectAffectedPathsAndFiles(node: FileNode) -> (paths: Set<String>, files: Set<String>) {
        var paths = Set<String>()
        var files = Set<String>()
        var nodeCount = 0

        func collect(_ n: FileNode) {
            nodeCount += 1
            
            // Add to paths (all nodes)
            paths.insert(n.url.path)

            // Add to files if it's a file
            if !n.isDirectory {
                files.insert(n.url.path)
            }

            // Recursively collect children
            for child in n.children {
                collect(child)
            }
        }

        collect(node)
        
        // Log performance info for large operations
        if nodeCount > 1000 {
            print("[FileNode] Large folder selection: \(nodeCount) nodes, \(files.count) files")
        }
        
        return (paths, files)
    }

    private func applySelectionUpdate(_ update: SelectionUpdate, to node: FileNode) {
        // Apply selection state to UI nodes
        func applyToNode(_ n: FileNode, shouldSelect: Bool) {
            // Check if this node's path is in the affected paths
            if update.affectedPaths.contains(n.url.path) {
                n.isSelected = shouldSelect
            }

            // Recursively apply to children
            for child in n.children {
                applyToNode(child, shouldSelect: shouldSelect)
            }
        }

        // Start applying from the selected node
        applyToNode(node, shouldSelect: update.isSelected)
    }

    private func updateTotalSelectedTokens() {
        let selectedFiles = rootNode?.getSelectedFiles() ?? []
        totalSelectedTokens = selectedFiles.reduce(0) { $0 + $1.tokenCount }
        // Also ensure aggregate counts are up to date
        rootNode?.updateAggregateTokens()
    }

    // Restore selections from saved JSON data
    func restoreSelections(from selectionJSON: String) {
        guard !selectionJSON.isEmpty,
              let jsonData = selectionJSON.data(using: .utf8),
              let savedPaths = try? JSONDecoder().decode(Set<String>.self, from: jsonData)
        else {
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
        fileSystemWatcher = FileSystemWatcher(url: url, debounceInterval: 1.0)
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

        // Throttle file system changes to avoid excessive updates
        guard changes.count < AppConfiguration.maxFileSystemChanges else {
            print("Too many file system changes (\(changes.count)), skipping update")
            return
        }

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

        // Ensure visible token labels are refreshed
        NotificationCenter.default.post(name: .outlineViewNeedsRefresh, object: nil)
    }

    private func performIncrementalUpdate(modifiedFiles: [URL]) async {
        // Only recalculate tokens for modified files
        // Process modified files asynchronously
        Task {
            for fileURL in modifiedFiles {
                // Find the corresponding node
                if let node = allNodes.first(where: { $0.url == fileURL && !$0.isDirectory }) {
                    let oldTokenCount = node.tokenCount

                    // Process file in background
                    if let result = await tokenProcessor.processFile(fileURL) {
                        await MainActor.run {
                            node.tokenCount = result.tokenCount

                            if oldTokenCount != result.tokenCount {
                                print("Updated token count for \(node.name): \(oldTokenCount) -> \(result.tokenCount)")
                                // Update aggregate counts up the tree
                                node.parent?.updateAggregateTokens()
                            }
                        }
                    }
                }
            }

            await MainActor.run {
                updateTotalSelectedTokens()
                // Make sure the tokens column updates for visible rows
                NotificationCenter.default.post(name: .outlineViewNeedsRefresh, object: nil)
            }
        }
    }
}
