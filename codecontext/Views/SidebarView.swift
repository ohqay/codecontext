import SwiftData
import SwiftUI

struct SidebarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SDWorkspace.lastOpenedAt, order: .reverse) private var workspaces: [SDWorkspace]

    @Binding var selection: SDWorkspace?
    @Binding var filterFocused: Bool
    @Binding var selectedTokenCount: Int
    @Binding var columnVisibility: NavigationSplitViewVisibility

    @State private var searchText: String = ""
    @State private var showWorkspaceList = false

    var body: some View {
        ZStack {
            // Ensure consistent background
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 0) {
                // Show file tree for selected workspace
                if let workspace = selection {
                    // File tree view with search and options
                    LiquidGlassSearchBar(
                        text: $searchText,
                        prompt: "Search files",
                        focused: $filterFocused
                    )
                    .searchBarPadding()

                    FileTreeContainer(
                        workspace: Binding(
                            get: { workspace },
                            set: { selection = $0 }
                        ), filterText: $searchText, selectedTokenCount: $selectedTokenCount
                    )
                } else {
                    // Empty state - prompt to open folder
                    EmptyStateView(
                        title: "No Folder Open",
                        subtitle: "Open a folder to begin"
                    )
                }
            }
        }
        .toolbar { SidebarToolbar(selection: $selection, columnVisibility: $columnVisibility) }
    }
}

// MARK: - Toolbar

private struct SidebarToolbar: ToolbarContent {
    @Environment(\.modelContext) private var modelContext
    @Binding var selection: SDWorkspace?
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @State private var showFiltersPopover = false

    var body: some ToolbarContent {
        if columnVisibility != .detailOnly {
            ToolbarItem(placement: .automatic) {
                GlassButton(
                    systemImage: "line.3.horizontal.decrease.circle",
                    action: { showFiltersPopover.toggle() }
                )
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
                GlassButton(
                    systemImage: "arrow.clockwise",
                    action: { NotificationCenter.default.post(name: .requestRefresh, object: nil) }
                )
                .help("Refresh (⌘R)")
            }
            ToolbarItem(placement: .automatic) {
                GlassButton(
                    systemImage: "folder.badge.plus"
                ) {
                    if let workspace = FolderPicker.openFolder(modelContext: modelContext) {
                        // Force SwiftData to refresh
                        try? modelContext.save()
                        // Small delay to ensure SwiftData updates
                        DispatchQueue.main.async {
                            selection = workspace
                        }
                    }
                }
                .help("Open Folder (⌘O)")
            }
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
        VStack(alignment: .leading, spacing: 4) {
            // Section 0: Respect rules
            ForEach(filterConfigs.filter { $0.section == 0 }, id: \.title) { config in
                FilterToggle(
                    title: config.title,
                    preference: prefs.first,
                    keyPath: config.keyPath,
                    onUpdate: update
                )
            }

            Divider()

            // Section 1: Exclude rules
            ForEach(filterConfigs.filter { $0.section == 1 }, id: \.title) { config in
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
            )
        )
    }
}
