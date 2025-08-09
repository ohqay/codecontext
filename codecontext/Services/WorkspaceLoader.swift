import Foundation
import SwiftData

/// Manages workspace loading and configuration
@MainActor
final class WorkspaceLoader {
    /// Resolve a workspace URL from bookmark data
    static func resolveURL(from workspace: SDWorkspace) -> URL? {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: workspace.bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            _ = url.startAccessingSecurityScopedResource()
            return url
        } catch {
            return nil
        }
    }

    /// Build ignore rules from workspace configuration
    static func buildIgnoreRules(from workspace: SDWorkspace, rootPath: String) -> IgnoreRules {
        IgnoreRules(
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
            rootPath: rootPath
        )
    }

    /// Perform a workspace operation (load or refresh)
    static func performOperation(
        workspace: SDWorkspace,
        fileTreeModel: FileTreeModel,
        isRefresh: Bool
    ) async -> Int {
        guard let url = resolveURL(from: workspace) else { 
            print("WorkspaceLoader: Failed to resolve URL for workspace: \(workspace.name)")
            return 0 
        }
        
        print("WorkspaceLoader: Loading workspace at \(url.path), isRefresh: \(isRefresh)")
        let ignoreRules = buildIgnoreRules(from: workspace, rootPath: url.path)

        if isRefresh {
            await fileTreeModel.refresh(ignoreRules: ignoreRules)
        } else {
            workspace.selectionJSON = "{}"
            await fileTreeModel.loadDirectory(at: url, ignoreRules: ignoreRules)
        }
        
        print("WorkspaceLoader: Loaded \(fileTreeModel.allNodes.count) nodes")
        return isRefresh ? fileTreeModel.totalSelectedTokens : 0
    }

    /// Update workspace selection state from file tree
    static func updateSelection(
        workspace: SDWorkspace,
        fileTreeModel: FileTreeModel
    ) {
        let selectedFiles = fileTreeModel.rootNode?.getSelectedFiles() ?? []
        let selectedPaths = Set(selectedFiles.map { $0.url.path })

        if let data = try? JSONEncoder().encode(selectedPaths),
           let json = String(data: data, encoding: .utf8),
           workspace.selectionJSON != json
        {
            workspace.selectionJSON = json
        }
    }
}
