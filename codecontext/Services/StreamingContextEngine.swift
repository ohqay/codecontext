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
    
    // File tree caching to avoid unnecessary regeneration
    private var cachedFileTreeXML: String?
    private var cachedFileTreeHash: String?

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
            }

            // Insert new files before closing </codebase> tag
            updatedXML = insertFilesIntoXML(updatedXML, newFilesXML: newFilesXML)
        }

        // Update file tree if needed
        if includeTree {
            logDebug("Generating file tree", details: "allFiles.count: \(allFiles.count)")
            let xmlBeforeTree = updatedXML
            let treeXML = generateFileTreeXML(
                allFiles: allFiles,
                rootURL: rootURL
            )
            logDebug("Generated tree XML", details: "Length: \(treeXML.count), Content preview: \(treeXML.prefix(200))")
            updatedXML = updateFileTreeInXML(updatedXML, newTree: treeXML)
            logDebug("After tree insertion", details: "XML changed: \(xmlBeforeTree != updatedXML), New length: \(updatedXML.count)")
        } else {
            logDebug("Skipping file tree generation", details: "includeTree is false")
        }

        // Always clean existing user instructions first, then wrap with new ones if provided
        updatedXML = stripExistingUserInstructions(updatedXML)

        if !userInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updatedXML = wrapWithUserInstructions(updatedXML, instructions: userInstructions)
        }

        // Calculate token count for final XML
        updatedTokenCount = await TokenizerService.shared.countTokens(updatedXML)
        
        // Validate the final XML for file tree issues
        validateFileTreeInXML(updatedXML)

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
        // Use BoundaryManager to safely remove all user instruction sections
        return BoundaryManager.remove(xml, type: .userInstructions)
    }

    // Helper method to wrap context XML with user instructions at top and bottom
    private func wrapWithUserInstructions(_ xml: String, instructions: String) -> String {
        let instructionsXML = "<userInstructions>\n\(instructions)\n</userInstructions>"
        
        // Wrap instructions with boundary markers
        let topInstructions = BoundaryManager.wrap(instructionsXML, type: .userInstructions)
        let bottomInstructions = BoundaryManager.wrap(instructionsXML, type: .userInstructions)
        
        // Wrap the entire codebase section with boundaries
        let codebaseContent = "<codebase>\n\(xml)\n</codebase>"
        let wrappedCodebase = BoundaryManager.wrap(codebaseContent, type: .codebase)
        
        return "\(topInstructions)\n\n\(wrappedCodebase)\n\n\(bottomInstructions)\n"
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

        // Extract all file sections using BoundaryManager
        let fileContents = BoundaryManager.extract(xml, type: .file)
        var result = xml
        
        // Find and remove the matching file section
        for fileContent in fileContents {
            let pathLine = "  Path: \(relativePath)"
            if fileContent.contains(pathLine) {
                // Found the file to remove - remove this specific boundary section
                let wrappedFile = BoundaryManager.wrap(fileContent, type: .file)
                result = result.replacingOccurrences(of: wrappedFile, with: "")
                logDebug("File removed from XML", details: "Absolute: \(path) → Relative: \(relativePath)")
                return result
            }
        }
        
        logDebug("File removal failed - file section not found", details: "Absolute: \(path) → Relative: \(relativePath)")
        return xml
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
        logDebug("updateFileTreeInXML", details: "Input XML length: \(xml.count), newTree length: \(newTree.count)")

        // First, remove ALL existing file trees to prevent duplication
        let cleanedXML = removeAllFileTreesFromXML(xml)
        let removedCount = (xml.components(separatedBy: "<fileTree>").count - 1) - (cleanedXML.components(separatedBy: "<fileTree>").count - 1)
        if removedCount > 0 {
            logDebug("Removed existing file trees", details: "Count: \(removedCount)")
        }

        // Then insert the new file tree after <codebase> opening
        if let range = cleanedXML.range(of: "<codebase>\n") {
            var result = cleanedXML
            let insertPoint = result.index(range.upperBound, offsetBy: 0)
            result.insert(contentsOf: newTree, at: insertPoint)
            logDebug("Inserted new file tree", details: "Result length: \(result.count)")
            return result
        } else {
            logDebug("Could not find <codebase>\\n in XML", details: "XML preview: \(cleanedXML.prefix(100))")
        }

        logDebug("File tree insertion failed", details: "Returning cleaned XML without new tree")
        return cleanedXML
    }
    
    // Helper method to remove ALL file tree sections from XML
    private func removeAllFileTreesFromXML(_ xml: String) -> String {
        // Use BoundaryManager to safely remove all file tree sections
        return BoundaryManager.remove(xml, type: .fileTree)
    }

    // Helper method to generate file tree XML with caching
    private func generateFileTreeXML(
        allFiles: [FileInfo],
        rootURL: URL
    ) -> String {
        // Use all files from the workspace to show complete codebase structure
        // This provides LLMs with better context about available files
        let allPaths = allFiles.map { $0.url.path }
        logDebug("File tree generation", details: "allPaths.count: \(allPaths.count), rootURL: \(rootURL.path)")

        // Filter out build artifacts before generating tree
        let filteredPaths = filterBuildArtifacts(allPaths)
        logDebug("After filtering artifacts", details: "filteredPaths.count: \(filteredPaths.count)")
        
        // Create hash of the file structure for caching
        let fileStructureHash = computeFileStructureHash(filteredPaths: filteredPaths, rootURL: rootURL)
        
        // Check if we have a cached version with the same structure
        if let cachedHash = cachedFileTreeHash,
           let cachedXML = cachedFileTreeXML,
           cachedHash == fileStructureHash {
            logDebug("Using cached file tree", details: "Hash: \(fileStructureHash.prefix(8))...")
            return cachedXML
        }
        
        logDebug("Generating new file tree", details: "Hash changed or no cache")
        let newTreeXML = generateFileTreeXMLInternal(filteredPaths: filteredPaths, rootURL: rootURL)
        
        // Cache the result
        cachedFileTreeXML = newTreeXML
        cachedFileTreeHash = fileStructureHash
        
        return newTreeXML
    }
    
    // Helper method to compute deterministic hash of file structure for caching
    private func computeFileStructureHash(filteredPaths: [String], rootURL: URL) -> String {
        let sortedPaths = filteredPaths.sorted()
        let combinedString = sortedPaths.joined(separator: "\n") + "\n" + rootURL.path
        
        // Use a deterministic hash that remains consistent across app launches
        return deterministicHash(of: combinedString)
    }
    
    // Helper method to compute deterministic hash using simple but stable algorithm
    private func deterministicHash(of string: String) -> String {
        // Use FNV-1a hash algorithm for deterministic hashing
        let fnvPrime: UInt64 = 1099511628211
        var hash: UInt64 = 14695981039346656037
        
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash.multipliedReportingOverflow(by: fnvPrime).partialValue
        }
        
        return String(hash)
    }
    
    // Internal method that actually generates the file tree XML
    private func generateFileTreeXMLInternal(filteredPaths: [String], rootURL: URL) -> String {

        // Reuse existing tree generation logic with simple indentation
        let urls = filteredPaths.map { URL(fileURLWithPath: $0) }
        let relative = urls.compactMap { url -> String? in
            let path = url.path(percentEncoded: false)
            if path.hasPrefix(rootURL.path) {
                return String(path.dropFirst(rootURL.path.count + 1))
            }
            return nil
        }
        logDebug("After converting to relative paths", details: "relative.count: \(relative.count), sample paths: \(relative.prefix(5))")

        let components = relative.map { $0.split(separator: "/").map(String.init) }
        var tree: [String] = []

        func add(level: Int, items: [[String]]) {
            let grouped = Dictionary(grouping: items) { $0.first ?? "" }
            
            // Separate directories from files
            let allKeys = grouped.keys
            var directories: [String] = []
            var files: [String] = []
            
            for key in allKeys {
                let children = grouped[key]!.map { Array($0.dropFirst()) }.filter { !$0.isEmpty }
                if !children.isEmpty {
                    directories.append(key)
                } else {
                    files.append(key)
                }
            }
            
            // Sort directories and files separately, then combine with directories first
            let sortedDirectories = directories.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            let sortedFiles = files.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            let sortedKeys = sortedDirectories + sortedFiles

            for key in sortedKeys {
                // Use simple indentation instead of Unicode tree characters
                let indentation = String(repeating: "  ", count: level)
                let children = grouped[key]!.map { Array($0.dropFirst()) }.filter { !$0.isEmpty }
                let isDirectory = !children.isEmpty
                
                // Add trailing slash for directories
                let displayName = isDirectory ? key + "/" : key
                let stem = indentation + displayName
                tree.append(stem)

                if isDirectory {
                    add(level: level + 1, items: children)
                }
            }
        }

        add(level: 0, items: components)

        var treeContent = "  <fileTree>\n"
        for line in tree {
            treeContent.append("    \(line)\n")
        }
        treeContent.append("  </fileTree>\n")

        logDebug("Final file tree", details: "tree.count: \(tree.count), treeContent.count: \(treeContent.count)")
        
        // Wrap with boundary markers for safe parsing
        return BoundaryManager.wrap(treeContent, type: .fileTree)
    }

    /// Clear all caches
    func clearCaches() async {
        logDebug("Clearing all caches")
        await fragmentCache.clear()
        await contentCache.clear()
        clearFileTreeCache()
    }
    
    /// Clear only the file tree cache (useful when workspace structure changes)
    func clearFileTreeCache() {
        cachedFileTreeXML = nil
        cachedFileTreeHash = nil
        logDebug("Cleared file tree cache")
    }
    
    /// Validate XML for file tree issues and log warnings
    private func validateFileTreeInXML(_ xml: String) {
        let fileTreeCount = xml.components(separatedBy: "<fileTree>").count - 1
        
        if fileTreeCount > 1 {
            logDebug("WARNING: Multiple file trees detected", details: "Count: \(fileTreeCount) - this may cause token count inflation")
        } else if fileTreeCount == 1 {
            logDebug("File tree validation passed", details: "Exactly 1 file tree found")
        } else {
            logDebug("File tree validation", details: "No file trees found")
        }
    }
    
    /// Clean up duplicate file trees in existing XML (recovery mechanism)
    func cleanupDuplicateFileTrees(in xml: String) -> String {
        let originalCount = xml.components(separatedBy: "<fileTree>").count - 1
        
        if originalCount <= 1 {
            return xml // No duplicates to clean up
        }
        
        logDebug("Cleaning up duplicate file trees", details: "Original count: \(originalCount)")
        
        // Remove all file trees, then we'll add back just one if needed
        let cleanedXML = removeAllFileTreesFromXML(xml)
        
        logDebug("Duplicate file trees removed", details: "Cleaned \(originalCount) duplicates")
        return cleanedXML
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
        var fileContent = ""
        fileContent.append("  <file=\(name)>\n")
        fileContent.append("  Path: \(path)\n")
        fileContent.append("  `````\(language)\n")

        // Process content line by line - content should be at same indentation level as XML tags
        content.enumerateLines { line, _ in
            fileContent.append("  \(line)\n")
        }

        fileContent.append("  `````\n")
        fileContent.append("  </file=\(name)>\n")

        // Wrap with boundary markers for safe parsing
        return BoundaryManager.wrap(fileContent, type: .file)
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
            
            // Separate directories from files
            let allKeys = grouped.keys
            var directories: [String] = []
            var files: [String] = []
            
            for key in allKeys {
                let children = grouped[key]!.map { Array($0.dropFirst()) }.filter { !$0.isEmpty }
                if !children.isEmpty {
                    directories.append(key)
                } else {
                    files.append(key)
                }
            }
            
            // Sort directories and files separately, then combine with directories first
            let sortedDirectories = directories.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            let sortedFiles = files.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            let sortedKeys = sortedDirectories + sortedFiles

            for key in sortedKeys {
                // Use simple indentation instead of Unicode tree characters
                let indentation = String(repeating: "  ", count: level)
                let children = grouped[key]!.map { Array($0.dropFirst()) }.filter { !$0.isEmpty }
                let isDirectory = !children.isEmpty
                
                // Add trailing slash for directories
                let displayName = isDirectory ? key + "/" : key
                let stem = indentation + displayName
                tree.append(stem)

                if isDirectory {
                    add(level: level + 1, items: children)
                }
            }
        }

        add(level: 0, items: components)

        var treeContent = "  <fileTree>\n"
        for line in tree {
            treeContent.append("    \(line)\n")
        }
        treeContent.append("  </fileTree>\n")

        // Wrap with boundary markers for safe parsing
        return BoundaryManager.wrap(treeContent, type: .fileTree)
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
