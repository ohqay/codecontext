import Foundation

// MARK: - Supporting Types

/// Centralized build artifact patterns to avoid duplication
private enum BuildArtifacts {
    static let patterns: Set<String> = [
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
        "yarn.lock", "package-lock.json", "pnpm-lock.yaml"
    ]
}

/// High-performance pattern matching with pre-compiled regex cache
private struct PatternMatcher {
    private let compiledRegexes: [String: NSRegularExpression?]

    init(patterns: [String]) {
        var cache: [String: NSRegularExpression?] = [:]

        for pattern in patterns {
            // Convert glob pattern to regex and attempt compilation
            let regexPattern = Self.convertGlobToRegex(pattern)
            let compiledRegex = try? NSRegularExpression(pattern: regexPattern, options: [])
            cache[pattern] = compiledRegex
        }

        compiledRegexes = cache
    }

    func matches(pattern: String, against path: String) -> Bool {
        // Check cache first
        if let cachedRegex = compiledRegexes[pattern] {
            if let regex = cachedRegex {
                let range = NSRange(location: 0, length: path.count)
                return regex.firstMatch(in: path, options: [], range: range) != nil
            }
            // If regex compilation failed, fall back to optimized glob matching
            return optimizedGlobMatch(pattern: pattern, text: path)
        }

        // Pattern not in cache, compile on demand
        let regexPattern = Self.convertGlobToRegex(pattern)
        if let regex = try? NSRegularExpression(pattern: regexPattern, options: []) {
            let range = NSRange(location: 0, length: path.count)
            return regex.firstMatch(in: path, options: [], range: range) != nil
        }

        return optimizedGlobMatch(pattern: pattern, text: path)
    }

    private static func convertGlobToRegex(_ pattern: String) -> String {
        var regexPattern = pattern
        regexPattern = regexPattern.replacingOccurrences(of: ".", with: "\\.")
        regexPattern = regexPattern.replacingOccurrences(of: "*", with: "[^/]*")
        regexPattern = regexPattern.replacingOccurrences(of: "?", with: "[^/]")
        return "^" + regexPattern + "$"
    }

    private func optimizedGlobMatch(pattern: String, text: String) -> Bool {
        // Optimized non-recursive glob matching
        let patternChars = Array(pattern)
        let textChars = Array(text)
        let patternCount = patternChars.count
        let textCount = textChars.count

        var pIndex = 0
        var tIndex = 0
        var starIndex = -1
        var match = 0

        while tIndex < textCount {
            if pIndex < patternCount && (patternChars[pIndex] == "?" || patternChars[pIndex] == textChars[tIndex]) {
                pIndex += 1
                tIndex += 1
            } else if pIndex < patternCount && patternChars[pIndex] == "*" {
                starIndex = pIndex
                match = tIndex
                pIndex += 1
            } else if starIndex != -1 {
                pIndex = starIndex + 1
                match += 1
                tIndex = match
            } else {
                return false
            }
        }

        while pIndex < patternCount && patternChars[pIndex] == "*" {
            pIndex += 1
        }

        return pIndex == patternCount
    }
}

/// Utility for efficient path processing operations
private struct PathProcessor {
    let rootPath: String

    func getRelativePath(from fullPath: String) -> String {
        guard !rootPath.isEmpty, fullPath.hasPrefix(rootPath) else {
            return fullPath
        }

        let relativePath = String(fullPath.dropFirst(rootPath.count))
        return relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
    }

    func getFilename(from path: String) -> String {
        return URL(fileURLWithPath: path).lastPathComponent
    }

    func matchesSimplePattern(_ pattern: String, filename: String, path: String) -> Bool {
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
}

struct IgnoreRules: Sendable {
    let respectGitIgnore: Bool
    let respectDotIgnore: Bool
    let showHiddenFiles: Bool
    let defaultExclusions: Set<String>
    let customPatterns: [String]
    private let gitignorePatterns: [IgnorePattern]
    private let dotignorePatterns: [IgnorePattern]
    private let pathProcessor: PathProcessor
    private let customPatternMatcher: PatternMatcher

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
        pathProcessor = PathProcessor(rootPath: rootPath)
        customPatternMatcher = PatternMatcher(patterns: customPatterns)

        var defaults: Set<String> = []
        if excludeNodeModules { defaults.insert("node_modules") }
        if excludeGit { defaults.insert(".git") }
        if excludeBuild { defaults.insert("build") }
        if excludeDist { defaults.insert("dist") }
        if excludeNext { defaults.insert(".next") }
        if excludeVenv { defaults.insert(".venv") }
        if excludeDSStore { defaults.insert(".DS_Store") }
        if excludeDerivedData { defaults.insert("DerivedData") }

