import Foundation
import SwiftData

// Global app-wide preferences
@Model
final class SDPreference {
    var id: String

    // Defaults for new workspaces
    var defaultRespectGitIgnore: Bool
    var defaultRespectDotIgnore: Bool
    var defaultShowHidden: Bool

    // Default exclusions
    var defaultExcludeNodeModules: Bool
    var defaultExcludeGit: Bool
    var defaultExcludeBuild: Bool
    var defaultExcludeDist: Bool
    var defaultExcludeNext: Bool
    var defaultExcludeVenv: Bool
    var defaultExcludeDSStore: Bool
    var defaultExcludeDerivedData: Bool

    // Output options
    var includeFileTreeInOutput: Bool

    // Session restoration options
    var enableSessionRestoration: Bool
    var lastActiveWorkspaceID: String?

    init(
        id: String = "global",
        defaultRespectGitIgnore: Bool = true,
        defaultRespectDotIgnore: Bool = true,
        defaultShowHidden: Bool = false,
        defaultExcludeNodeModules: Bool = true,
        defaultExcludeGit: Bool = true,
        defaultExcludeBuild: Bool = true,
        defaultExcludeDist: Bool = true,
        defaultExcludeNext: Bool = true,
        defaultExcludeVenv: Bool = true,
        defaultExcludeDSStore: Bool = true,
        defaultExcludeDerivedData: Bool = true,
        includeFileTreeInOutput: Bool = false,
        enableSessionRestoration: Bool = true,
        lastActiveWorkspaceID: String? = nil
    ) {
        self.id = id
        self.defaultRespectGitIgnore = defaultRespectGitIgnore
        self.defaultRespectDotIgnore = defaultRespectDotIgnore
        self.defaultShowHidden = defaultShowHidden
        self.defaultExcludeNodeModules = defaultExcludeNodeModules
        self.defaultExcludeGit = defaultExcludeGit
        self.defaultExcludeBuild = defaultExcludeBuild
        self.defaultExcludeDist = defaultExcludeDist
        self.defaultExcludeNext = defaultExcludeNext
        self.defaultExcludeVenv = defaultExcludeVenv
        self.defaultExcludeDSStore = defaultExcludeDSStore
        self.defaultExcludeDerivedData = defaultExcludeDerivedData
        self.includeFileTreeInOutput = includeFileTreeInOutput
        self.enableSessionRestoration = enableSessionRestoration
        self.lastActiveWorkspaceID = lastActiveWorkspaceID
    }
}
