import Foundation

struct IgnoreRules: Sendable {
    let respectGitIgnore: Bool
    let respectDotIgnore: Bool
    let showHiddenFiles: Bool
    let defaultExclusions: Set<String>
    let customPatterns: [String]

    init(
        respectGitIgnore: Bool = true,
        respectDotIgnore: Bool = true,
        showHiddenFiles: Bool = false,
        excludeNodeModules: Bool = true,
        excludeGit: Bool = true,
        excludeBuild: Bool = true,
        excludeDist: Bool = true,
        excludeNext: Bool = true,
        excludeVenv: Bool = true,
        excludeDSStore: Bool = true,
        excludeDerivedData: Bool = true,
        customPatterns: [String] = []
    ) {
        self.respectGitIgnore = respectGitIgnore
        self.respectDotIgnore = respectDotIgnore
        self.showHiddenFiles = showHiddenFiles
        var defaults: Set<String> = []
        if excludeNodeModules { defaults.insert("node_modules") }
        if excludeGit { defaults.insert(".git") }
        if excludeBuild { defaults.insert("build") }
        if excludeDist { defaults.insert("dist") }
        if excludeNext { defaults.insert(".next") }
        if excludeVenv { defaults.insert(".venv") }
        if excludeDSStore { defaults.insert(".DS_Store") }
        if excludeDerivedData { defaults.insert("DerivedData") }
        self.defaultExclusions = defaults
        self.customPatterns = customPatterns
    }

    func isIgnored(path: String, isDirectory: Bool) -> Bool {
        let url = URL(fileURLWithPath: path)
        let last = url.lastPathComponent
        if !showHiddenFiles && last.hasPrefix(".") {
            return true
        }
        if defaultExclusions.contains(last) {
            return true
        }
        for pattern in customPatterns where matches(pattern: pattern, path: path, isDirectory: isDirectory) {
            return true
        }
        return false
    }

    private func matches(pattern: String, path: String, isDirectory: Bool) -> Bool {
        // Minimal glob-style matching: supports leading/trailing * and suffix matches
        if pattern.hasPrefix("*") && pattern.hasSuffix("*") {
            let token = String(pattern.dropFirst().dropLast())
            return path.contains(token)
        } else if pattern.hasPrefix("*") {
            let token = String(pattern.dropFirst())
            return path.hasSuffix(token)
        } else if pattern.hasSuffix("*") {
            let token = String(pattern.dropLast())
            return path.hasPrefix(token)
        } else {
            return path.contains(pattern)
        }
    }
}

