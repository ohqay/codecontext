import Foundation
import SwiftData

@MainActor
final class WorkspaceEngine {
    private let tokenizer: Tokenizer
    private let scanner = FileScanner()
    private let xml = XMLFormatterService()

    init(tokenizer: Tokenizer? = nil) {
        self.tokenizer = tokenizer ?? TransformersTokenizer()
    }

    struct Output {
        let xml: String
        let totalTokens: Int
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
            customPatterns: workspace.customIgnore.split(separator: "\n").map(String.init)
        )
        let options = FileScanner.Options(ignoreRules: rules)
        let files = scanner.scan(root: root, options: options).filter { !$0.isDirectory }

        var entries: [XMLFormatterService.FileEntry] = []
        var totalTokens = 0
        for file in files {
            guard let data = try? Data(contentsOf: file.url), let content = String(data: data, encoding: .utf8) else { continue }
            let tokens = await tokenizer.countTokens(content)
            totalTokens += tokens
            let entry = XMLFormatterService.FileEntry(
                displayName: file.url.lastPathComponent,
                absolutePath: file.url.path,
                languageHint: LanguageMap.languageHint(for: file.url),
                contents: content
            )
            entries.append(entry)
        }

        let rendered = xml.render(codebaseRoot: root, files: entries, includeTree: includeTree)
        return Output(xml: rendered, totalTokens: totalTokens)
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
}

