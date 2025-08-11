import Foundation

struct IgnoreRules: Sendable {
    let respectGitIgnore: Bool
    let respectDotIgnore: Bool
    let showHiddenFiles: Bool
    let defaultExclusions: Set<String>
    let customPatterns: [String]
    private let gitignorePatterns: [IgnorePattern]
    private let dotignorePatterns: [IgnorePattern]
    private let rootPath: String

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
        customPatterns: [String] = [],
        rootPath: String = ""
    ) {
        self.respectGitIgnore = respectGitIgnore
        self.respectDotIgnore = respectDotIgnore
        self.showHiddenFiles = showHiddenFiles
        self.rootPath = rootPath

        var defaults: Set<String> = []
        if excludeNodeModules { defaults.insert("node_modules") }
        if excludeGit { defaults.insert(".git") }
        if excludeBuild { defaults.insert("build") }
        if excludeDist { defaults.insert("dist") }
        if excludeNext { defaults.insert(".next") }
        if excludeVenv { defaults.insert(".venv") }
        if excludeDSStore { defaults.insert(".DS_Store") }
        if excludeDerivedData { defaults.insert("DerivedData") }

        // Add comprehensive build artifact exclusions
        let buildArtifacts: Set<String> = [
            // Rust
            "target", "Cargo.lock",

            // JavaScript/TypeScript/Node
            "node_modules", "dist", "build", ".next", ".nuxt", ".output",
            "coverage", ".nyc_output", "bower_components",

            // Python
            "__pycache__", ".venv", "venv", ".env", "env",
            ".tox", ".coverage", ".pytest_cache", ".mypy_cache",
            "build", "dist", "*.egg-info",

            // Swift/iOS/macOS (exclude actual build products, not project files)
            "DerivedData", ".build", "*.dSYM", "*.app", "*.ipa", "Pods",
            "xcuserdata", "*.xcuserdatad",

            // Java/Kotlin/Android
            ".gradle", "build", "target", ".idea",
            "*.class", "*.jar", "*.war", "*.ear",

            // C/C++/CMake
            "build", "cmake-build-debug", "cmake-build-release",
            "*.o", "*.so", "*.dylib", "*.dll", "*.exe",

            // Go
            "vendor", "go.sum",

            // .NET/C#
            "bin", "obj", "packages", "*.user",

            // Ruby
            ".bundle", "vendor/bundle", "log", "tmp",

            // PHP
            "vendor", "composer.lock",

            // General build/cache/temp
            ".cache", "cache", "logs", "log", "tmp", "temp",
            ".DS_Store", "Thumbs.db", "*.log", "*.tmp",

            // Version control and IDE
            ".svn", ".hg", ".bzr",
            ".vscode", ".idea", "*.swp", "*.swo", "*~",

            // Package managers
            "yarn.lock", "package-lock.json", "pnpm-lock.yaml",
        ]

        defaults.formUnion(buildArtifacts)
        defaultExclusions = defaults
        self.customPatterns = customPatterns

        // Parse .gitignore file if it exists and we respect it
        if respectGitIgnore {
            gitignorePatterns = Self.parseIgnoreFile(at: rootPath + "/.gitignore")
        } else {
            gitignorePatterns = []
        }

        // Parse .ignore file if it exists and we respect it
        if respectDotIgnore {
            dotignorePatterns = Self.parseIgnoreFile(at: rootPath + "/.ignore")
        } else {
            dotignorePatterns = []
        }
    }

    func isIgnored(path: String, isDirectory: Bool) -> Bool {
        let url = URL(fileURLWithPath: path)
        let filename = url.lastPathComponent

        // Check for hidden files
        if !showHiddenFiles && filename.hasPrefix(".") {
            logIgnoreReason(path: path, reason: "hidden file (showHiddenFiles=false)")
            return true
        }

        // Check default exclusions
        if defaultExclusions.contains(filename) {
            logIgnoreReason(path: path, reason: "default exclusion: \(filename)")
            return true
        }

        // Check custom patterns
        for pattern in customPatterns {
            if matches(pattern: pattern, path: path, isDirectory: isDirectory) {
                logIgnoreReason(path: path, reason: "custom pattern: \(pattern)")
                return true
            }
        }

        // Get relative path from root for gitignore-style matching
        let relativePath = getRelativePath(fullPath: path)

        // Check gitignore patterns
        if respectGitIgnore {
            let gitignoreResult = evaluatePatterns(gitignorePatterns, against: relativePath, isDirectory: isDirectory)
            if let result = gitignoreResult {
                logIgnoreReason(path: path, reason: "gitignore pattern (result: \(result))")
                return result
            }
        }

        // Check .ignore patterns
        if respectDotIgnore {
            let dotignoreResult = evaluatePatterns(dotignorePatterns, against: relativePath, isDirectory: isDirectory)
            if let result = dotignoreResult {
                logIgnoreReason(path: path, reason: ".ignore pattern (result: \(result))")
                return result
            }
        }

        return false
    }

    #if DEBUG
        private func logIgnoreReason(path: String, reason: String) {
            let filename = URL(fileURLWithPath: path).lastPathComponent
            if filename.contains("pbxproj") || filename.contains("xcodeproj") {
                print("[IgnoreRules] Ignoring \(filename): \(reason)")
            }
        }
    #else
        private func logIgnoreReason(path _: String, reason _: String) {
            // No-op in release builds
        }
    #endif

    private func getRelativePath(fullPath: String) -> String {
        guard !rootPath.isEmpty, fullPath.hasPrefix(rootPath) else {
            return fullPath
        }

        let relativePath = String(fullPath.dropFirst(rootPath.count))
        if relativePath.hasPrefix("/") {
            return String(relativePath.dropFirst())
        }
        return relativePath
    }

    /// Evaluates ignore patterns against a path, returning nil if no pattern matches,
    /// true if the path should be ignored, false if it should be included (negated)
    private func evaluatePatterns(_ patterns: [IgnorePattern], against path: String, isDirectory: Bool) -> Bool? {
        var shouldIgnore: Bool? = nil

        for pattern in patterns {
            if pattern.matches(path: path, isDirectory: isDirectory) {
                shouldIgnore = !pattern.isNegated
            }
        }

        return shouldIgnore
    }

    private func matches(pattern: String, path: String, isDirectory _: Bool) -> Bool {
        // Improved glob-style matching: handles file extensions and path components correctly
        let filename = URL(fileURLWithPath: path).lastPathComponent

        if pattern.hasPrefix("*") && pattern.hasSuffix("*") {
            let token = String(pattern.dropFirst().dropLast())
            return filename.contains(token)
        } else if pattern.hasPrefix("*") {
            let token = String(pattern.dropFirst())
            // For patterns like *.xcworkspace, match file extensions properly
            if token.hasPrefix(".") {
                return filename.hasSuffix(token)
            } else {
                return filename.hasSuffix(token)
            }
        } else if pattern.hasSuffix("*") {
            let token = String(pattern.dropLast())
            return filename.hasPrefix(token)
        } else {
            // Exact match against filename or path component
            return filename == pattern || path.contains(pattern)
        }
    }

    /// Parse ignore file (.gitignore or .ignore) and return array of patterns
    private static func parseIgnoreFile(at filePath: String) -> [IgnorePattern] {
        guard let contents = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return []
        }

        var patterns: [IgnorePattern] = []
        let lines = contents.components(separatedBy: .newlines)

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip empty lines and comments
            if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") {
                continue
            }

            patterns.append(IgnorePattern(pattern: trimmedLine))
        }

        return patterns
    }
}

