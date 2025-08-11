import Foundation
import SwiftData

/// Session management service for restoring user's last active workspace
@MainActor
final class SessionManager {
    static let shared = SessionManager()

    private init() {}

    /// Save the current active workspace to preferences for session restoration
    /// - Parameters:
    ///   - workspace: The workspace to save as the last active
    ///   - modelContext: SwiftData model context for persistence
    func saveCurrentSession(workspace: SDWorkspace?, modelContext: ModelContext) {
        do {
            let preferences = try getOrCreatePreferences(modelContext: modelContext)
            preferences.lastActiveWorkspaceID = workspace?.id
            try modelContext.save()

            print("[SessionManager] Saved session with workspace: \(workspace?.name ?? "nil")")
        } catch {
            print("[SessionManager] Failed to save session: \(error)")
        }
    }

    /// Restore the last active workspace if session restoration is enabled
    /// - Parameter modelContext: SwiftData model context for querying
    /// - Returns: The last active workspace if found and valid, nil otherwise
    func restoreLastSession(modelContext: ModelContext) -> SDWorkspace? {
        do {
            let preferences = try getOrCreatePreferences(modelContext: modelContext)

            // Check if session restoration is enabled
            guard preferences.enableSessionRestoration else {
                print("[SessionManager] Session restoration is disabled")
                return nil
            }

            // Try to find the last active workspace
            if let lastWorkspaceID = preferences.lastActiveWorkspaceID,
               let workspace = try findWorkspaceByID(lastWorkspaceID, modelContext: modelContext)
            {
                // Validate that the workspace bookmark is still accessible
                if validateWorkspaceAccess(workspace) {
                    print("[SessionManager] Restored session with workspace: \(workspace.name)")
                    return workspace
                } else {
                    print("[SessionManager] Last workspace bookmark is no longer accessible, clearing session")
                    // Clear the invalid workspace reference
                    preferences.lastActiveWorkspaceID = nil
                    try modelContext.save()
                }
            }

            // Fallback: try to get the most recently used workspace
            let fallbackWorkspace = try getMostRecentWorkspace(modelContext: modelContext)
            if let workspace = fallbackWorkspace, validateWorkspaceAccess(workspace) {
                print("[SessionManager] Restored fallback workspace: \(workspace.name)")
                return workspace
            }

            print("[SessionManager] No valid workspace found for restoration")
            return nil

        } catch {
            print("[SessionManager] Failed to restore session: \(error)")
            return nil
        }
    }

    /// Clear the current session (useful for logout or reset scenarios)
    /// - Parameter modelContext: SwiftData model context for persistence
    func clearSession(modelContext: ModelContext) {
        do {
            let preferences = try getOrCreatePreferences(modelContext: modelContext)
            preferences.lastActiveWorkspaceID = nil
            try modelContext.save()
            print("[SessionManager] Session cleared")
        } catch {
            print("[SessionManager] Failed to clear session: \(error)")
        }
    }

    /// Check if session restoration is enabled in user preferences
    /// - Parameter modelContext: SwiftData model context for querying
    /// - Returns: True if session restoration is enabled, false otherwise
    func isSessionRestorationEnabled(modelContext: ModelContext) -> Bool {
        do {
            let preferences = try getOrCreatePreferences(modelContext: modelContext)
            return preferences.enableSessionRestoration
        } catch {
            print("[SessionManager] Failed to check session restoration setting: \(error)")
            // Default to enabled if we can't check preferences
            return true
        }
    }

    // MARK: - Private Helper Methods

    private func getOrCreatePreferences(modelContext: ModelContext) throws -> SDPreference {
        let fetchDescriptor = FetchDescriptor<SDPreference>()
        let preferences = try modelContext.fetch(fetchDescriptor)

        if let existingPreferences = preferences.first {
            return existingPreferences
        } else {
            // Create default preferences if none exist
            let newPreferences = SDPreference()
            modelContext.insert(newPreferences)
            return newPreferences
        }
    }

    private func findWorkspaceByID(_ workspaceID: String, modelContext: ModelContext) throws -> SDWorkspace? {
        let fetchDescriptor = FetchDescriptor<SDWorkspace>()
        let allWorkspaces = try modelContext.fetch(fetchDescriptor)
        return allWorkspaces.first { $0.id == workspaceID }
    }

    private func getMostRecentWorkspace(modelContext: ModelContext) throws -> SDWorkspace? {
        let fetchDescriptor = FetchDescriptor<SDWorkspace>()
        let allWorkspaces = try modelContext.fetch(fetchDescriptor)
        return allWorkspaces.sorted { $0.lastOpenedAt > $1.lastOpenedAt }.first
    }

    private func validateWorkspaceAccess(_ workspace: SDWorkspace) -> Bool {
        // Attempt to resolve the security-scoped bookmark
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: workspace.bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            // Start accessing the security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                print("[SessionManager] Failed to access security-scoped resource for \(workspace.name)")
                return false
            }

            defer {
                url.stopAccessingSecurityScopedResource()
            }

            // Check if the directory still exists and is accessible
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)

            if !exists {
                print("[SessionManager] Workspace directory no longer exists: \(workspace.name)")
                return false
            }

            if !isDirectory.boolValue {
                print("[SessionManager] Workspace path is no longer a directory: \(workspace.name)")
                return false
            }

            if isStale {
                print("[SessionManager] Workspace bookmark is stale but accessible: \(workspace.name)")
                // Note: We could refresh the bookmark here in the future
            }

            return true

        } catch {
            print("[SessionManager] Failed to validate workspace access for \(workspace.name): \(error)")
            return false
        }
    }
}
