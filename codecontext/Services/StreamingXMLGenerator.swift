import Foundation

// MARK: - Errors

enum XMLGenerationError: Error {
    case tooManyFiles(count: Int, max: Int)
    case memoryPressure
    case cancelled
    case fileReadError(URL, any Error)
    
    var localizedDescription: String {
        switch self {
        case .tooManyFiles(let count, let max):
            return "Too many files selected (\(count)). Maximum supported: \(max) files."
        case .memoryPressure:
            return "System memory pressure is too high. Please close other applications and try again."
        case .cancelled:
            return "XML generation was cancelled."
        case .fileReadError(let url, let error):
            return "Failed to read file \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }
}

/// High-performance XML generator using streaming and async patterns
/// Designed to handle 200k+ tokens without memory issues or UI blocking
actor StreamingXMLGenerator {
    
    // MARK: - Types
    
    struct Progress {
        let current: Int
        let total: Int
        let currentFile: String
        let bytesProcessed: Int64
        
        var percentage: Double {
            guard total > 0 else { return 0 }
            return Double(current) / Double(total) * 100
        }
    }
    
    struct Configuration {
        let maxConcurrentReads: Int = 8
        let chunkSize: Int = 10 * 1024 // 10KB chunks
        let maxFileSizeBytes: Int64 = 10 * 1024 * 1024 // 10MB
        let maxTotalFiles: Int = 10_000
        let memoryPressureThreshold: Double = 0.8 // 80% memory usage
    }
    
    // MARK: - Properties
    
    private let config = Configuration()
    private var isCancelled = false
    
    // MARK: - Initialization
    
    init() {
        // No initialization needed
    }
    
    // MARK: - Public Methods
    
    /// Cancel the current generation
    func cancel() {
        isCancelled = false
    }
    
    /// Generate XML using streaming approach with backpressure control
    func generateStreaming(
        codebaseRoot: URL,
        files: [FileInfo],
        selectedPaths: Set<String>,
        includeTree: Bool,
        onProgress: @escaping @Sendable (Progress) -> Void
    ) async throws -> String {
        
        // Reset cancellation state
        isCancelled = false
        
        // Filter selected files
        let selectedFiles = files.filter { selectedPaths.contains($0.url.path) }
        
        // Validate file count
        guard selectedFiles.count <= config.maxTotalFiles else {
            throw XMLGenerationError.tooManyFiles(count: selectedFiles.count, max: config.maxTotalFiles)
        }
        
        // Check memory pressure before starting
        if await isMemoryPressureHigh() {
            throw XMLGenerationError.memoryPressure
        }
        
        // Create XML stream writer
        let xmlWriter = XMLStreamWriter()
        
        // Start XML document
        await xmlWriter.startDocument(codebaseRoot: codebaseRoot)
        
        // Add file tree if requested
        if includeTree {
            let allPaths = files.map { $0.url.path }
            await xmlWriter.writeFileTree(root: codebaseRoot, paths: allPaths)
        }
        
        // Process files with streaming
        let total = selectedFiles.count
        
        // Process files sequentially for better memory management and progress tracking
        var processedCount = 0
        var totalBytesProcessed: Int64 = 0
        
        for file in selectedFiles {
            // Check cancellation
            if isCancelled {
                throw XMLGenerationError.cancelled
            }
            
            // Process file with streaming
            let fileBytes = try await processFileStreaming(
                file: file,
                xmlWriter: xmlWriter
            )
            
            processedCount += 1
            totalBytesProcessed += fileBytes
            
            // Update progress on main actor
            await MainActor.run {
                onProgress(Progress(
                    current: processedCount,
                    total: total,
                    currentFile: file.url.lastPathComponent,
                    bytesProcessed: totalBytesProcessed
                ))
            }
            
            // Yield periodically to prevent blocking
            if processedCount % 10 == 0 {
                await Task.yield()
                
                // Check memory pressure periodically
                if await isMemoryPressureHigh() {
                    throw XMLGenerationError.memoryPressure
                }
            }
        }
        
        // Finalize XML document
        await xmlWriter.endDocument()
        
        // Return the complete XML
        return await xmlWriter.getOutput()
    }
    
    // MARK: - Private Methods
    
    /// Process a single file using streaming approach
    private func processFileStreaming(
        file: FileInfo,
        xmlWriter: XMLStreamWriter
    ) async throws -> Int64 {
        
        // Check file size
        let fileSize = try getFileSize(url: file.url)
        guard fileSize <= config.maxFileSizeBytes else {
            // Skip large files gracefully
            return 0
        }
        
        // Determine language hint
        let languageHint = LanguageMap.languageHint(for: file.url)
        
        // Start file element
        await xmlWriter.startFile(
            name: file.url.lastPathComponent,
            path: file.url.path,
            language: languageHint
        )
        
        // Stream file content in chunks
        let handle = try FileHandle(forReadingFrom: file.url)
        defer { try? handle.close() }
        
        var totalBytes: Int64 = 0
        
        while !isCancelled {
            autoreleasepool {
                // Read chunk
                let chunk = handle.readData(ofLength: config.chunkSize)
                
                // Check if we're done
                guard !chunk.isEmpty else { return }
                
                // Convert to string and write
                if let chunkString = String(data: chunk, encoding: .utf8) {
                    Task {
                        await xmlWriter.writeContent(chunkString)
                    }
                    totalBytes += Int64(chunk.count)
                }
            }
            
            // Break if no more data
            if handle.availableData.isEmpty {
                break
            }
        }
        
        // End file element
        await xmlWriter.endFile()
        
        return totalBytes
    }
    
    /// Get file size safely
    private func getFileSize(url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }
    
    /// Check if memory pressure is high
    private func isMemoryPressureHigh() async -> Bool {
        // Get memory info
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
        
        // Check if we're using more than threshold of available memory
        let memoryUsage = Double(info.resident_size)
        let totalMemory = Double(ProcessInfo.processInfo.physicalMemory)
        let usageRatio = memoryUsage / totalMemory
        
        return usageRatio > config.memoryPressureThreshold
    }
}

// MARK: - XML Stream Writer

/// Efficient XML writer that builds output incrementally
actor XMLStreamWriter {
    private var output: String = ""
    private let indentLevel = 2
    
    init() {
        // Reserve initial capacity for better performance
        output.reserveCapacity(1024 * 1024) // 1MB initial capacity
    }
    
    func startDocument(codebaseRoot: URL) {
        output.append("<codebase>\n")
    }
    
    func endDocument() {
        output.append("</codebase>\n")
    }
    
    func writeFileTree(root: URL, paths: [String]) {
        output.append("  <fileTree>\n")
        
        // Build tree structure efficiently
        let tree = buildTreeStructure(root: root, paths: paths)
        for line in tree {
            output.append("    ")
            output.append(line)
            output.append("\n")
        }
        
        output.append("  </fileTree>\n")
    }
    
    func startFile(name: String, path: String, language: String) {
        output.append("  <file=\(name)>\n")
        output.append("  Path: \(path)\n")
        output.append("  `````\(language)\n")
    }
    
    func writeContent(_ content: String) {
        // Process content line by line for proper indentation
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines {
            output.append("  ")
            output.append(String(line))
            output.append("\n")
        }
    }
    
    func endFile() {
        output.append("  `````\n")
        output.append("  </file>\n")
    }
    
    func getOutput() -> String {
        return output
    }
    
    private func buildTreeStructure(root: URL, paths: [String]) -> [String] {
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
        
        func add(prefix: String, items: [[String]]) {
            let grouped = Dictionary(grouping: items) { $0.first ?? "" }
            let keys = grouped.keys.sorted()
            
            for (i, key) in keys.enumerated() {
                let isLast = i == keys.count - 1
                let stem = prefix + (isLast ? "└─ " : "├─ ") + key
                tree.append(stem)
                
                let children = grouped[key]!.map { Array($0.dropFirst()) }.filter { !$0.isEmpty }
                if !children.isEmpty {
                    add(prefix: prefix + (isLast ? "   " : "│  "), items: children)
                }
            }
        }
        
        add(prefix: "", items: components)
        return tree
    }
}