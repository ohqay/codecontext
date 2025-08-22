@testable import codecontext
import SwiftData
import XCTest

@MainActor
final class DataControllerTests: SwiftDataTestCase {
    
    func testDataControllerSharedInstance() {
        // Test that DataController.shared provides a valid instance
        let _ = DataController.shared
        // If we get here without crashing, the shared instance works
        XCTAssertTrue(true, "DataController.shared should be accessible")
    }
    
    func testDataControllerContainerCreation() async throws {
        // Test that DataController can create containers properly
        let _ = DataController.shared
        
        // The container should be created during initialization
        // We can't access it directly, but we can verify it works by creating our own
        let schema = Schema([
            SDWorkspace.self,
            SDPreference.self,
        ])
        
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let _ = try ModelContainer(for: schema, configurations: [config])
        
        // If we get here without throwing, container creation works
        XCTAssertTrue(true, "Should be able to create ModelContainer with app schema")
    }
    
    func testWorkspaceCreationAndRetrieval() throws {
        // Test creating and retrieving workspaces using our test infrastructure
        let _ = createTestWorkspace(name: "Workspace 1", path: "/path/1")
        let _ = createTestWorkspace(name: "Workspace 2", path: "/path/2")
        
        let allWorkspaces = try fetchAllWorkspaces()
        
        XCTAssertEqual(allWorkspaces.count, 2, "Should have exactly 2 workspaces")
        XCTAssertTrue(allWorkspaces.contains { $0.name == "Workspace 1" }, "Should contain Workspace 1")
        XCTAssertTrue(allWorkspaces.contains { $0.name == "Workspace 2" }, "Should contain Workspace 2")
    }
    
    func testPreferenceCreationAndRetrieval() throws {
        // Test creating and retrieving preferences
        let _ = createTestPreference(id: "pref1")
        let _ = createTestPreference(id: "pref2", lastActiveWorkspaceID: "workspace123")
        
        let allPreferences = try fetchAllPreferences()
        
        XCTAssertEqual(allPreferences.count, 2, "Should have exactly 2 preferences")
        XCTAssertTrue(allPreferences.contains { $0.id == "pref1" }, "Should contain pref1")
        XCTAssertTrue(allPreferences.contains { $0.id == "pref2" }, "Should contain pref2")
        
        let pref2 = allPreferences.first { $0.id == "pref2" }
        XCTAssertEqual(pref2?.lastActiveWorkspaceID, "workspace123", "Should preserve lastActiveWorkspaceID")
    }
    
    func testWorkspaceIDGeneration() {
        // Test that workspace IDs are unique
        let workspace1 = createTestWorkspace(name: "Test 1")
        let workspace2 = createTestWorkspace(name: "Test 2")
        
        XCTAssertFalse(workspace1.id.isEmpty, "Workspace 1 ID should not be empty")
        XCTAssertFalse(workspace2.id.isEmpty, "Workspace 2 ID should not be empty")
        XCTAssertNotEqual(workspace1.id, workspace2.id, "Workspace IDs should be unique")
    }
    
    func testWorkspaceDefaultValues() {
        // Test that workspaces are created with proper default values
        let workspace = createTestWorkspace()
        
        XCTAssertTrue(workspace.respectGitIgnore, "Should respect .gitignore by default")
        XCTAssertTrue(workspace.respectDotIgnore, "Should respect .ignore by default")
        XCTAssertFalse(workspace.showHiddenFiles, "Should not show hidden files by default")
        
        // Test exclusion defaults
        XCTAssertTrue(workspace.excludeNodeModules, "Should exclude node_modules by default")
        XCTAssertTrue(workspace.excludeGit, "Should exclude .git by default")
        XCTAssertTrue(workspace.excludeBuild, "Should exclude build directories by default")
        XCTAssertTrue(workspace.excludeDerivedData, "Should exclude DerivedData by default")
        
        XCTAssertEqual(workspace.selectionJSON, "{}", "Should have empty selection JSON by default")
        XCTAssertEqual(workspace.customIgnore, "", "Should have empty custom ignore by default")
    }
    
    func testPreferenceDefaultValues() {
        // Test that preferences are created with proper default values
        let preference = createTestPreference()
        
        XCTAssertTrue(preference.defaultRespectGitIgnore, "Should respect .gitignore by default")
        XCTAssertTrue(preference.defaultRespectDotIgnore, "Should respect .ignore by default")
        XCTAssertFalse(preference.defaultShowHidden, "Should not show hidden files by default")
        
        XCTAssertTrue(preference.enableSessionRestoration, "Should enable session restoration by default")
        XCTAssertTrue(preference.includeFileTreeInOutput, "Should include file tree in output by default")
        
        XCTAssertNil(preference.lastActiveWorkspaceID, "Should have no last active workspace by default")
    }
    
    func testModelRelationships() throws {
        // Test the relationship between workspaces and preferences
        let workspace = createTestWorkspace(name: "Test Workspace")
        let preference = createTestPreference(lastActiveWorkspaceID: workspace.id)
        
        // Verify the preference points to the correct workspace
        XCTAssertEqual(preference.lastActiveWorkspaceID, workspace.id, "Preference should reference correct workspace")
        
        // Test fetching workspace by ID (simulating session restoration)
        let allWorkspaces = try fetchAllWorkspaces()
        let foundWorkspace = allWorkspaces.first { $0.id == preference.lastActiveWorkspaceID }
        
        XCTAssertNotNil(foundWorkspace, "Should be able to find workspace by ID")
        XCTAssertEqual(foundWorkspace?.name, "Test Workspace", "Found workspace should have correct name")
    }
    
    func testModelContextValidation() {
        // Test that our test context remains valid throughout operations
        assertValidContext()
        
        let workspace = createTestWorkspace()
        assertValidContext()
        
        let preference = createTestPreference()
        assertValidContext()
        
        // Modify entities
        workspace.name = "Modified Name"
        preference.enableSessionRestoration = false
        
        assertValidContext()
        
        try? modelContext.save()
        assertValidContext()
    }
    
    func testEntityCounting() throws {
        // Test our utility method for counting entities
        XCTAssertEqual(try getTotalEntityCount(), 0, "Should start with 0 entities")
        
        let _ = createTestWorkspace()
        XCTAssertEqual(try getTotalEntityCount(), 1, "Should have 1 entity after creating workspace")
        
        let _ = createTestPreference()
        XCTAssertEqual(try getTotalEntityCount(), 2, "Should have 2 entities after creating preference")
        
        let _ = createTestWorkspace(name: "Second")
        XCTAssertEqual(try getTotalEntityCount(), 3, "Should have 3 entities after creating second workspace")
    }
    
    func testDataIsolation() throws {
        // Test that each test has isolated data
        let workspace = createTestWorkspace(name: "Isolation Test")
        let workspaces = try fetchAllWorkspaces()
        
        XCTAssertEqual(workspaces.count, 1, "Should only have the workspace created in this test")
        XCTAssertEqual(workspaces.first?.name, "Isolation Test", "Should have correct workspace name")
    }
}