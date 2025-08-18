import Foundation
import SwiftData

@MainActor
final class WorkspaceEngine {
    private let scanner = FileScanner()
    private let xml = XMLFormatterService()
    private let progressiveGenerator = ProgressiveXMLGenerator()
    private let streamingGenerator = StreamingXMLGenerator()
    private let notificationSystem: NotificationSystem

    // Callback for when workspace content changes
    var onContentChange: (() -> Void)?

    // Cache for token counts to avoid re-tokenizing
    private var tokenCache: [URL: Int] = [:]

    // Cache the last generation result for comparison
    private var lastOutput: Output?
    private var lastGenerationFiles: Set<URL> = []

    // Override files that were manually included despite exclusions
    private var overrideFiles: Set<URL> = []

    init(notificationSystem: NotificationSystem = NotificationSystem()) {
        self.notificationSystem = notificationSystem

        // Listen for file inclusion requests
        NotificationCenter.default.addObserver(
            forName: .includeExcludedFiles,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let urls = notification.object as? [URL] {
                Task { @MainActor in
                    self?.overrideFiles.formUnion(urls)
                }
            }
        }
    }

    struct Output: Equatable {
        let xml: String
        let totalTokens: Int

        static func == (lhs: Output, rhs: Output) -> Bool {
            return lhs.xml == rhs.xml && lhs.totalTokens == rhs.totalTokens
        }
    }

    func generateWithProgress(
        for workspace: SDWorkspace,
        modelContext _: ModelContext,
        includeTree: Bool,
        onProgress: @escaping @Sendable (Int, Int) -> Void
    ) async -> Output? {
        guard let root = resolveURL(from: workspace) else { return nil }

        let rules = IgnoreRules(
            respectGitIgnore: workspace.respectGitIgnore,
            respectDotIgnore: workspace.respectDotIgnore,
            showHiddenFiles: workspace.showHiddenFiles,
            excludeNodeModules: workspace.excludeNodeModules,
            excludeGit: workspace.excludeGit,
            excludeBuild: workspace.excludeBuild,
            excludeDist: workspace.excludeDist,
            excludeNext: workspace.excludeNext,
            excludeVenv: workspace.excludeVenv,
            excludeDSStore: workspace.excludeDSStore,
            excludeDerivedData: workspace.excludeDerivedData,
            customPatterns: workspace.customIgnore.split(separator: "\n").map(String.init),
            rootPath: root.path
        )

        // Parse selected files
        let selectedFilePaths: Set<String>
        if let selectionData = workspace.selectionJSON.data(using: .utf8),
           let decodedPaths = try? JSONDecoder().decode(Set<String>.self, from: selectionData)
        {
            selectedFilePaths = decodedPaths
        } else {
            selectedFilePaths = Set()
        }

        // Quick return if no files selected
        guard !selectedFilePaths.isEmpty else {
            return Output(xml: "No files selected. Please select files from the sidebar.", totalTokens: 0)
        }

        let options = FileScanner.Options(
            ignoreRules: rules,
            enableExclusionDetection: true,
            allowOverrides: overrideFiles
        )
        let scanResult = scanner.scanWithExclusions(root: root, options: options)

        // Use streaming generator - commit fully to optimized approach
        do {
            let xmlString = try await streamingGenerator.generateStreaming(
                codebaseRoot: root,
                files: scanResult.includedFiles,
                selectedPaths: selectedFilePaths,
                includeTree: includeTree
            ) { progress in
                onProgress(progress.current, progress.total)
            }

            let tokenCount = await TokenizerService.shared.countTokens(xmlString)
            return Output(xml: xmlString, totalTokens: tokenCount)
        } catch {
            // Log the error and return nil instead of falling back
            print("Streaming generation failed: \(error). Fix the streaming implementation rather than using fallback.")
            return nil
        }
    }

