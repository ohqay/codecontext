import SwiftUI
import SwiftData

@Observable
final class AppState {
    var includeFileTreeInOutput: Bool = false
}

struct MainWindow: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SDWorkspace.lastOpenedAt, order: .reverse) private var workspaces: [SDWorkspace]

    @State private var appState = AppState()
    @State private var tabManager = TabManager()

    var body: some View {
        TabView(selection: $tabManager.selectedTabId) {
            ForEach(tabManager.tabs) { tab in
                WorkspaceTabView(
                    tab: tab,
                    tabManager: tabManager,
                    appState: appState,
                    modelContext: modelContext
                )
                .tabItem {
                    Text(tabManager.displayName(for: tab))
                }
                .tag(tab.id)
            }
        }
        .focusedValue(\._workspaceActions, WorkspaceActions(
            newTab: createNewTab,
            openFolder: openFolder,
            copyOutput: copyOutput,
            toggleFileTree: { appState.includeFileTreeInOutput.toggle() },
            refresh: triggerRefresh,
            focusFilter: focusCurrentTabFilter,
            toggleSidebar: toggleSidebar
        ))
        .toolbar { }
        .onAppear { ensureDefaultPreference() }
    }

    private func ensureDefaultPreference() {
        let fetch = FetchDescriptor<SDPreference>()
        if (try? modelContext.fetch(fetch))?.isEmpty ?? true {
            modelContext.insert(SDPreference())
        }
    }

    private func createNewTab() {
        tabManager.addNewTab()
    }

    private func openFolder() {
        FolderPicker.openFolder(modelContext: modelContext)
    }

    private func copyOutput() {
        NotificationCenter.default.post(name: .requestCopyOutput, object: nil)
    }

    private func triggerRefresh() {
        NotificationCenter.default.post(name: .requestRefresh, object: nil)
    }
    
    private func focusCurrentTabFilter() {
        guard let currentTab = tabManager.selectedTab else { return }
        tabManager.updateFilterFocused(for: currentTab.id, focused: true)
    }
    
    private func toggleSidebar() {
        // This will be handled by the focused tab's view
        // Just a placeholder for the command menu action
    }
}

/// Individual tab view that contains its own NavigationSplitView and workspace selection
private struct WorkspaceTabView: View {
    let tab: WorkspaceTab
    let tabManager: TabManager
    let appState: AppState
    let modelContext: ModelContext
    
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
    // Local binding for this tab's workspace selection
    private var selection: Binding<SDWorkspace?> {
        Binding(
            get: { tab.workspace },
            set: { tabManager.updateWorkspace(for: tab.id, workspace: $0) }
        )
    }
    
    // Local binding for this tab's filter focus state
    private var filterFocused: Binding<Bool> {
        Binding(
            get: { tab.filterFocused },
            set: { tabManager.updateFilterFocused(for: tab.id, focused: $0) }
        )
    }
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: selection, filterFocused: filterFocused)
        } detail: {
            if let selectedWorkspace = tab.workspace {
                WorkspaceDetailView(workspace: selectedWorkspace, includeFileTree: Binding(
                    get: { appState.includeFileTreeInOutput },
                    set: { appState.includeFileTreeInOutput = $0 }
                ))
            } else {
                EmptySelectionView()
            }
        }
        .focusedValue(\._workspaceActions, WorkspaceActions(
            newTab: { tabManager.addNewTab() },
            openFolder: { FolderPicker.openFolder(modelContext: modelContext) },
            copyOutput: { NotificationCenter.default.post(name: .requestCopyOutput, object: nil) },
            toggleFileTree: { appState.includeFileTreeInOutput.toggle() },
            refresh: { NotificationCenter.default.post(name: .requestRefresh, object: nil) },
            focusFilter: { tabManager.updateFilterFocused(for: tab.id, focused: true) },
            toggleSidebar: toggleSidebar
        ))
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
}
