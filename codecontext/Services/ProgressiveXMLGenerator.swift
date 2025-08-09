import Foundation

/// Generates XML progressively to avoid blocking the main thread
@MainActor
final class ProgressiveXMLGenerator {
    
    struct Progress {
        let current: Int
        let total: Int
        let percentage: Double
        
        var isComplete: Bool { current >= total }
    }
    
    private let xml = XMLFormatterService()
    private var isCancelled = false
    private var currentTask: Task<Void, Never>?
    private var processedEntries: [XMLFormatterService.FileEntry] = []
    
    /// Cancel the current generation and clean up resources
    func cancel() {
        isCancelled = true
        currentTask?.cancel()
        
        // Clean up processed entries to free memory
        processedEntries.removeAll()
        
        // Reset state
        currentTask = nil
    }
    
    /// Generate XML progressively with progress updates
    func generateProgressive(
        codebaseRoot: URL,
        files: [FileInfo],
        selectedPaths: Set<String>,
        includeTree: Bool,
        maxFiles: Int = AppConfiguration.maxProgressiveXMLFiles,
        onProgress: @escaping (Progress) -> Void
    ) async -> String? {
        
        isCancelled = false
        
        // Filter to selected files only
        let selectedFiles = files.filter { selectedPaths.contains($0.url.path) }
        
        // Check if too many files
        guard selectedFiles.count <= maxFiles else {
            return """
            <error>
            Too many files selected (\(selectedFiles.count)).
            Maximum supported: \(maxFiles) files.
            Please select fewer files or use filters to reduce the selection.
            </error>
            """
        }
        
        var entries: [XMLFormatterService.FileEntry] = []
        let total = selectedFiles.count
        
        // Process files in small batches
        let batchSize = AppConfiguration.processingBatchSize
        for (index, file) in selectedFiles.enumerated() {
            // Check cancellation
            if isCancelled {
                return nil
            }
            
            // Update progress
            let progress = Progress(
                current: index + 1,
                total: total,
                percentage: Double(index + 1) / Double(total) * 100
            )
            onProgress(progress)
            
            // Process file
            if let entry = await processFile(file) {
                entries.append(entry)
            }
            
            // Yield periodically to keep UI responsive
            if index % batchSize == 0 {
                await Task.yield()
            }
        }
        
        // Check final cancellation
        if isCancelled {
            return nil
        }
        
        // Generate final XML with all file paths for the tree
        let allPaths = files.map { $0.url.path }
        return xml.render(codebaseRoot: codebaseRoot, files: entries, includeTree: includeTree, allFilePaths: allPaths)
    }
    
    /// Process a single file asynchronously with proper memory management
    private func processFile(_ file: FileInfo) async -> XMLFormatterService.FileEntry? {
        // Check cancellation
        if isCancelled || Task.isCancelled {
            return nil
        }
        
        // Skip large files
        let attrs = try? FileManager.default.attributesOfItem(atPath: file.url.path)
        let fileSize = (attrs?[.size] as? Int) ?? 0
        
        guard fileSize < AppConfiguration.maxFileSizeBytesForXMLGeneration else { // Size limit for XML generation
            print("Skipping large file for XML: \(file.url.lastPathComponent) (\(fileSize) bytes)")
            return nil
        }
        
        return autoreleasepool {
            // Read file content
            guard let data = try? Data(contentsOf: file.url),
                  let content = String(data: data, encoding: .utf8) else {
                return nil
            }
            
            return XMLFormatterService.FileEntry(
                displayName: file.url.lastPathComponent,
                absolutePath: file.url.path,
                languageHint: LanguageMap.languageHint(for: file.url),
                contents: content
            )
        }
    }
}