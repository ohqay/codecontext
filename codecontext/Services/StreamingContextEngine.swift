import Foundation

/// High-performance streaming XML context engine for real-time generation
/// Designed to handle million-token contexts with minimal latency
actor StreamingContextEngine {
    // MARK: - Types

    enum EngineError: LocalizedError {
        case invalidURL
        case cancelled
        case memoryPressure

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid file URL"
            case .cancelled: return "Operation was cancelled"
            case .memoryPressure: return "System memory pressure too high"
            }
        }
    }

    struct GenerationResult {
        let xml: String
        let tokenCount: Int
        let filesProcessed: Int
        let generationTime: TimeInterval
    }

    struct DebugInfo {
        let timestamp: Date
        let event: String
        let details: String?
    }

    // MARK: - Properties

    private let fragmentCache: XMLFragmentCache
    private let contentCache: FileContentCache

    private var currentGeneration: Task<GenerationResult, Error>?
    private var debugLogs: [DebugInfo] = []
    private let maxDebugLogs = 1000
    private let progressReporter = ProgressReporter()

    // Performance configuration
    private let maxConcurrentReads = 8
    private let debounceInterval: TimeInterval = 0.1 // 100ms
    private let maxFileSizeForCaching: Int = 5 * 1024 * 1024 // 5MB

    // MARK: - Initialization

    init() async {
        fragmentCache = XMLFragmentCache(maxSize: 100 * 1024 * 1024) // 100MB cache
        contentCache = FileContentCache(maxSize: 50 * 1024 * 1024) // 50MB cache

        logDebug("StreamingContextEngine initialized", details: "Fragment cache: 100MB, Content cache: 50MB")
    }

    // MARK: - Public Methods

    /// Generate XML context with real-time streaming updates
    /// Generate incremental update for selection changes
    /// This method efficiently updates the context by only processing changed files
    /// rather than regenerating everything from scratch
    func updateContext(
        currentXML: String,
        addedPaths: Set<String>,
        removedPaths: Set<String>,
        allFiles: [FileInfo],
        includeTree: Bool,
        rootURL: URL,
        userInstructions: String = ""
    ) async throws -> GenerationResult {
        let startTime = Date()
        logDebug("Incremental update", details: "Added: \(addedPaths.count), Removed: \(removedPaths.count)")

        var updatedXML = currentXML
        var updatedTokenCount = 0

        // Remove files that were deselected
        for pathToRemove in removedPaths {
            let xmlBeforeRemoval = updatedXML
            updatedXML = removeFileFromXML(updatedXML, path: pathToRemove, rootURL: rootURL)

            // Validate removal was successful
            if xmlBeforeRemoval == updatedXML {
                logDebug("WARNING: File removal had no effect", details: "Path: \(pathToRemove)")
            }
        }

        // Add newly selected files
        if !addedPaths.isEmpty {
            var newFilesXML = ""

            for path in addedPaths {
                guard let file = allFiles.first(where: { $0.url.path == path }) else { continue }

                // Read file content
                let content = try await AsyncFileReader.shared.readFile(at: file.url)

                // Generate XML for this file using consistent format
                let fileName = file.url.lastPathComponent
                let relativePath = convertToRelativePath(file.url.path, rootURL: rootURL)
                let languageHint = LanguageMap.languageHint(for: file.url)

                logDebug("Adding file to XML", details: "Absolute: \(file.url.path) → Relative: \(relativePath)")

                newFilesXML.append(generateFileXML(
                    name: fileName,
                    path: relativePath,
                    language: languageHint,
                    content: content
                ))
                newFilesXML.append("\n")
            }

            // Insert new files before closing </codebase> tag
            updatedXML = insertFilesIntoXML(updatedXML, newFilesXML: newFilesXML)
        }

        // Update file tree if needed
        if includeTree {
            let treeXML = generateFileTreeXML(
                allFiles: allFiles,
                rootURL: rootURL
            )
            updatedXML = updateFileTreeInXML(updatedXML, newTree: treeXML)
        }

        // Always clean existing user instructions first, then wrap with new ones if provided
        updatedXML = stripExistingUserInstructions(updatedXML)
        
        if !userInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updatedXML = wrapWithUserInstructions(updatedXML, instructions: userInstructions)
        }

        // Calculate token count for final XML
        updatedTokenCount = await TokenizerService.shared.countTokens(updatedXML)

        let duration = Date().timeIntervalSince(startTime)
        logDebug("Incremental update complete", details: "Duration: \(String(format: "%.3fs", duration))")

        return GenerationResult(
            xml: updatedXML,
            tokenCount: updatedTokenCount,
            filesProcessed: addedPaths.count,
            generationTime: duration
        )
    }

    // Helper method to strip existing user instructions from XML
    private func stripExistingUserInstructions(_ xml: String) -> String {
        // Pattern to match userInstructions at the beginning and end of XML
        let pattern = "^<userInstructions>.*?</userInstructions>\\s*\\n*|\\n*\\s*<userInstructions>.*?</userInstructions>\\s*$"
        
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
            let range = NSRange(location: 0, length: xml.utf16.count)
            let result = regex.stringByReplacingMatches(in: xml, options: [], range: range, withTemplate: "")
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            logDebug("Failed to strip user instructions", details: "Error: \(error)")
            return xml
        }
    }

    // Helper method to wrap context XML with user instructions at top and bottom
    private func wrapWithUserInstructions(_ xml: String, instructions: String) -> String {
        let instructionsXML = "<userInstructions>\n\(instructions)\n</userInstructions>\n\n"
        let wrappedXML = instructionsXML + xml + "\n" + instructionsXML
        return wrappedXML
    }

    // Helper method to remove a file section from XML
    func removeFileFromXML(_ xml: String, path: String, rootURL: URL) -> String {
        // Convert absolute path to relative path using the same logic as when adding files
        let relativePath: String
        if path.hasPrefix("/") {
            // This is an absolute path, convert to relative using centralized method
            relativePath = convertToRelativePath(path, rootURL: rootURL)
        } else {
            // Already a relative path
            relativePath = path
        }

        // Escape special regex characters in the path
        let escapedPath = NSRegularExpression.escapedPattern(for: relativePath)

        // Find and remove the file section by matching the Path: line
        // Pattern: <file=filename>...Path: relativePath...content...</file=filename>
        // Note: The closing tag includes the filename, so we need to capture and match it
        let pattern = "  <file=([^>]+)>\\s*\\n  Path: \(escapedPath)\\s*\\n.*?</file=\\1>\\s*\\n"

        do {
            let regex = try NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators)
            let range = NSRange(location: 0, length: xml.utf16.count)
            let result = regex.stringByReplacingMatches(in: xml, options: [], range: range, withTemplate: "")

            // Enhanced logging to help debug path conversion issues
            if result != xml {
                logDebug("File removed from XML", details: "Absolute: \(path) → Relative: \(relativePath)")
            } else {
                logDebug("File removal failed - regex no match", details: "Absolute: \(path) → Relative: \(relativePath)")
                logDebug("Regex pattern used", details: pattern)
                // Additional debug: show what paths are actually in the XML
                let xmlPaths = extractAllPathsFromXML(xml)
                logDebug("Available paths in XML", details: "\(xmlPaths.prefix(10))")
                // Show a snippet of the XML around the expected location
                if let pathLocation = xml.range(of: "Path: \(relativePath)") {
                    let start = xml.index(pathLocation.lowerBound, offsetBy: -50, limitedBy: xml.startIndex) ?? xml.startIndex
                    let end = xml.index(pathLocation.upperBound, offsetBy: 100, limitedBy: xml.endIndex) ?? xml.endIndex
                    let snippet = String(xml[start ..< end])
                    logDebug("XML snippet around target", details: snippet.replacingOccurrences(of: "\n", with: "\\n"))
                }
            }

            return result
        } catch {
            logDebug("File removal failed - regex error", details: "Path: \(relativePath), Error: \(error)")
            return xml
        }
    }

    // Helper method to extract all paths from XML for debugging
    private func extractAllPathsFromXML(_ xml: String) -> [String] {
        let lines = xml.components(separatedBy: .newlines)
        var paths: [String] = []

        for line in lines {
            if line.contains("Path: ") {
                let pathLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                let path = pathLine.replacingOccurrences(of: "  Path: ", with: "")
                paths.append(path)
            }
        }

        return paths
    }

    // Centralized method to convert absolute path to relative path
    // This MUST match the logic used when adding files to ensure consistency
    private func convertToRelativePath(_ absolutePath: String, rootURL: URL) -> String {
        let rootPath = rootURL.path

        // Use the same logic as when adding files to XML
        if absolutePath.hasPrefix(rootPath + "/") {
            return absolutePath.replacingOccurrences(of: rootPath + "/", with: "")
        } else if absolutePath.hasPrefix(rootPath) && absolutePath.count > rootPath.count {
            // Handle case where there's no trailing slash
            return String(absolutePath.dropFirst(rootPath.count + 1))
        } else {
            // Fallback: use just the filename if path doesn't match expected format
            logDebug("Path conversion fallback", details: "Could not convert \(absolutePath) relative to \(rootPath)")
            return URL(fileURLWithPath: absolutePath).lastPathComponent
        }
    }

    // Helper method to insert new files into XML
    func insertFilesIntoXML(_ xml: String, newFilesXML: String) -> String {
        // Insert before </codebase> closing tag
        if let range = xml.range(of: "</codebase>") {
            var result = xml
            result.replaceSubrange(range, with: newFilesXML + "</codebase>")
            return result
        }
        return xml
    }

    // Helper method to update file tree in XML
    private func updateFileTreeInXML(_ xml: String, newTree: String) -> String {
        // Replace existing <fileTree>...</fileTree> section
        let pattern = "  <fileTree>.*?</fileTree>\n"

        if let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) {
            let range = NSRange(location: 0, length: xml.utf16.count)
            return regex.stringByReplacingMatches(in: xml, options: [], range: range, withTemplate: newTree)
        }

        // If no existing tree, insert after <codebase> opening
        if let range = xml.range(of: "<codebase>\n") {
            var result = xml
            let insertPoint = result.index(range.upperBound, offsetBy: 0)
            result.insert(contentsOf: newTree, at: insertPoint)
            return result
        }

        return xml
    }

    // Helper method to generate file tree XML
    private func generateFileTreeXML(
        allFiles: [FileInfo],
        rootURL: URL
    ) -> String {
        // Use all files from the workspace to show complete codebase structure
        // This provides LLMs with better context about available files
        let allPaths = allFiles.map { $0.url.path }

        // Filter out build artifacts before generating tree
        let filteredPaths = filterBuildArtifacts(allPaths)

        // Reuse existing tree generation logic with simple indentation
        let urls = filteredPaths.map { URL(fileURLWithPath: $0) }
        let relative = urls.compactMap { url -> String? in
            let path = url.path(percentEncoded: false)
            if path.hasPrefix(rootURL.path) {
                return String(path.dropFirst(rootURL.path.count + 1))
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

        var treeXML = "  <fileTree>\n"
        for line in tree {
            treeXML.append("    \(line)\n")
        }
        treeXML.append("  </fileTree>\n")

        return treeXML
    }

    /// Clear all caches
    func clearCaches() async {
        logDebug("Clearing all caches")
        await fragmentCache.clear()
        await contentCache.clear()
    }

    /// Get debug logs for troubleshooting
    func getDebugLogs() -> [DebugInfo] {
        return debugLogs
    }

    // MARK: - Private Methods

    /* private func performGeneration(
         rootURL: URL,
         selectedPaths: Set<String>,
         allFiles: [FileInfo],
         includeTree: Bool,
         onProgress: (@Sendable (Double, String) -> Void)?
     ) async throws -> GenerationResult {
         let startTime = Date()
         var timingLog: [String] = []

         // Check memory pressure before starting
         if await isMemoryPressureHigh() {
             throw EngineError.memoryPressure
         }

         // Filter to selected files only
         let filterStart = Date()
         let selectedFiles = allFiles.filter { selectedPaths.contains($0.url.path) }
         timingLog.append("File filtering: \(String(format: "%.3fs", Date().timeIntervalSince(filterStart)))")

         // Start building XML
         await xmlBuilder.reset()
         await xmlBuilder.startDocument()

         // Add file tree if requested
         if includeTree {
             let treeStart = Date()
             let allPaths = allFiles.map { $0.url.path }
             let treeXML = await generateFileTree(root: rootURL, paths: allPaths)
             await xmlBuilder.appendTree(treeXML)
             timingLog.append("File tree generation: \(String(format: "%.3fs", Date().timeIntervalSince(treeStart)))")
         }

         // Process files with concurrency control
         let filesStart = Date()
         let totalFiles = selectedFiles.count
         var processedCount = 0

         try await withThrowingTaskGroup(of: (String, String, Int)?.self) { group in
             // Limit concurrent operations
             var activeCount = 0
             var fileIterator = selectedFiles.makeIterator()

             while let file = fileIterator.next() {
                 // Wait if we've hit concurrency limit
                 while activeCount >= maxConcurrentReads {
                     if let result = try await group.next() {
                         if let (path, xml, _) = result {
                             await xmlBuilder.appendFile(xml)
                             processedCount += 1

                             let progress = Double(processedCount) / Double(totalFiles)
                             if let onProgress = onProgress {
                                 // Call progress directly - UI updates will handle MainActor dispatch if needed
                                 onProgress(progress, "Processing \(URL(fileURLWithPath: path).lastPathComponent)")
                             }
                         }
                         activeCount -= 1
                     }
                 }

                 // Add new task
                 group.addTask {
                     try Task.checkCancellation()
                     return await self.processFile(file)
                 }
                 activeCount += 1
             }

             // Collect remaining results
             for try await result in group {
                 if let (path, xml, _) = result {
                     await xmlBuilder.appendFile(xml)
                     processedCount += 1

                     let progress = Double(processedCount) / Double(totalFiles)
                     if let onProgress = onProgress {
                         // Call progress directly - UI updates will handle MainActor dispatch if needed
                         onProgress(progress, "Processing \(URL(fileURLWithPath: path).lastPathComponent)")
                     }
                 }
             }
         }

         timingLog.append("File processing: \(String(format: "%.3fs", Date().timeIntervalSince(filesStart)))")

         // Finalize XML
         let finalizeStart = Date()
         await xmlBuilder.endDocument()
         let finalXML = await xmlBuilder.build()
         timingLog.append("XML building: \(String(format: "%.3fs", Date().timeIntervalSince(finalizeStart)))")

         // Calculate total tokens using the centralized TokenizerService
         // This provides exact token counts using cl100k_base encoding (GPT-4/GPT-3.5)
         let tokenStart = Date()
         let totalTokens = await TokenizerService.shared.countTokens(finalXML)
         timingLog.append("Token counting: \(String(format: "%.3fs", Date().timeIntervalSince(tokenStart)))")

         let duration = Date().timeIntervalSince(startTime)

         // Log detailed timing breakdown
         print("[Engine Timing Breakdown]")
         for log in timingLog {
             print("  - \(log)")
         }
         print("  Total engine time: \(String(format: "%.3fs", duration))")

         return GenerationResult(
             xml: finalXML,
             tokenCount: totalTokens,
             filesProcessed: processedCount,
             generationTime: duration
         )
     } */

    /* private func processFile(_ file: FileInfo) async -> (String, String, Int)? {
         let path = file.url.path

         // Check fragment cache first
         if let cachedFragment = await fragmentCache.get(path: path) {
             logDebug("Cache hit", details: file.url.lastPathComponent)
             return (path, cachedFragment.xml, cachedFragment.tokens)
         }

         // Check if file is too large
         guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
               let fileSize = attributes[.size] as? Int
         else {
             return nil
         }

         if fileSize > 10 * 1024 * 1024 { // Skip files > 10MB
             logDebug("Skipping large file", details: "\(file.url.lastPathComponent) (\(fileSize) bytes)")
             return nil
         }

         // Try to get content from cache or read from disk
         let content: String
         if let cachedContent = await contentCache.get(path: path) {
             content = cachedContent
         } else {
             // Use async file reading to avoid blocking
             do {
                 content = try await AsyncFileReader.shared.readFile(at: file.url)
             } catch {
                 // Fallback to FileHandle-based reading if URLSession fails
                 do {
                     content = try await AsyncFileReader.shared.readFileWithHandle(at: file.url)
                 } catch {
                     return nil
                 }
             }

             // Cache if small enough
             if fileSize < maxFileSizeForCaching {
                 await contentCache.set(path: path, content: content)
             }
         }

         // Generate XML fragment
         let languageHint = LanguageMap.languageHint(for: file.url)
         let xml = generateFileXML(
             name: file.url.lastPathComponent,
             path: path,
             language: languageHint,
             content: content
         )

         // Calculate tokens using actual tokenization - no estimation
         let tokens = await TokenizerService.shared.countTokens(content)

         // Cache the fragment
         await fragmentCache.set(path: path, xml: xml, tokens: tokens)

         return (path, xml, tokens)
     } */

    private func generateFileXML(name: String, path: String, language: String, content: String) -> String {
        var xml = ""
        xml.append("  <file=\(name)>\n")
        xml.append("  Path: \(path)\n")
        xml.append("  `````\(language)\n")

        // Process content line by line - content should be at same indentation level as XML tags
        content.enumerateLines { line, _ in
            xml.append("  \(line)\n")
        }

        xml.append("  `````\n")
        xml.append("  </file=\(name)>\n")

        return xml
    }

    private func generateFileTree(root: URL, paths: [String]) async -> String {
        // Filter out build artifacts before generating tree
        let filteredPaths = filterBuildArtifacts(paths)

        // Reuse existing tree generation logic with simple indentation
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

        var treeXML = "  <fileTree>\n"
        for line in tree {
            treeXML.append("    \(line)\n")
        }
        treeXML.append("  </fileTree>\n")

        return treeXML
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
                if component.hasSuffix("deps"), pathComponents.contains("target") {
                    return false
                }
            }

            return true
        }
    }

    func extractSelectedPaths(from xml: String) -> Set<String> {
        // Simple extraction of paths from existing XML
        var paths = Set<String>()
        let lines = xml.split(separator: "\n")

        for line in lines {
            if line.contains("Path: ") {
                let path = line.replacingOccurrences(of: "  Path: ", with: "").trimmingCharacters(in: .whitespaces)
                paths.insert(path)
            }
        }

        return paths
    }

    private func isMemoryPressureHigh() async -> Bool {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                          task_flavor_t(MACH_TASK_BASIC_INFO),
                          $0,
                          &count)
            }
        }

        guard result == KERN_SUCCESS else { return false }

        let memoryUsage = Double(info.resident_size)
        let totalMemory = Double(ProcessInfo.processInfo.physicalMemory)
        let usageRatio = memoryUsage / totalMemory

        return usageRatio > 0.8 // 80% threshold
    }

    private func logDebug(_ event: String, details: String? = nil) {
        let info = DebugInfo(timestamp: Date(), event: event, details: details)
        debugLogs.append(info)

        // Trim logs if too many
        if debugLogs.count > maxDebugLogs {
            debugLogs.removeFirst(debugLogs.count - maxDebugLogs)
        }

        #if DEBUG
            let detailsStr = details.map { " - \($0)" } ?? ""
            print("[StreamingContextEngine] \(event)\(detailsStr)")
        #endif
    }
}