/// Represents a single gitignore-style pattern with parsing logic
private struct IgnorePattern {
    let original: String
    let pattern: String
    let isNegated: Bool
    let isDirectoryOnly: Bool
    let isRooted: Bool
    let hasDoubleAsterisk: Bool

    init(pattern: String) {
        original = pattern

        // Handle negation
        if pattern.hasPrefix("!") {
            isNegated = true
            let withoutNegation = String(pattern.dropFirst())
            self.pattern = withoutNegation
        } else {
            isNegated = false
            self.pattern = pattern
        }

        // Check if directory-only pattern
        isDirectoryOnly = self.pattern.hasSuffix("/")

        // Check if pattern is rooted (starts with /)
        isRooted = self.pattern.hasPrefix("/")

        // Check for double asterisk (**) patterns
        hasDoubleAsterisk = self.pattern.contains("**")
    }

    func matches(path: String, isDirectory: Bool) -> Bool {
        // Directory-only patterns only match directories
        if isDirectoryOnly && !isDirectory {
            return false
        }

        let cleanPattern = pattern.hasSuffix("/") ? String(pattern.dropLast()) : pattern
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path

        // Rooted patterns match from the beginning
        if isRooted {
            let rootedPattern = String(cleanPattern.dropFirst()) // Remove leading /
            return matchPattern(rootedPattern, against: cleanPath)
        }

        // Non-rooted patterns can match anywhere in the path
        // Split path into components and try matching against each suffix
        let pathComponents = cleanPath.components(separatedBy: "/")

        for i in 0 ..< pathComponents.count {
            let pathSuffix = pathComponents[i...].joined(separator: "/")
            if matchPattern(cleanPattern, against: pathSuffix) {
                return true
            }
        }

        return false
    }

