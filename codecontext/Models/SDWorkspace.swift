import Foundation
import SwiftData

// Workspace persisted entity holding bookmark and per-workspace settings
@Model
final class SDWorkspace {
    // Unique identifier for this workspace
    var id: String

    // Human-readable display name
    var name: String

    // Original picked path for UX; not used for access
    var originalPath: String

    // Security-scoped bookmark data for the selected directory
    var bookmark: Data

    // Per-workspace options
    var respectGitIgnore: Bool
    var respectDotIgnore: Bool
    var showHiddenFiles: Bool

    // Exclusions (default true per SPEC)
    var excludeNodeModules: Bool
    var excludeGit: Bool
    var excludeBuild: Bool
    var excludeDist: Bool
    var excludeNext: Bool
    var excludeVenv: Bool
    var excludeDSStore: Bool
    var excludeDerivedData: Bool

    // Custom ignore patterns (gitignore-like), one per line
    var customIgnore: String

    // JSON blob for selection state (path set); kept minimal and versionable
    var selectionJSON: String

    // Last opened date for recents ordering
    var lastOpenedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        originalPath: String,
        bookmark: Data,
        respectGitIgnore: Bool = true,
        respectDotIgnore: Bool = true,
        showHiddenFiles: Bool = false,
        excludeNodeModules: Bool = true,
        excludeGit: Bool = true,
        excludeBuild: Bool = true,
        excludeDist: Bool = true,
        excludeNext: Bool = true,
        excludeVenv: Bool = true,
        excludeDSStore: Bool = true,
        excludeDerivedData: Bool = true,
        customIgnore: String = "",
        selectionJSON: String = "{}",
        lastOpenedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.originalPath = originalPath
        self.bookmark = bookmark
        self.respectGitIgnore = respectGitIgnore
        self.respectDotIgnore = respectDotIgnore
        self.showHiddenFiles = showHiddenFiles
        self.excludeNodeModules = excludeNodeModules
        self.excludeGit = excludeGit
        self.excludeBuild = excludeBuild
        self.excludeDist = excludeDist
        self.excludeNext = excludeNext
        self.excludeVenv = excludeVenv
        self.excludeDSStore = excludeDSStore
        self.excludeDerivedData = excludeDerivedData
        self.customIgnore = customIgnore
        self.selectionJSON = selectionJSON
        self.lastOpenedAt = lastOpenedAt
    }
}
