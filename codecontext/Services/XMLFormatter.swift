import Foundation

struct XMLFormatterService: Sendable {
    struct FileEntry: Sendable {
        let displayName: String
        let absolutePath: String
        let languageHint: String
        let contents: String
    }

    func render(codebaseRoot: URL, files: [FileEntry], includeTree: Bool) -> String {
        var lines: [String] = []
        lines.append("<codebase>")
        if includeTree {
            lines.append("  <fileTree>")
            lines.append(contentsOf: renderTree(root: codebaseRoot, files: files).map { "    " + $0 })
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
        // Produce a simple ASCII tree for the included files only
        let paths = files.map { URL(fileURLWithPath: $0.absolutePath) }
        let relative = paths.compactMap { $0.path(percentEncoded: false).dropFirst(root.path.count + 1) }
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

