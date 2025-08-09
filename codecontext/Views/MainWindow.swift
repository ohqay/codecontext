import SwiftUI
import SwiftData
import AppKit

@Observable
final class AppState {
    var includeFileTreeInOutput: Bool = true
    var currentWorkspace: SDWorkspace?
    var selectedTokenCount: Int = 0
}

struct MainWindow: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SDWorkspace.lastOpenedAt, order: .reverse) private var workspaces: [SDWorkspace]
    @Environment(\.openWindow) private var openWindow

    @State private var appState = AppState()
    @State private var selection: SDWorkspace?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var filterFocused: Bool = false
    @State private var filterText: String = ""
    @State private var showWorkspaceList = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selection, filterFocused: $filterFocused, selectedTokenCount: Binding(
                get: { appState.selectedTokenCount },
                set: { appState.selectedTokenCount = $0 }
            ))
            .navigationSplitViewColumnWidth(min: 280, ideal: 400, max: 600)
        } detail: {
            if let selectedWorkspace = selection {
                WorkspaceDetailView(
                    workspace: selectedWorkspace,
                    includeFileTree: Binding(
                        get: { appState.includeFileTreeInOutput },
                        set: { appState.includeFileTreeInOutput = $0 }
                    ),
                    selectedTokenCount: Binding(
                        get: { appState.selectedTokenCount },
                        set: { appState.selectedTokenCount = $0 }
                    )
                )
            } else {
                EmptySelectionView()
            }
        }
        .focusedValue(\._workspaceActions, WorkspaceActions(
            newTab: createNewTab,
            openFolder: openFolder,
            copyOutput: copyOutput,
            toggleFileTree: { appState.includeFileTreeInOutput.toggle() },
            refresh: triggerRefresh,
            focusFilter: { filterFocused = true },
            toggleSidebar: toggleSidebar
        ))
        .toolbar(removing: .sidebarToggle)
        .onAppear { 
            ensureDefaultPreference()
            configureWindowForTabs()
        }
        .onChange(of: selection) { _, newWorkspace in
            appState.currentWorkspace = newWorkspace
            if let workspace = newWorkspace {
                workspace.lastOpenedAt = .now
                try? modelContext.save()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
            toggleSidebar()
        }
    }

    private func ensureDefaultPreference() {
        let fetch = FetchDescriptor<SDPreference>()
        if (try? modelContext.fetch(fetch))?.isEmpty ?? true {
            modelContext.insert(SDPreference())
        }
    }
    
    private func configureWindowForTabs() {
        // Configure the current window for native tabs
        DispatchQueue.main.async {
            if let window = NSApp.keyWindow {
                window.tabbingMode = .preferred
                window.titleVisibility = .visible
                
                // Set window title based on workspace
                if let workspace = selection {
                    window.title = workspace.name
                } else {
                    window.title = "codecontext"
                }
            }
        }
    }

    private func createNewTab() {
        // Use native macOS tab creation
        if let window = NSApp.keyWindow {
            NSApp.sendAction(#selector(NSWindow.newWindowForTab(_:)), to: nil, from: window)
        }
    }

    private func openFolder() {
        if let workspace = FolderPicker.openFolder(modelContext: modelContext) {
            selection = workspace
        }
    }

    private func copyOutput() {
        NotificationCenter.default.post(name: .requestCopyOutput, object: nil)
    }

    private func triggerRefresh() {
        NotificationCenter.default.post(name: .requestRefresh, object: nil)
    }
    
    private func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.3)) {
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
        }
    }
}

private struct EmptySelectionView: View {
    var body: some View {
        ContentPlaceholder {
            Text("Open a folder to begin")
        }
    }
}

extension Notification.Name {
    static let requestCopyOutput = Notification.Name("requestCopyOutput")
    static let requestRefresh = Notification.Name("requestRefresh")
    static let requestOpenFromWelcome = Notification.Name("requestOpenFromWelcome")
    static let fileSystemChanged = Notification.Name("fileSystemChanged")
    static let selectionChanged = Notification.Name("selectionChanged")
    static let outlineViewNeedsRefresh = Notification.Name("outlineViewNeedsRefresh")
    static let toggleSidebar = Notification.Name("toggleSidebar")
}