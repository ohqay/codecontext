@testable import codecontext
import SwiftData
import XCTest

@MainActor  
final class WorkspaceLoaderTests: SwiftDataTestCase {
    
    func testBuildIgnoreRulesFromWorkspace() {
        let workspace = createTestWorkspace(name: "Test Workspace")
        
        // Configure workspace with specific ignore settings
        workspace.respectGitIgnore = true
        workspace.respectDotIgnore = false
        workspace.showHiddenFiles = true
        workspace.excludeNodeModules = true
        workspace.excludeGit = false
        workspace.excludeBuild = true
        workspace.excludeDist = false
        workspace.excludeNext = true
        workspace.excludeVenv = false
        workspace.excludeDSStore = true
        workspace.excludeDerivedData = true
        workspace.customIgnore = "*.tmp\n*.log\n*.cache"
        
        let rootPath = "/test/workspace"
        let ignoreRules = WorkspaceLoader.buildIgnoreRules(from: workspace, rootPath: rootPath)
        
        // Verify all settings are correctly transferred
        XCTAssertTrue(ignoreRules.respectGitIgnore, "Should respect git ignore")
        XCTAssertFalse(ignoreRules.respectDotIgnore, "Should not respect dot ignore")
        XCTAssertTrue(ignoreRules.showHiddenFiles, "Should show hidden files")
        
        // Verify custom patterns are parsed correctly
        XCTAssertEqual(ignoreRules.customPatterns.count, 3, "Should have 3 custom patterns")
        XCTAssertTrue(ignoreRules.customPatterns.contains("*.tmp"), "Should contain *.tmp pattern")
        XCTAssertTrue(ignoreRules.customPatterns.contains("*.log"), "Should contain *.log pattern") 
        XCTAssertTrue(ignoreRules.customPatterns.contains("*.cache"), "Should contain *.cache pattern")
    }
    
    func testBuildIgnoreRulesWithEmptyCustomIgnore() {
        let workspace = createTestWorkspace(name: "Test Workspace")
        workspace.customIgnore = ""
        
        let rootPath = "/test/workspace"
        let ignoreRules = WorkspaceLoader.buildIgnoreRules(from: workspace, rootPath: rootPath)
        
        XCTAssertTrue(ignoreRules.customPatterns.isEmpty, "Should have no custom patterns when empty")
    }
    
    func testBuildIgnoreRulesWithSingleLineCustomIgnore() {
        let workspace = createTestWorkspace(name: "Test Workspace")
        workspace.customIgnore = "*.single"
        
        let rootPath = "/test/workspace"
        let ignoreRules = WorkspaceLoader.buildIgnoreRules(from: workspace, rootPath: rootPath)
        
        XCTAssertEqual(ignoreRules.customPatterns.count, 1, "Should have 1 custom pattern")
        XCTAssertEqual(ignoreRules.customPatterns.first, "*.single", "Should contain single pattern")
    }
    
    func testBuildIgnoreRulesWithMultilineCustomIgnore() {
        let workspace = createTestWorkspace(name: "Test Workspace")
        workspace.customIgnore = """
        *.tmp
        *.log
        node_modules/
        .env
        dist/
        """
        
        let rootPath = "/test/workspace"
        let ignoreRules = WorkspaceLoader.buildIgnoreRules(from: workspace, rootPath: rootPath)
        
        XCTAssertEqual(ignoreRules.customPatterns.count, 5, "Should have 5 custom patterns")
        XCTAssertTrue(ignoreRules.customPatterns.contains("*.tmp"), "Should contain *.tmp")
        XCTAssertTrue(ignoreRules.customPatterns.contains("*.log"), "Should contain *.log")
        XCTAssertTrue(ignoreRules.customPatterns.contains("node_modules/"), "Should contain node_modules/")
        XCTAssertTrue(ignoreRules.customPatterns.contains(".env"), "Should contain .env")
        XCTAssertTrue(ignoreRules.customPatterns.contains("dist/"), "Should contain dist/")
    }
    
    func testBuildIgnoreRulesDefaultValues() {
        let workspace = createTestWorkspace(name: "Test Workspace")
        // Use default values (from createTestWorkspace)
        
        let rootPath = "/test/workspace"
        let ignoreRules = WorkspaceLoader.buildIgnoreRules(from: workspace, rootPath: rootPath)
        
        // Verify default values match workspace defaults
        XCTAssertTrue(ignoreRules.respectGitIgnore, "Should respect git ignore by default")
        XCTAssertTrue(ignoreRules.respectDotIgnore, "Should respect dot ignore by default")
        XCTAssertFalse(ignoreRules.showHiddenFiles, "Should not show hidden files by default")
    }
    
    func testResolveURLWithInvalidBookmark() {
        let workspace = createTestWorkspace(name: "Test Workspace")
        // Set invalid bookmark data
        workspace.bookmark = Data([0x00, 0x01, 0x02])  // Invalid bookmark
        
        let result = WorkspaceLoader.resolveURL(from: workspace, start: false)
        
        XCTAssertNil(result, "Should return nil for invalid bookmark data")
    }
    
    func testResolveURLWithValidBookmark() {
        let workspace = createTestWorkspace(name: "Test Workspace")
        
        // Create a temporary directory to work with
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent(UUID().uuidString)
        
        do {
            try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
            
            // Create bookmark data for the test directory
            let bookmarkData = try testDir.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            
            workspace.bookmark = bookmarkData
            
            // Test resolving the URL without starting access
            let resolvedURL = WorkspaceLoader.resolveURL(from: workspace, start: false)
            
            XCTAssertNotNil(resolvedURL, "Should resolve valid bookmark data")
            XCTAssertEqual(resolvedURL?.path, testDir.path, "Should resolve to correct path")
            
            // Clean up
            try? FileManager.default.removeItem(at: testDir)
        } catch {
            XCTFail("Failed to create test directory or bookmark: \(error)")
        }
    }
    
    func testWorkspaceHasValidInitialSelection() {
        let workspace = createTestWorkspace(name: "Test Workspace")
        
        // Workspace should start with valid JSON
        XCTAssertEqual(workspace.selectionJSON, "{}", "Should start with empty JSON object")
        
        // Should be parseable as JSON
        if let data = workspace.selectionJSON.data(using: .utf8) {
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data), "Selection JSON should be valid")
        } else {
            XCTFail("Should be able to convert selection JSON to data")
        }
    }
}