// MARK: - Supporting Types

/* /// Incremental XML builder for efficient string operations
 actor IncrementalXMLBuilder {
     private var buffer: String
     private let estimatedCapacity = 1024 * 1024 // 1MB initial capacity

     init() {
         buffer = ""
         buffer.reserveCapacity(estimatedCapacity)
     }

     func reset() {
         buffer = ""
         buffer.reserveCapacity(estimatedCapacity)
     }

     func startDocument() {
         buffer.append("<codebase>\n")
     }

     func endDocument() {
         buffer.append("</codebase>\n")
     }

     func appendTree(_ tree: String) {
         buffer.append(tree)
     }

     func appendFile(_ fileXML: String) {
         buffer.append(fileXML)
     }

     func build() -> String {
         return buffer
     }
 } */

/// LRU cache for XML fragments
actor XMLFragmentCache {
    struct CacheEntry {
        let xml: String
        let tokens: Int
        let timestamp: Date
        let size: Int
    }

    private var cache: [String: CacheEntry] = [:]
    private var accessOrder: [String] = []
    private let maxSize: Int
    private var currentSize: Int = 0

    init(maxSize: Int) {
        self.maxSize = maxSize
    }

    func get(path: String) -> (xml: String, tokens: Int)? {
        guard let entry = cache[path] else { return nil }

        // Update access order
        accessOrder.removeAll { $0 == path }
        accessOrder.append(path)

        return (entry.xml, entry.tokens)
    }

    func set(path: String, xml: String, tokens: Int) {
        let size = xml.utf8.count

        // Remove old entry if exists
        if let oldEntry = cache[path] {
            currentSize -= oldEntry.size
            accessOrder.removeAll { $0 == path }
        }

        // Evict entries if needed
        while currentSize + size > maxSize, !accessOrder.isEmpty {
            let pathToEvict = accessOrder.removeFirst()
            if let entry = cache.removeValue(forKey: pathToEvict) {
                currentSize -= entry.size
            }
        }

        // Add new entry
        let entry = CacheEntry(xml: xml, tokens: tokens, timestamp: Date(), size: size)
        cache[path] = entry
        accessOrder.append(path)
        currentSize += size
    }

    func clear() {
        cache.removeAll()
        accessOrder.removeAll()
        currentSize = 0
    }
}

