@testable import codecontext
import XCTest

final class SelectionManagerTests: XCTestCase {
    
    func testSelectionManagerInitialState() async {
        let manager = SelectionManager()
        
        let state = await manager.getSelectionState()
        
        XCTAssertTrue(state.paths.isEmpty, "Should start with no selected paths")
        XCTAssertTrue(state.files.isEmpty, "Should start with no selected files")
        XCTAssertEqual(state.tokens, 0, "Should start with zero tokens")
    }
    
    func testToggleSelectionChangesState() async {
        let manager = SelectionManager()
        let nodePath = "/test/folder"
        let affectedPaths: Set<String> = ["/test/folder", "/test/folder/file1.txt"]
        let affectedFiles: Set<String> = ["/test/folder/file1.txt"]
        
        // Toggle selection
        _ = await manager.toggleSelection(
            for: nodePath,
            affectedPaths: affectedPaths,
            affectedFiles: affectedFiles
        )
        
        let state = await manager.getSelectionState()
        XCTAssertFalse(state.paths.isEmpty, "Should have selected paths after toggle")
        XCTAssertFalse(state.files.isEmpty, "Should have selected files after toggle")
    }
    
    func testClearAllResetsState() async {
        let manager = SelectionManager()
        let nodePath = "/test/folder"
        let affectedPaths: Set<String> = ["/test/folder", "/test/folder/file1.txt"]
        let affectedFiles: Set<String> = ["/test/folder/file1.txt"]
        
        // Select some files
        _ = await manager.toggleSelection(
            for: nodePath,
            affectedPaths: affectedPaths,
            affectedFiles: affectedFiles
        )
        
        // Clear all
        await manager.clearAll()
        
        // Verify cleared
        let state = await manager.getSelectionState()
        XCTAssertTrue(state.paths.isEmpty, "Should have no selected paths after clear")
        XCTAssertTrue(state.files.isEmpty, "Should have no selected files after clear")
        XCTAssertEqual(state.tokens, 0, "Should have zero tokens after clear")
    }
    
    func testSetSelectionFromJSON() async {
        let manager = SelectionManager()
        let selectionJSON = """
        {
            "/test/file1.txt": true,
            "/test/file2.txt": true
        }
        """
        
        await manager.setSelection(from: selectionJSON)
        
        let state = await manager.getSelectionState()
        XCTAssertFalse(state.paths.isEmpty, "Should have paths from valid JSON")
    }
    
    func testSetSelectionFromInvalidJSON() async {
        let manager = SelectionManager()
        let invalidJSON = "{ invalid json }"
        
        // Should not crash on invalid JSON
        await manager.setSelection(from: invalidJSON)
        
        let state = await manager.getSelectionState()
        XCTAssertTrue(state.paths.isEmpty, "Should have no paths from invalid JSON")
    }
}