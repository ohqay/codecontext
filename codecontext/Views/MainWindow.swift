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
    @State private var selection: SDWorkspace?
    @State private var filterFocused: Bool = false

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection, filterFocused: $filterFocused)
        } detail: {
            if let selection {
                WorkspaceDetailView(workspace: selection, includeFileTree: $appState.includeFileTreeInOutput)
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
            focusFilter: { filterFocused = true }
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
        NSApp.sendAction(#selector(NSWindow.performClose(_:)), to: nil, from: nil)
        // SwiftUI will create a new WindowGroup instance with the same content.
        NSApp.sendAction(#selector(NSApplication.newWindowForTab(_:)), to: nil, from: nil)
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
}
