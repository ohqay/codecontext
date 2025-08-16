import SwiftUI

struct AppCommands: Commands {
    @FocusedValue(\._workspaceActions) private var actions

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            Button("Toggle Sidebar", systemImage: "sidebar.left") { actions?.toggleSidebar() }
                .keyboardShortcut("\\")
            Divider()
        }
        
        CommandGroup(replacing: .newItem) {
            Button("New Tab", systemImage: "plus.rectangle.on.rectangle") { actions?.newTab() }
                .keyboardShortcut("t")
            Button("Open Folder…", systemImage: "folder.badge.plus") { actions?.openFolder() }
                .keyboardShortcut("o")
        }

        CommandMenu("Codebase") {
            Button("Copy XML Output", systemImage: "doc.on.clipboard") { actions?.copyOutput() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button("Toggle File Tree in Output", systemImage: "list.bullet.indent") { actions?.toggleFileTree() }
                .keyboardShortcut("b")
            Button("Refresh", systemImage: "arrow.clockwise") { actions?.refresh() }
                .keyboardShortcut("r")
            Divider()
            Button("Filter Files", systemImage: "line.3.horizontal.decrease.circle") { actions?.focusFilter() }
                .keyboardShortcut("f")
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

    init(
        newTab: @escaping () -> Void,
        openFolder: @escaping () -> Void,
        copyOutput: @escaping () -> Void,
        toggleFileTree: @escaping () -> Void,
        refresh: @escaping () -> Void,
        focusFilter: @escaping () -> Void,
        toggleSidebar: @escaping () -> Void
    ) {
        self.newTab = newTab
        self.openFolder = openFolder
        self.copyOutput = copyOutput
        self.toggleFileTree = toggleFileTree
        self.refresh = refresh
        self.focusFilter = focusFilter
        self.toggleSidebar = toggleSidebar
    }
}
