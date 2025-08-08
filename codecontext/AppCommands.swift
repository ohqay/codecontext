import SwiftUI

struct AppCommands: Commands {
    @FocusedValue(\._workspaceActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Tab") { actions?.newTab() }
                .keyboardShortcut("t")
            Button("Open Folder…") { actions?.openFolder() }
                .keyboardShortcut("o")
        }

        CommandMenu("Codebase") {
            Button("Copy XML Output") { actions?.copyOutput() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button("Toggle File Tree in Output") { actions?.toggleFileTree() }
                .keyboardShortcut("b")
            Button("Refresh") { actions?.refresh() }
                .keyboardShortcut("r")
            Divider()
            Button("Filter Files") { actions?.focusFilter() }
                .keyboardShortcut("f")
        }

        CommandMenu("View") {
            Button("Toggle Sidebar") { actions?.toggleSidebar() }
                .keyboardShortcut("\\")
        }
    }
}

// Focused actions wiring so nested views can expose intents
struct WorkspaceActionsKey: FocusedValueKey {
    typealias Value = WorkspaceActions
}

extension FocusedValues {
    var _workspaceActions: WorkspaceActionsKey.Value? {
        get { self[WorkspaceActionsKey.self] }
        set { self[WorkspaceActionsKey.self] = newValue }
    }
}

struct WorkspaceActions {
    let newTab: () -> Void
    let openFolder: () -> Void
    let copyOutput: () -> Void
    let toggleFileTree: () -> Void
    let refresh: () -> Void
    let focusFilter: () -> Void
    let toggleSidebar: () -> Void
}

