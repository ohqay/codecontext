import SwiftData
import SwiftUI

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
                    FileTreeContainer(
                        workspace: Binding(
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
                    Spacer()
                }
            }
        }
        .toolbar { SidebarToolbar(selection: $selection) }
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
            if newValue {
                isFocused = true
                focused = false
            }
        }
    }
}

private struct SidebarToolbar: ToolbarContent {
    @Environment(\.modelContext) private var modelContext
    @Binding var selection: SDWorkspace?
    @State private var showFiltersPopover = false
    
    var body: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Button(action: {
                showFiltersPopover.toggle()
            }) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 16, weight: .regular))
            }
            .buttonStyle(.glass)
            .help("Filters")
            .popover(isPresented: $showFiltersPopover, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    FiltersMenu()
                }
                .padding()
                .frame(width: 250)
            }
        }
        ToolbarItem(placement: .automatic) {
            Button(action: {
                if let workspace = FolderPicker.openFolder(modelContext: modelContext) {
                    // Force SwiftData to refresh
                    try? modelContext.save()
                    // Small delay to ensure SwiftData updates
                    DispatchQueue.main.async {
                        selection = workspace
                    }
                }
            }) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 16, weight: .regular))
            }
            .buttonStyle(.glass)
            .help("Open Folder")
        }
    }
}

private struct FiltersMenu: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var prefs: [SDPreference]

    // Define filter configurations
    private let filterConfigs:
        [(title: String, keyPath: WritableKeyPath<SDPreference, Bool>, section: Int)] = [
            // Section 0: Respect rules
            ("Respect .gitignore", \.defaultRespectGitIgnore, 0),
            ("Respect .ignore", \.defaultRespectDotIgnore, 0),
            // Section 1: Exclude rules
            ("Exclude node_modules", \.defaultExcludeNodeModules, 1),
            ("Exclude .git", \.defaultExcludeGit, 1),
            ("Exclude build", \.defaultExcludeBuild, 1),
            ("Exclude dist", \.defaultExcludeDist, 1),
            ("Exclude .next", \.defaultExcludeNext, 1),
            ("Exclude .venv", \.defaultExcludeVenv, 1),
            ("Exclude .DS_Store", \.defaultExcludeDSStore, 1),
            ("Exclude DerivedData", \.defaultExcludeDerivedData, 1),
        ]

    var body: some View {
        ForEach(0..<filterConfigs.count) { section in
            if section == 1 {
                Divider()
            }
            ForEach(filterConfigs.filter { $0.section == section }, id: \.title) { config in
                FilterToggle(
                    title: config.title,
                    preference: prefs.first,
                    keyPath: config.keyPath,
                    onUpdate: update
                )
            }
        }
    }

    private func update(_ mutate: (inout SDPreference) -> Void) {
        guard var pref = try? modelContext.fetch(FetchDescriptor<SDPreference>()).first else {
            return
        }
        mutate(&pref)
        try? modelContext.save()
    }
}

private struct FilterToggle: View {
    let title: String
    let preference: SDPreference?
    let keyPath: WritableKeyPath<SDPreference, Bool>
    let onUpdate: ((inout SDPreference) -> Void) -> Void

    var body: some View {
        Toggle(
            title,
            isOn: Binding(
                get: { preference?[keyPath: keyPath] ?? true },
                set: { _ in onUpdate { $0[keyPath: keyPath].toggle() } }
            ))
    }
}
