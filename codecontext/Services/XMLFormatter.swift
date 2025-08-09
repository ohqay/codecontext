import Foundation

struct XMLFormatterService: Sendable {
    struct FileEntry: Sendable {
        let displayName: String
        let absolutePath: String
        let languageHint: String
        let contents: String
    }

    func render(codebaseRoot: URL, files: [FileEntry], includeTree: Bool, allFilePaths: [String]? = nil) -> String {
        // Pre-calculate capacity for better performance
        let estimatedCapacity = files.count * 500 + (includeTree ? 1000 : 0)
        var output = ""
        output.reserveCapacity(estimatedCapacity)
        
        output.append("<codebase>\n")
        
        if includeTree {
            output.append("  <fileTree>\n")
            // If allFilePaths is provided, use it for the full tree; otherwise fall back to selected files
            let treePaths = allFilePaths ?? files.map { $0.absolutePath }
            for line in renderTreeFromPaths(root: codebaseRoot, paths: treePaths) {
                output.append("    ")
                output.append(line)
                output.append("\n")
            }
            output.append("  </fileTree>\n")
        }

        for f in files {
            output.append("  <file=\(f.displayName)>\n")
            output.append("  Path: \(f.absolutePath)\n")
            output.append("  `````\(f.languageHint)\n")
            
            // Process content more efficiently
            let contentLines = f.contents.split(separator: "\n", omittingEmptySubsequences: false)
            for line in contentLines {
                output.append("  ")
                output.append(String(line))
                output.append("\n")
            }
            
            output.append("  `````\n")
            output.append("  </file=\(f.displayName)>\n")
        }
        
        output.append("</codebase>\n")
        return output
    }

    private func renderTree(root: URL, files: [FileEntry]) -> [String] {
        // Legacy method - kept for compatibility
        return renderTreeFromPaths(root: root, paths: files.map { $0.absolutePath })
    }
    
    private func renderTreeFromPaths(root: URL, paths: [String]) -> [String] {
        // Produce a simple ASCII tree for the provided paths
        let urls = paths.map { URL(fileURLWithPath: $0) }
        let relative = urls.compactMap { url -> String? in
            let path = url.path(percentEncoded: false)
            if path.hasPrefix(root.path) {
                return String(path.dropFirst(root.path.count + 1))
            }
            return nil
        }
        let components = relative.map { $0.split(separator: "/").map(String.init) }
        var tree: [String] = []
        func add(level: Int, prefix: String, items: [[String]]) {
            let grouped = Dictionary(grouping: items) { $0.first ?? "" }
            let keys = grouped.keys.sorted()
            for (i, key) in keys.enumerated() {
                let isLast = i == keys.count - 1
                let stem = prefix + (isLast ? "└─ " : "├─ ") + key
                tree.append(stem)
                let children = grouped[key]!.map { Array($0.dropFirst()) }.filter { !$0.isEmpty }
                if !children.isEmpty {
                    add(level: level + 1, prefix: prefix + (isLast ? "   " : "│  "), items: children)
                }
            }
        }
        add(level: 0, prefix: "", items: components)
        return tree
    }
}