    private func matchPattern(_ pattern: String, against path: String) -> Bool {
        if hasDoubleAsterisk {
            return matchDoubleAsteriskPattern(pattern, against: path)
        } else {
            return matchSinglePattern(pattern, against: path)
        }
    }

    private func matchDoubleAsteriskPattern(_ pattern: String, against path: String) -> Bool {
        let parts = pattern.components(separatedBy: "**")

        if parts.count == 2 {
            let prefix = parts[0]
            let suffix = parts[1]

            // Handle leading **
            if prefix.isEmpty {
                let cleanSuffix = suffix.hasPrefix("/") ? String(suffix.dropFirst()) : suffix
                return path.hasSuffix(cleanSuffix) || matchSinglePattern(cleanSuffix, against: path)
            }

            // Handle trailing **
            if suffix.isEmpty || suffix == "/" {
                let cleanPrefix = prefix.hasSuffix("/") ? String(prefix.dropLast()) : prefix
                return path.hasPrefix(cleanPrefix) || matchSinglePattern(cleanPrefix, against: path)
            }

            // Handle ** in the middle
            let cleanPrefix = prefix.hasSuffix("/") ? String(prefix.dropLast()) : prefix
            let cleanSuffix = suffix.hasPrefix("/") ? String(suffix.dropFirst()) : suffix

            return path.hasPrefix(cleanPrefix) && path.hasSuffix(cleanSuffix)
        }

        // Multiple ** - simplified matching
        return matchSinglePattern(pattern.replacingOccurrences(of: "**", with: "*"), against: path)
    }

    private func matchSinglePattern(_ pattern: String, against path: String) -> Bool {
        // Convert glob pattern to regex-like matching
        var regexPattern = pattern
        regexPattern = regexPattern.replacingOccurrences(of: ".", with: "\\.")
        regexPattern = regexPattern.replacingOccurrences(of: "*", with: "[^/]*")
        regexPattern = regexPattern.replacingOccurrences(of: "?", with: "[^/]")
        regexPattern = "^" + regexPattern + "$"

        do {
            let regex = try NSRegularExpression(pattern: regexPattern, options: [])
            let range = NSRange(location: 0, length: path.count)
            return regex.firstMatch(in: path, options: [], range: range) != nil
        } catch {
            // Fallback to simple matching if regex fails
            return simpleGlobMatch(pattern: pattern, text: path)
        }
    }

    private func simpleGlobMatch(pattern: String, text: String) -> Bool {
        if pattern.isEmpty { return text.isEmpty }
        if text.isEmpty { return pattern.allSatisfy { $0 == "*" } }

        let patternChars = Array(pattern)
        let textChars = Array(text)

        return globMatchHelper(patternChars, 0, textChars, 0)
    }

    private func globMatchHelper(_ pattern: [Character], _ pIdx: Int, _ text: [Character], _ tIdx: Int) -> Bool {
        if pIdx >= pattern.count {
            return tIdx >= text.count
        }

        if pattern[pIdx] == "*" {
            // Try matching zero characters
            if globMatchHelper(pattern, pIdx + 1, text, tIdx) {
                return true
            }
            // Try matching one or more characters (but not '/' for single *)
            for i in tIdx ..< text.count {
                if text[i] == "/" { break }
                if globMatchHelper(pattern, pIdx + 1, text, i + 1) {
                    return true
                }
            }
            return false
        }

        if tIdx >= text.count {
            return false
        }

        if pattern[pIdx] == "?" || pattern[pIdx] == text[tIdx] {
            return globMatchHelper(pattern, pIdx + 1, text, tIdx + 1)
        }

        return false
    }
}
