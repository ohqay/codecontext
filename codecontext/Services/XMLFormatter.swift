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
        // Filter out build artifacts before generating tree
        let filteredPaths = filterBuildArtifacts(paths)

        // Produce a simple indented tree (token-optimized format)
        let urls = filteredPaths.map { URL(fileURLWithPath: $0) }
        let relative = urls.compactMap { url -> String? in
            let path = url.path(percentEncoded: false)
            if path.hasPrefix(root.path) {
                return String(path.dropFirst(root.path.count + 1))
            }
            return nil
        }
        let components = relative.map { $0.split(separator: "/").map(String.init) }
        var tree: [String] = []

        func add(level: Int, items: [[String]]) {
            let grouped = Dictionary(grouping: items) { $0.first ?? "" }
            let keys = grouped.keys.sorted()

            for key in keys {
                // Use simple indentation instead of Unicode tree characters
                let indentation = String(repeating: "  ", count: level)
                let stem = indentation + key
                tree.append(stem)

                let children = grouped[key]!.map { Array($0.dropFirst()) }.filter { !$0.isEmpty }
                if !children.isEmpty {
                    add(level: level + 1, items: children)
                }
            }
        }

        add(level: 0, items: components)
        return tree
    }

    /// Filter out build artifacts and temporary files from paths
    private func filterBuildArtifacts(_ paths: [String]) -> [String] {
        return paths.filter { path in
            let pathComponents = path.split(separator: "/").map(String.init)

            // Check against build artifact patterns
            for component in pathComponents {
                // Rust build artifacts
                if component == "target" || component.hasSuffix(".d") || component.hasSuffix(".rlib") {
                    return false
                }

                // JavaScript/Node build artifacts
                if component == "node_modules" || component == "dist" || component == ".next" ||
                    component.hasSuffix(".bundle.js") || component.hasSuffix(".min.js")
                {
                    return false
                }

                // Swift/iOS build artifacts (exclude build products, not project files)
                if component == "DerivedData" || component == ".build" ||
                    component.hasSuffix(".dSYM") || component.hasSuffix(".app") ||
                    component == "xcuserdata"
                {
                    return false
                }

                // Python build artifacts
                if component == "__pycache__" || component == ".venv" || component == "build" ||
                    component.hasSuffix(".pyc") || component.hasSuffix(".egg-info")
                {
                    return false
                }

                // Java build artifacts
                if component == ".gradle" || component.hasSuffix(".class") {
                    return false
                }

                // C/C++ build artifacts
                if component.hasSuffix(".o") || component.hasSuffix(".so") || component.hasSuffix(".dylib") ||
                    component.hasPrefix("cmake-build-")
                {
                    return false
                }

                // Go build artifacts
                if component == "vendor" || component == "go.sum" || component.hasSuffix(".exe") {
                    return false
                }

                // General build/temp artifacts
                if component.hasSuffix(".log") || component.hasSuffix(".tmp") || component.hasSuffix(".cache") ||
                    component == ".DS_Store" || component == "Thumbs.db" || component.hasPrefix("incremental")
                {
                    return false
                }

                // Dependency files
                if component.hasSuffix("deps") && pathComponents.contains("target") {
                    return false
                }
            }

            return true
        }
    }
}
