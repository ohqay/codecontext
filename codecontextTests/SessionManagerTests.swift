@testable import codecontext
import SwiftData
import XCTest

@MainActor
final class SessionManagerTests: XCTestCase {
    private var modelContext: ModelContext!
    private var container: ModelContainer!

    override func setUp() async throws {
        let schema = Schema([
            SDWorkspace.self,
            SDPreference.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        modelContext = ModelContext(container)
    }

    override func tearDown() async throws {
        modelContext = nil
        container = nil
    }

    func testSessionRestorationEnabled() throws {
        let sessionManager = SessionManager.shared

        // Initially, session restoration should be enabled by default
        let isEnabled = sessionManager.isSessionRestorationEnabled(modelContext: modelContext)
        XCTAssertTrue(isEnabled, "Session restoration should be enabled by default")
    }

    func testSaveAndRestoreSession() throws {
        let sessionManager = SessionManager.shared

        // Create a test workspace
        let workspace = SDWorkspace(
            name: "Test Workspace",
            originalPath: "/test/path",
            bookmark: Data()
        )

        modelContext.insert(workspace)
        try modelContext.save()

        // Save the session
        sessionManager.saveCurrentSession(workspace: workspace, modelContext: modelContext)

        // The restored session would normally validate bookmark access
        // For this test, we'll just verify the preference was saved
        let fetchDescriptor = FetchDescriptor<SDPreference>()
        let preferences = try modelContext.fetch(fetchDescriptor)

        XCTAssertEqual(preferences.count, 1, "Should have one preference record")
        XCTAssertEqual(preferences.first?.lastActiveWorkspaceID, workspace.id, "Should save workspace ID")
        XCTAssertTrue(preferences.first?.enableSessionRestoration ?? false, "Should enable session restoration")
    }

    func testClearSession() throws {
        let sessionManager = SessionManager.shared

        // Create a test workspace and save session
        let workspace = SDWorkspace(
            name: "Test Workspace",
            originalPath: "/test/path",
            bookmark: Data()
        )

        modelContext.insert(workspace)
        try modelContext.save()

        sessionManager.saveCurrentSession(workspace: workspace, modelContext: modelContext)

        // Clear the session
        sessionManager.clearSession(modelContext: modelContext)

        // Verify session was cleared
        let fetchDescriptor = FetchDescriptor<SDPreference>()
        let preferences = try modelContext.fetch(fetchDescriptor)

        XCTAssertEqual(preferences.count, 1, "Should still have preference record")
        XCTAssertNil(preferences.first?.lastActiveWorkspaceID, "Should clear workspace ID")
    }

    func testGetOrCreatePreferences() throws {
        let sessionManager = SessionManager.shared

        // Initially no preferences should exist
        let fetchDescriptor = FetchDescriptor<SDPreference>()
        let initialPreferences = try modelContext.fetch(fetchDescriptor)
        XCTAssertEqual(initialPreferences.count, 0, "Should start with no preferences")

        // Calling any method should create preferences
        let isEnabled = sessionManager.isSessionRestorationEnabled(modelContext: modelContext)
        XCTAssertTrue(isEnabled, "Should create default preferences")

        // Verify preferences were created
        let createdPreferences = try modelContext.fetch(fetchDescriptor)
        XCTAssertEqual(createdPreferences.count, 1, "Should create one preference record")
        XCTAssertTrue(createdPreferences.first?.enableSessionRestoration ?? false, "Should default to enabled")
    }

    func testWorkspaceIDGeneration() {
        let workspace1 = SDWorkspace(
            name: "Workspace 1",
            originalPath: "/path/1",
            bookmark: Data()
        )

        let workspace2 = SDWorkspace(
            name: "Workspace 2",
            originalPath: "/path/2",
            bookmark: Data()
        )

        // IDs should be unique
        XCTAssertNotEqual(workspace1.id, workspace2.id, "Workspace IDs should be unique")
        XCTAssertFalse(workspace1.id.isEmpty, "Workspace ID should not be empty")
        XCTAssertFalse(workspace2.id.isEmpty, "Workspace ID should not be empty")
    }
}
