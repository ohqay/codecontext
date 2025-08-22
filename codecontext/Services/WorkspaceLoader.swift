import Foundation
import SwiftData

/// Manages workspace loading and configuration
@MainActor
final class WorkspaceLoader {
    /// Resolve a workspace URL from bookmark data
    static func resolveURL(from workspace: SDWorkspace, start: Bool = true) -> URL? {
        print(
            "[DEBUG] WorkspaceLoader: Resolving URL for workspace \(workspace.id), start: \(start)")
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: workspace.bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if start {
                let success = url.startAccessingSecurityScopedResource()
                print("[DEBUG] WorkspaceLoader: Started accessing \(url.path), success: \(success)")
            } else {
                url.stopAccessingSecurityScopedResource()
                print("[DEBUG] WorkspaceLoader: Stopped accessing \(url.path)")
            }
            return url
        } catch {
            print("[DEBUG] WorkspaceLoader: Error resolving URL: \(error.localizedDescription)")
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
        print(
            "[DEBUG] WorkspaceLoader: Performing operation for workspace \(workspace.id), isRefresh: \(isRefresh)"
        )
        guard let url = resolveURL(from: workspace) else {
            print("[DEBUG] WorkspaceLoader: Failed to resolve URL for workspace \(workspace.id)")
            return 0
        }

        print("[DEBUG] WorkspaceLoader: Resolved URL: \(url.path)")
        let ignoreRules = buildIgnoreRules(from: workspace, rootPath: url.path)

        if isRefresh {
            await fileTreeModel.refresh(ignoreRules: ignoreRules)
        } else {
            workspace.selectionJSON = "{}"
            await fileTreeModel.loadDirectory(at: url, ignoreRules: ignoreRules)
        }

        print("[DEBUG] WorkspaceLoader: Loaded \(fileTreeModel.allNodes.count) nodes")
        return isRefresh ? fileTreeModel.totalSelectedTokens : 0
    }

    /// Update workspace selection state from file tree
    static func updateSelection(
        workspace: SDWorkspace,
        fileTreeModel: FileTreeModel
    ) {
        print("[DEBUG] WorkspaceLoader: Updating selection for workspace \(workspace.id)")
        // This is now handled by SelectionManager, just trigger the update
        // The actual selection state will be updated asynchronously
        Task {
            let selectionManager = fileTreeModel.selectionManager
            // Get only the selected FILES (not directories) for the workspace JSON
            let (_, files, _) = await selectionManager.getSelectionState()

            await MainActor.run {
                if let data = try? JSONEncoder().encode(files),
                    let json = String(data: data, encoding: .utf8),
                    workspace.selectionJSON != json
                {
                    workspace.selectionJSON = json
                }
            }
        }
    }
}
