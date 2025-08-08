import AppKit
import SwiftData

enum FolderPicker {
    static func openFolder(modelContext: ModelContext) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Open"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let name = url.lastPathComponent
                let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                let ws = SDWorkspace(name: name, originalPath: url.path, bookmark: bookmark)
                modelContext.insert(ws)
                try modelContext.save()
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }
}

