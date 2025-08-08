import SwiftUI
import SwiftData

struct SidebarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SDWorkspace.lastOpenedAt, order: .reverse) private var workspaces: [SDWorkspace]

    @Binding var selection: SDWorkspace?
    @Binding var filterFocused: Bool

    @State private var filterText: String = ""
    @State private var showWorkspaceList = false

    var body: some View {
        VStack(spacing: 0) {
            // Show file tree for selected workspace, or workspace list
            if let workspace = selection, !showWorkspaceList {
                // File tree view with filter and options
                VStack(spacing: 0) {
                    WorkspaceHeader(workspace: workspace, showList: $showWorkspaceList)
                    Divider()
                    FilterBar(text: $filterText, focused: $filterFocused)
                    Divider()
                    FileTreeContainer(workspace: Binding(
                        get: { workspace },
                        set: { selection = $0 }
                    ), filterText: $filterText)
                }
            } else {
                // Workspace list
                VStack(spacing: 0) {
                    FilterBar(text: $filterText, focused: $filterFocused)
                    List(selection: $selection) {
                        Section("Workspaces") {
                            ForEach(workspaces) { ws in
                                HStack {
                                    Image(systemName: "folder")
                                    VStack(alignment: .leading) {
                                        Text(ws.name)
                                            .lineLimit(1)
                                        Text(ws.originalPath)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .tag(ws as SDWorkspace?)
                            }
                            .onDelete { indexSet in
                                indexSet.forEach { modelContext.delete(workspaces[$0]) }
                            }
                        }
                    }
                    .onChange(of: selection) { _, _ in
                        showWorkspaceList = false
                    }
                }
            }
        }
        .toolbar { SidebarToolbar() }
        .onReceive(NotificationCenter.default.publisher(for: .requestOpenFromWelcome)) { _ in
            FolderPicker.openFolder(modelContext: modelContext)
        }
    }
}

private struct WorkspaceHeader: View {
    let workspace: SDWorkspace
    @Binding var showList: Bool
    
    var body: some View {
        HStack {
            Button(action: { showList = true }) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            
            Image(systemName: "folder")
            Text(workspace.name)
                .font(.headline)
                .lineLimit(1)
            
            Spacer()
            
            Menu {
                FiltersMenu()
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

private struct FilterBar: View {
    @Binding var text: String
    @Binding var focused: Bool
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
            TextField("Filter files", text: $text)
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
    var body: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Menu("Filters") { FiltersMenu() }
        }
        ToolbarItem(placement: .automatic) {
            Button("Open…") { FolderPicker.openFolder(modelContext: modelContext) }
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

