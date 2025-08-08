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
    
    init(tokenizer: Tokenizer? = nil) {
        self.tokenizer = tokenizer ?? HuggingFaceTokenizer()
    }
    
    func loadDirectory(at url: URL, ignoreRules: IgnoreRules) async {
        rootNode = FileNode(url: url, isDirectory: true)
        await scanDirectory(node: rootNode!, ignoreRules: ignoreRules)
        await calculateTokenCounts()
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
}