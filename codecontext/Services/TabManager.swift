import SwiftUI
import SwiftData
import Foundation

/// Represents a single tab with its own workspace and UI state
struct WorkspaceTab: Identifiable, Hashable {
    let id = UUID()
    var workspace: SDWorkspace?
    var filterFocused: Bool = false
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: WorkspaceTab, rhs: WorkspaceTab) -> Bool {
        lhs.id == rhs.id
    }
}

/// Manages tab state for the application, allowing multiple workspaces to be open simultaneously
@Observable
final class TabManager {
    var tabs: [WorkspaceTab] = []
    var selectedTabId: UUID?
    
    var selectedTab: WorkspaceTab? {
        get {
            guard let selectedTabId else { return tabs.first }
            return tabs.first { $0.id == selectedTabId }
        }
        set {
            selectedTabId = newValue?.id
        }
    }
    
    init() {
        // Start with one empty tab
        addNewTab()
    }
    
    /// Creates a new empty tab and optionally selects it
    func addNewTab(selectTab: Bool = true) {
        let newTab = WorkspaceTab()
        tabs.append(newTab)
        
        if selectTab || tabs.count == 1 {
            selectedTabId = newTab.id
        }
    }
    
    /// Updates the workspace for a specific tab
    func updateWorkspace(for tabId: UUID, workspace: SDWorkspace?) {
        if let index = tabs.firstIndex(where: { $0.id == tabId }) {
            tabs[index].workspace = workspace
        }
    }
    
    /// Updates the filter focus state for a specific tab
    func updateFilterFocused(for tabId: UUID, focused: Bool) {
        if let index = tabs.firstIndex(where: { $0.id == tabId }) {
            tabs[index].filterFocused = focused
        }
    }
    
    /// Closes a tab by ID, ensuring at least one tab remains
    func closeTab(with id: UUID) {
        guard tabs.count > 1 else { return }
        
        let wasSelected = selectedTabId == id
        tabs.removeAll { $0.id == id }
        
        // If we closed the selected tab, select the first remaining tab
        if wasSelected || selectedTabId == nil {
            selectedTabId = tabs.first?.id
        }
    }
    
    /// Gets the display name for a tab
    func displayName(for tab: WorkspaceTab) -> String {
        guard let workspace = tab.workspace else { return "New Tab" }
        return workspace.name
    }
}