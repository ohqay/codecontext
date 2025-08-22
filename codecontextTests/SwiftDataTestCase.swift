@testable import codecontext
import SwiftData
import XCTest

/// Base test case class for tests that require SwiftData model containers
/// Provides a clean, isolated in-memory database for each test
@MainActor
class SwiftDataTestCase: XCTestCase {
    private(set) var modelContext: ModelContext!
    private(set) var container: ModelContainer!
    
    override func setUp() async throws {
        try await super.setUp()
        try await setupSwiftData()
    }
    
    override func tearDown() async throws {
        await cleanupSwiftData()
        try await super.tearDown()
    }
    
    /// Sets up an in-memory SwiftData container with all app models
    private func setupSwiftData() async throws {
        let schema = Schema([
            SDWorkspace.self,
            SDPreference.self,
        ])
        
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        
        container = try ModelContainer(for: schema, configurations: [config])
        modelContext = ModelContext(container)
        
        // Ensure the context is clean
        try modelContext.save()
    }
    
    /// Cleans up SwiftData resources
    private func cleanupSwiftData() async {
        // Clear all data from the context
        if let modelContext = modelContext {
            // Delete all SDWorkspace entities
            let workspaceDescriptor = FetchDescriptor<SDWorkspace>()
            if let workspaces = try? modelContext.fetch(workspaceDescriptor) {
                for workspace in workspaces {
                    modelContext.delete(workspace)
                }
            }
            
            // Delete all SDPreference entities
            let preferenceDescriptor = FetchDescriptor<SDPreference>()
            if let preferences = try? modelContext.fetch(preferenceDescriptor) {
                for preference in preferences {
                    modelContext.delete(preference)
                }
            }
            
            try? modelContext.save()
        }
        
        modelContext = nil
        container = nil
    }
    
    /// Creates a test workspace with default values
    func createTestWorkspace(name: String = "Test Workspace", path: String = "/tmp/test") -> SDWorkspace {
        let workspace = SDWorkspace(
            name: name,
            originalPath: path,
            bookmark: Data() // Empty bookmark for testing
        )
        
        modelContext.insert(workspace)
        try? modelContext.save()
        
        return workspace
    }
    
    /// Creates a test preference with default values
    func createTestPreference(
        id: String = "test_global",
        lastActiveWorkspaceID: String? = nil
    ) -> SDPreference {
        let preference = SDPreference(
            id: id,
            lastActiveWorkspaceID: lastActiveWorkspaceID
        )
        
        modelContext.insert(preference)
        try? modelContext.save()
        
        return preference
    }
    
    /// Fetches all workspaces from the test database
    func fetchAllWorkspaces() throws -> [SDWorkspace] {
        let descriptor = FetchDescriptor<SDWorkspace>()
        return try modelContext.fetch(descriptor)
    }
    
    /// Fetches all preferences from the test database
    func fetchAllPreferences() throws -> [SDPreference] {
        let descriptor = FetchDescriptor<SDPreference>()
        return try modelContext.fetch(descriptor)
    }
    
    /// Asserts that the model context has no validation errors
    func assertValidContext() {
        XCTAssertNoThrow(try modelContext.save(), "Model context should be in a valid state")
    }
    
    /// Counts the total number of entities in the database
    func getTotalEntityCount() throws -> Int {
        let workspaces = try fetchAllWorkspaces()
        let preferences = try fetchAllPreferences()
        return workspaces.count + preferences.count
    }
}

/// Protocol for tests that need custom SwiftData setup
protocol CustomSwiftDataSetup {
    func customSetupSwiftData() async throws
    func customCleanupSwiftData() async
}

extension SwiftDataTestCase {
    /// Override point for subclasses that need custom SwiftData setup
    func performCustomSetup() async throws {
        if let customSetup = self as? CustomSwiftDataSetup {
            try await customSetup.customSetupSwiftData()
        }
    }
    
    /// Override point for subclasses that need custom SwiftData cleanup
    func performCustomCleanup() async {
        if let customCleanup = self as? CustomSwiftDataSetup {
            await customCleanup.customCleanupSwiftData()
        }
    }
}