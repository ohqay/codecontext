import Foundation
import SwiftData

@MainActor
final class WorkspaceEngine {
    private let tokenizer: Tokenizer
    private let scanner = FileScanner()
    private let xml = XMLFormatterService()
    private let notificationSystem: NotificationSystem
    
    // Callback for when workspace content changes
    var onContentChange: (() -> Void)?
    
    // Cache the last generation result for comparison
    private var lastOutput: Output?
    private var lastGenerationFiles: Set<URL> = []
    
    // Override files that were manually included despite exclusions
    private var overrideFiles: Set<URL> = []

    init(tokenizer: Tokenizer? = nil, notificationSystem: NotificationSystem = NotificationSystem()) {
        self.tokenizer = tokenizer ?? HuggingFaceTokenizer()
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

    func generate(for workspace: SDWorkspace, modelContext: ModelContext, includeTree: Bool) async -> Output? {
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
           let decodedPaths = try? JSONDecoder().decode(Set<String>.self, from: selectionData) {
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
        
        // Filter to only include selected files
        let files = allFiles.filter { selectedFilePaths.contains($0.url.path) }

        var entries: [XMLFormatterService.FileEntry] = []
        var totalTokens = 0
        for file in files {
            guard let data = try? Data(contentsOf: file.url), let content = String(data: data, encoding: .utf8) else { continue }
            do {
                let tokens = try await tokenizer.countTokens(content)
                totalTokens += tokens
            } catch {
                print("Warning: Failed to count tokens for \(file.url.lastPathComponent): \(error)")
                // Continue processing even if tokenization fails for one file
            }
            let entry = XMLFormatterService.FileEntry(
                displayName: file.url.lastPathComponent,
                absolutePath: file.url.path,
                languageHint: LanguageMap.languageHint(for: file.url),
                contents: content
            )
            entries.append(entry)
        }

        let rendered = xml.render(codebaseRoot: root, files: entries, includeTree: includeTree)
        let output = Output(xml: rendered, totalTokens: totalTokens)
        
        // Check if content has changed
        let currentFiles = Set(files.map { $0.url })
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
        
        let selectedFiles = fileTreeModel.rootNode?.getSelectedFiles() ?? []
        guard !selectedFiles.isEmpty else {
            return Output(xml: "No files selected", totalTokens: 0)
        }
        
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
        
        let rendered = xml.render(codebaseRoot: root, files: entries, includeTree: includeTree)
        let output = Output(xml: rendered, totalTokens: totalTokens)
        
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
}

