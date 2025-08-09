import Foundation

struct XMLFormatterService: Sendable {
    struct FileEntry: Sendable {
        let displayName: String
        let absolutePath: String
        let languageHint: String
        let contents: String
    }

    func render(codebaseRoot: URL, files: [FileEntry], includeTree: Bool, allFilePaths: [String]? = nil) -> String {
        var lines: [String] = []
        lines.append("<codebase>")
        if includeTree {
            lines.append("  <fileTree>")
            // If allFilePaths is provided, use it for the full tree; otherwise fall back to selected files
            let treePaths = allFilePaths ?? files.map { $0.absolutePath }
            lines.append(contentsOf: renderTreeFromPaths(root: codebaseRoot, paths: treePaths).map { "    " + $0 })
            lines.append("  </fileTree>")
        }

        for f in files {
            lines.append("  <file=\(f.displayName)>")
            lines.append("  Path: \(f.absolutePath)")
            lines.append("  `````\(f.languageHint)")
            // Preserve contents as-is; do not escape within code fence
            let fenced = f.contents.replacingOccurrences(of: "\r\n", with: "\n")
            for line in fenced.split(separator: "\n", omittingEmptySubsequences: false) {
                lines.append("  \(line)")
            }
            lines.append("  `````")
            lines.append("  </file=\(f.displayName)>")
        }
        lines.append("</codebase>")
        return lines.joined(separator: "\n") + "\n"
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

