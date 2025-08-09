import AppKit
import SwiftData

enum FolderPicker {
    @discardableResult
    static func openFolder(modelContext: ModelContext) -> SDWorkspace? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Open"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                // Check if workspace already exists for this path
                let fetch = FetchDescriptor<SDWorkspace>()
                let allWorkspaces = try modelContext.fetch(fetch)
                
                if let existingWorkspace = allWorkspaces.first(where: { $0.originalPath == url.path }) {
                    // Update last opened date for existing workspace
                    existingWorkspace.lastOpenedAt = .now
                    try modelContext.save()
                    return existingWorkspace
                } else {
                    // Create new workspace
                    let name = url.lastPathComponent
                    let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                    let ws = SDWorkspace(name: name, originalPath: url.path, bookmark: bookmark)
                    modelContext.insert(ws)
                    try modelContext.save()
                    return ws
                }
            } catch {
                NSAlert(error: error).runModal()
                return nil
            }
        }
        return nil
    }
}