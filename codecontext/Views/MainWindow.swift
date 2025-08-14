import AppKit
import SwiftData
import SwiftUI

@Observable
final class AppState {
    var includeFileTreeInOutput: Bool = true
    var includeInstructionsInOutput: Bool = true
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
            SidebarView(
                selection: $selection, filterFocused: $filterFocused,
                selectedTokenCount: Binding(
                    get: { appState.selectedTokenCount },
                    set: { appState.selectedTokenCount = $0 }
                )
            )
            .navigationSplitViewColumnWidth(min: 280, ideal: 400, max: 600)
            .navigationSplitViewStyle(.balanced)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            if let selectedWorkspace = selection {
                WorkspaceDetailView(
                    workspace: selectedWorkspace,
                    includeFileTree: Binding(
                        get: { appState.includeFileTreeInOutput },
                        set: { appState.includeFileTreeInOutput = $0 }
                    ),
                    includeInstructions: Binding(
                        get: { appState.includeInstructionsInOutput },
                        set: { appState.includeInstructionsInOutput = $0 }
                    ),
                    selectedTokenCount: Binding(
                        get: { appState.selectedTokenCount },
                        set: { appState.selectedTokenCount = $0 }
                    )
                )
            } else {
                EmptySelectionView(selection: $selection)
            }
        }
        .focusedValue(
            \._workspaceActions,
            WorkspaceActions(
                newTab: createNewTab,
                openFolder: openFolder,
                copyOutput: copyOutput,
                toggleFileTree: { appState.includeFileTreeInOutput.toggle() },
                refresh: triggerRefresh,
                focusFilter: { filterFocused = true },
                toggleSidebar: toggleSidebar,
            )
        )
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                GlassButton(
                    systemImage: "sidebar.left",
                    action: toggleSidebar
                )
                .symbolVariant(columnVisibility == .detailOnly ? .none : .fill)
                .help(columnVisibility == .detailOnly ? "Show Sidebar" : "Hide Sidebar")
            }
        }
        .onAppear {
            ensureDefaultPreference()
            configureWindowForTabs()
            restoreLastSessionIfNeeded()
        }
        .onChange(of: selection) { _, newWorkspace in
            print("MainWindow: Selection changed to \(newWorkspace?.name ?? "nil")")
            appState.currentWorkspace = newWorkspace
            if let workspace = newWorkspace {
                workspace.lastOpenedAt = .now
                try? modelContext.save()
            }

            // Save the current session for restoration
            SessionManager.shared.saveCurrentSession(workspace: newWorkspace, modelContext: modelContext)
        }
    }

    private func ensureDefaultPreference() {
        let fetch = FetchDescriptor<SDPreference>()
        if (try? modelContext.fetch(fetch))?.isEmpty ?? true {
            modelContext.insert(SDPreference())
        }
    }

    private func restoreLastSessionIfNeeded() {
        // Only restore if no workspace is currently selected and we have workspaces available
        guard selection == nil, !workspaces.isEmpty else {
            return
        }

        // Attempt to restore the last session
        if let restoredWorkspace = SessionManager.shared.restoreLastSession(modelContext: modelContext) {
            // Use a small delay to ensure the UI is ready
            DispatchQueue.main.async {
                self.selection = restoredWorkspace
                print("[MainWindow] Auto-restored workspace: \(restoredWorkspace.name)")
            }
        }
    }

    private func configureWindowForTabs() {
        // Configure the current window for native tabs
        DispatchQueue.main.async {
            if let window = NSApp.keyWindow {
                window.tabbingMode = .preferred
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
            // Force SwiftData to refresh by saving context first
            try? modelContext.save()
            // Small delay to ensure SwiftData updates
            DispatchQueue.main.async {
                selection = workspace
            }
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
    @Environment(\.modelContext) private var modelContext
    @Binding var selection: SDWorkspace?

    var body: some View {
        EmptyStateView(
            icon: "folder.badge.plus",
            title: "No Folder Selected",
            action: {
                if let workspace = FolderPicker.openFolder(modelContext: modelContext) {
                    // Force SwiftData to refresh
                    try? modelContext.save()
                    // Small delay to ensure SwiftData updates
                    DispatchQueue.main.async {
                        selection = workspace
                    }
                }
            },
            actionTitle: "Open Folder",
            actionHint: "⌘O",
            isActionProminent: true
        )
    }
}

// MARK: - Glass Button

struct GlassButton: View {
    let title: String?
    let hint: String?
    let systemImage: String?
    let imageFontSize: CGFloat
    let isProminent: Bool
    let isHoverable: Bool
    let action: () -> Void

    @State private var isHovered = false

    init(
        title: String? = nil,
        hint: String? = nil,
        systemImage: String? = nil,
        imageFontSize: CGFloat = 16,
        isProminent: Bool = false,
        isHoverable: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.hint = hint
        self.systemImage = systemImage
        self.imageFontSize = imageFontSize
        self.isProminent = isProminent
        self.isHoverable = isHoverable
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage = systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: imageFontSize, weight: .regular))
                        .foregroundStyle(.primary)
                }
                if let title = title {
                    Text(title)
                }
                if let hint = hint {
                    Text(hint)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .modifier(GlassButtonModifier(isProminent: isProminent))
        .cornerRadius(.greatestFiniteMagnitude)
        .focusEffectDisabled()
        .scaleEffect(isHoverable && isHovered ? 1.03 : 1.0)
        .animation(.easeInOut(duration: 0.10), value: isHovered)
        .onHover { hovering in
            if isHoverable {
                isHovered = hovering
            }
        }
    }
}

private struct GlassButtonModifier: ViewModifier {
    let isProminent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isProminent {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.glass)
        }
    }
}

extension Notification.Name {
    static let requestCopyOutput = Notification.Name("requestCopyOutput")
    static let requestRefresh = Notification.Name("requestRefresh")
    static let fileSystemChanged = Notification.Name("fileSystemChanged")
    static let selectionChanged = Notification.Name("selectionChanged")
    static let outlineViewNeedsRefresh = Notification.Name("outlineViewNeedsRefresh")
}
