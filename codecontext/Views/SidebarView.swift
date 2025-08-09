import SwiftUI
import SwiftData

struct SidebarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SDWorkspace.lastOpenedAt, order: .reverse) private var workspaces: [SDWorkspace]

    @Binding var selection: SDWorkspace?
    @Binding var filterFocused: Bool
    @Binding var selectedTokenCount: Int

    @State private var filterText: String = ""
    @State private var showWorkspaceList = false

    var body: some View {
        VStack(spacing: 0) {
            // Show file tree for selected workspace
            if let workspace = selection {
                // File tree view with filter and options
                VStack(spacing: 0) {
                    FilterBar(text: $filterText, focused: $filterFocused)
                    Divider()
                    FileTreeContainer(workspace: Binding(
                        get: { workspace },
                        set: { selection = $0 }
                    ), filterText: $filterText, selectedTokenCount: $selectedTokenCount)
                }
            } else {
                // Empty state - prompt to open folder
                VStack {
                    Spacer()
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No Folder Open")
                        .font(.headline)
                        .padding(.top, 8)
                    Text("Open a folder to get started")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Folder") {
                        if let workspace = FolderPicker.openFolder(modelContext: modelContext) {
                            selection = workspace
                        }
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 12)
                    Spacer()
                }
            }
        }
        .toolbar { SidebarToolbar(selection: $selection) }
        .onReceive(NotificationCenter.default.publisher(for: .requestOpenFromWelcome)) { _ in
            if let workspace = FolderPicker.openFolder(modelContext: modelContext) {
                selection = workspace
            }
        }
    }
}

private struct FilterBar: View {
    @Binding var text: String
    @Binding var focused: Bool
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search files", text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
        }
        .padding(8)
        .background(.bar)
        .onChange(of: focused) { _, newValue in
            if newValue { isFocused = true; focused = false }
        }
    }
}

private struct SidebarToolbar: ToolbarContent {
    @Environment(\.modelContext) private var modelContext
    @Binding var selection: SDWorkspace?
    var body: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Menu {
                FiltersMenu()
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
            .buttonStyle(.borderless)
            .help("Filters")
        }
        ToolbarItem(placement: .automatic) {
            Button(action: { 
                if let workspace = FolderPicker.openFolder(modelContext: modelContext) {
                    selection = workspace
                }
            }) {
                Image(systemName: "folder.badge.plus")
            }
            .buttonStyle(.borderless)
            .help("Open Folder")
        }
    }
}

private struct FiltersMenu: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var prefs: [SDPreference]
    var body: some View {
        let pref = prefs.first
        Toggle("Respect .gitignore", isOn: Binding(
            get: { pref?.defaultRespectGitIgnore ?? true },
            set: { _ in update { $0.defaultRespectGitIgnore.toggle() } }
        ))
        Toggle("Respect .ignore", isOn: Binding(
            get: { pref?.defaultRespectDotIgnore ?? true },
            set: { _ in update { $0.defaultRespectDotIgnore.toggle() } }
        ))
        Divider()
        Toggle("Exclude node_modules", isOn: Binding(
            get: { pref?.defaultExcludeNodeModules ?? true },
            set: { _ in update { $0.defaultExcludeNodeModules.toggle() } }
        ))
        Toggle("Exclude .git", isOn: Binding(
            get: { pref?.defaultExcludeGit ?? true },
            set: { _ in update { $0.defaultExcludeGit.toggle() } }
        ))
        Toggle("Exclude build", isOn: Binding(
            get: { pref?.defaultExcludeBuild ?? true },
            set: { _ in update { $0.defaultExcludeBuild.toggle() } }
        ))
        Toggle("Exclude dist", isOn: Binding(
            get: { pref?.defaultExcludeDist ?? true },
            set: { _ in update { $0.defaultExcludeDist.toggle() } }
        ))
        Toggle("Exclude .next", isOn: Binding(
            get: { pref?.defaultExcludeNext ?? true },
            set: { _ in update { $0.defaultExcludeNext.toggle() } }
        ))
        Toggle("Exclude .venv", isOn: Binding(
            get: { pref?.defaultExcludeVenv ?? true },
            set: { _ in update { $0.defaultExcludeVenv.toggle() } }
        ))
        Toggle("Exclude .DS_Store", isOn: Binding(
            get: { pref?.defaultExcludeDSStore ?? true },
            set: { _ in update { $0.defaultExcludeDSStore.toggle() } }
        ))
        Toggle("Exclude DerivedData", isOn: Binding(
            get: { pref?.defaultExcludeDerivedData ?? true },
            set: { _ in update { $0.defaultExcludeDerivedData.toggle() } }
        ))
    }

    private func update(_ mutate: (inout SDPreference) -> Void) {
        guard var pref = try? modelContext.fetch(FetchDescriptor<SDPreference>()).first else { return }
        mutate(&pref)
        try? modelContext.save()
    }
}