/// LRU cache for file contents
actor FileContentCache {
    struct CacheEntry {
        let content: String
        let timestamp: Date
        let size: Int
    }

    private var cache: [String: CacheEntry] = [:]
    private var accessOrder: [String] = []
    private let maxSize: Int
    private var currentSize: Int = 0

    init(maxSize: Int) {
        self.maxSize = maxSize
    }

    func get(path: String) -> String? {
        guard let entry = cache[path] else { return nil }

        // Update access order
        accessOrder.removeAll { $0 == path }
        accessOrder.append(path)

        return entry.content
    }

    func set(path: String, content: String) {
        let size = content.utf8.count

        // Don't cache if too large
        if size > maxSize / 4 { return }

        // Remove old entry if exists
        if let oldEntry = cache[path] {
            currentSize -= oldEntry.size
            accessOrder.removeAll { $0 == path }
        }

        // Evict entries if needed
        while currentSize + size > maxSize, !accessOrder.isEmpty {
            let pathToEvict = accessOrder.removeFirst()
            if let entry = cache.removeValue(forKey: pathToEvict) {
                currentSize -= entry.size
            }
        }

        // Add new entry
        let entry = CacheEntry(content: content, timestamp: Date(), size: size)
        cache[path] = entry
        accessOrder.append(path)
        currentSize += size
    }

    func clear() {
        cache.removeAll()
        accessOrder.removeAll()
        currentSize = 0
    }
}