        // Use centralized build artifact patterns
        defaults.formUnion(BuildArtifacts.patterns)
        defaultExclusions = defaults
        self.customPatterns = customPatterns

        // Parse ignore files if they exist and we respect them
        gitignorePatterns = respectGitIgnore ? Self.parseIgnoreFile(at: rootPath + "/.gitignore") : []
        dotignorePatterns = respectDotIgnore ? Self.parseIgnoreFile(at: rootPath + "/.ignore") : []
    }

    func isIgnored(path: String, isDirectory: Bool) -> Bool {
        let filename = pathProcessor.getFilename(from: path)

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

        // Check custom patterns using pre-compiled matcher
        for pattern in customPatterns {
            if pathProcessor.matchesSimplePattern(pattern, filename: filename, path: path) {
                logIgnoreReason(path: path, reason: "custom pattern: \(pattern)")
                return true
            }
        }

        // Get relative path for gitignore-style matching
        let relativePath = pathProcessor.getRelativePath(from: path)

        // Check both gitignore and .ignore patterns using unified evaluation
        if let result = evaluateIgnorePatterns(relativePath: relativePath, isDirectory: isDirectory) {
            logIgnoreReason(path: path, reason: "ignore pattern match (result: \(result))")
            return result
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

    /// Unified evaluation of both gitignore and .ignore patterns
    private func evaluateIgnorePatterns(relativePath: String, isDirectory: Bool) -> Bool? {
        // Check gitignore patterns first (if enabled)
        if respectGitIgnore,
           let gitResult = evaluatePatterns(gitignorePatterns, against: relativePath, isDirectory: isDirectory) {
            return gitResult
        }

        // Check .ignore patterns (if enabled)
        if respectDotIgnore,
           let ignoreResult = evaluatePatterns(dotignorePatterns, against: relativePath, isDirectory: isDirectory) {
            return ignoreResult
        }

        return nil
    }

    /// Evaluates ignore patterns against a path, returning nil if no pattern matches,
    /// true if the path should be ignored, false if it should be included (negated)
    private func evaluatePatterns(_ patterns: [IgnorePattern], against path: String, isDirectory: Bool) -> Bool? {
        var shouldIgnore: Bool?

        for pattern in patterns where pattern.matches(path: path, isDirectory: isDirectory) {
            shouldIgnore = !pattern.isNegated
        }

        return shouldIgnore
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
            guard !trimmedLine.isEmpty && !trimmedLine.hasPrefix("#") else {
                continue
            }

            patterns.append(IgnorePattern(pattern: trimmedLine))
        }

        return patterns
    }
}

/// Represents a single gitignore-style pattern with optimized matching logic
private struct IgnorePattern {
    let original: String
    let pattern: String
    let isNegated: Bool
    let isDirectoryOnly: Bool
    let isRooted: Bool
    let hasDoubleAsterisk: Bool
    private let patternMatcher: PatternMatcher

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

        // Check pattern characteristics
        isDirectoryOnly = self.pattern.hasSuffix("/")
        isRooted = self.pattern.hasPrefix("/")
        hasDoubleAsterisk = self.pattern.contains("**")

        // Initialize pattern matcher for this specific pattern
        patternMatcher = PatternMatcher(patterns: [self.pattern])
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

        for index in 0 ..< pathComponents.count {
            let pathSuffix = pathComponents[index...].joined(separator: "/")
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
            // Use optimized pattern matcher for single patterns
            return patternMatcher.matches(pattern: pattern, against: path)
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
                return path.hasSuffix(cleanSuffix) || patternMatcher.matches(pattern: cleanSuffix, against: path)
            }

            // Handle trailing **
            if suffix.isEmpty || suffix == "/" {
                let cleanPrefix = prefix.hasSuffix("/") ? String(prefix.dropLast()) : prefix
                return path.hasPrefix(cleanPrefix) || patternMatcher.matches(pattern: cleanPrefix, against: path)
            }

            // Handle ** in the middle
            let cleanPrefix = prefix.hasSuffix("/") ? String(prefix.dropLast()) : prefix
            let cleanSuffix = suffix.hasPrefix("/") ? String(suffix.dropFirst()) : suffix

            return path.hasPrefix(cleanPrefix) && path.hasSuffix(cleanSuffix)
        }

        // Multiple ** - simplified matching
        let simplifiedPattern = pattern.replacingOccurrences(of: "**", with: "*")
        return patternMatcher.matches(pattern: simplifiedPattern, against: path)
    }
}