    func generate(for workspace: SDWorkspace, modelContext _: ModelContext, includeTree: Bool) async -> Output? {
        guard let root = resolveURL(from: workspace) else { return nil }

        let rules = IgnoreRules(
            respectGitIgnore: workspace.respectGitIgnore,
            respectDotIgnore: workspace.respectDotIgnore,
            showHiddenFiles: workspace.showHiddenFiles,
            excludeNodeModules: workspace.excludeNodeModules,
            excludeGit: workspace.excludeGit,
            excludeBuild: workspace.excludeBuild,
            excludeDist: workspace.excludeDist,
            excludeNext: workspace.excludeNext,
            excludeVenv: workspace.excludeVenv,
            excludeDSStore: workspace.excludeDSStore,
            excludeDerivedData: workspace.excludeDerivedData,
            customPatterns: workspace.customIgnore.split(separator: "\n").map(String.init),
            rootPath: root.path
        )
        // Parse selected files from workspace
        let selectedFilePaths: Set<String>
        if let selectionData = workspace.selectionJSON.data(using: .utf8),
           let decodedPaths = try? JSONDecoder().decode(Set<String>.self, from: selectionData)
        {
            selectedFilePaths = decodedPaths
        } else {
            selectedFilePaths = Set()
        }

        let options = FileScanner.Options(
            ignoreRules: rules,
            enableExclusionDetection: true,
            allowOverrides: overrideFiles
        )
        let scanResult = scanner.scanWithExclusions(root: root, options: options)
        let allFiles = scanResult.includedFiles.filter { !$0.isDirectory }

        // Show notification if there were exclusions
        if !scanResult.exclusions.isEmpty {
            notificationSystem.showExclusionNotification(exclusions: scanResult.exclusions)
        }

        // Keep track of all file paths for the full tree
        let allFilePaths = scanResult.includedFiles.map { $0.url.path }

        // Filter to only include selected files for content
        let files = allFiles.filter { selectedFilePaths.contains($0.url.path) }

        // Prevent hanging on too many files
        guard files.count <= AppConfiguration.maxProcessableFiles else {
            return Output(xml: "Too many files selected (\(files.count)). Please select fewer files.", totalTokens: 0)
        }

        var entries: [XMLFormatterService.FileEntry] = []

        // Process files in smaller batches with better memory management
        let batchSize = 5 // Smaller batches to reduce memory pressure
        let batches = files.chunked(into: batchSize)

        for batch in batches {
            await withTaskGroup(of: XMLFormatterService.FileEntry?.self) { group in
                for file in batch {
                    group.addTask {
                        await self.processFileAsync(file)
                    }
                }

                // Collect results from the batch
                for await entry in group {
                    if let entry = entry {
                        entries.append(entry)
                    }
                }
            }

            // Yield control to prevent blocking and allow memory cleanup
            await Task.yield()
        }

        let rendered = xml.render(codebaseRoot: root, files: entries, includeTree: includeTree, allFilePaths: allFilePaths)

        // Use actual tokenization with cl100k_base encoding
        let xmlTokens = await TokenizerService.shared.countTokens(rendered)

        let output = Output(xml: rendered, totalTokens: xmlTokens)

        // Don't notify of content changes to avoid infinite loops
        // The view will handle regeneration based on specific triggers

        // Update cache
        lastOutput = output
        lastGenerationFiles = Set(files.map { $0.url })

        return output
    }

    private func resolveURL(from workspace: SDWorkspace) -> URL? {
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: workspace.bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
            return url
        } catch {
            return nil
        }
    }

    /// Generate output from selected files in FileTreeModel
    func generateFromFileTree(_ fileTreeModel: FileTreeModel, includeTree: Bool) async -> Output? {
        guard let root = fileTreeModel.rootNode?.url else { return nil }

        let selectedFiles = await fileTreeModel.rootNode?.getSelectedFiles() ?? []
        guard !selectedFiles.isEmpty else {
            return Output(xml: "No files selected", totalTokens: 0)
        }

        // Get all file paths from the tree for the full structure
        let allFilePaths = getAllFilePaths(from: fileTreeModel.rootNode)

        var entries: [XMLFormatterService.FileEntry] = []
        var totalTokens = 0

        for fileNode in selectedFiles {
            guard let data = try? Data(contentsOf: fileNode.url),
                  let content = String(data: data, encoding: .utf8) else { continue }

            let entry = XMLFormatterService.FileEntry(
                displayName: fileNode.url.lastPathComponent,
                absolutePath: fileNode.url.path,
                languageHint: LanguageMap.languageHint(for: fileNode.url),
                contents: content
            )
            entries.append(entry)
            totalTokens += fileNode.tokenCount
        }

        let rendered = xml.render(codebaseRoot: root, files: entries, includeTree: includeTree, allFilePaths: allFilePaths)

        // Use actual tokenization with cl100k_base encoding
        let xmlTokens = await TokenizerService.shared.countTokens(rendered)

        let output = Output(xml: rendered, totalTokens: xmlTokens)

        // Check if content has changed
        let currentFiles = Set(selectedFiles.map { $0.url })
        let contentChanged = lastOutput != output || lastGenerationFiles != currentFiles

        // Update cache
        lastOutput = output
        lastGenerationFiles = currentFiles

        // Notify if content changed
        if contentChanged {
            onContentChange?()
        }

        return output
    }

    // MARK: - Private Helper Methods

    /// Get all file paths from the file tree recursively
    private func getAllFilePaths(from node: FileNode?) -> [String] {
        guard let node = node else { return [] }

        var paths: [String] = []

        func collectPaths(from currentNode: FileNode) {
            paths.append(currentNode.url.path)
            for child in currentNode.children {
                collectPaths(from: child)
            }
        }

        collectPaths(from: node)
        return paths
    }

    /// Process a single file asynchronously with proper memory management
    private func processFileAsync(_ file: FileInfo) async -> XMLFormatterService.FileEntry? {
        // Skip very large files to avoid memory issues
        let attrs = try? FileManager.default.attributesOfItem(atPath: file.url.path)
        let fileSize = (attrs?[.size] as? Int) ?? 0

        guard fileSize < AppConfiguration.maxFileSizeBytes else { // Skip files exceeding size limit
            print("Skipping large file: \(file.url.lastPathComponent) (\(fileSize) bytes)")
            return nil
        }

        return autoreleasepool {
            guard let data = try? Data(contentsOf: file.url),
                  let content = String(data: data, encoding: .utf8)
            else {
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

    /// Process a FileNode asynchronously with proper memory management
    private func processFileNodeAsync(_ fileNode: FileNode) async -> (XMLFormatterService.FileEntry?, Int) {
        return autoreleasepool {
            guard let data = try? Data(contentsOf: fileNode.url),
                  let content = String(data: data, encoding: .utf8)
            else {
                return (nil, 0)
            }

            let entry = XMLFormatterService.FileEntry(
                displayName: fileNode.url.lastPathComponent,
                absolutePath: fileNode.url.path,
                languageHint: LanguageMap.languageHint(for: fileNode.url),
                contents: content
            )

            return (entry, fileNode.tokenCount)
        }
    }
}
