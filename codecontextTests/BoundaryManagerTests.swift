@testable import codecontext
import Foundation
import Testing

@MainActor
struct BoundaryManagerTests {
    
    // MARK: - Basic Functionality Tests
    
    @Test func boundaryManagerWrapContent() {
        let content = "test content"
        let wrapped = BoundaryManager.wrap(content, type: .file)
        
        #expect(wrapped.contains("test content"), "Wrapped content should contain original content")
        #expect(wrapped.contains("CODECONTEXT-FILE-START"), "Should contain start marker")
        #expect(wrapped.contains("CODECONTEXT-FILE-END"), "Should contain end marker")
    }
    
    @Test func boundaryManagerExtractContent() {
        let content = "test content"
        let wrapped = BoundaryManager.wrap(content, type: .codebase)
        
        let extracted = BoundaryManager.extract(wrapped, type: .codebase)
        
        #expect(extracted.count == 1, "Should extract exactly one section")
        #expect(extracted.first == content, "Extracted content should match original")
    }
    
    @Test func boundaryManagerRemoveContent() {
        let content = "test content"
        let wrapped = BoundaryManager.wrap(content, type: .userInstructions)
        
        let removed = BoundaryManager.remove(wrapped, type: .userInstructions)
        
        #expect(!removed.contains("test content"), "Removed content should not contain original")
        #expect(!removed.contains("CODECONTEXT-USERINSTR"), "Should not contain boundary markers")
    }
    
    @Test func boundaryManagerCleanForDisplay() {
        let content = "test content"
        let wrapped = BoundaryManager.wrap(content, type: .file)
        
        let cleaned = BoundaryManager.cleanForDisplay(wrapped)
        
        // The cleaned content should not contain boundary markers but may have different whitespace
        #expect(!cleaned.contains("CODECONTEXT"), "Should not contain any boundary markers")
        #expect(cleaned.trimmingCharacters(in: .whitespacesAndNewlines) == content, "Cleaned content should match original after trimming")
    }
    
    // MARK: - Boundary Type Tests
    
    @Test func boundaryManagerHandlesDifferentTypes() {
        let content = "test content"
        
        let codebaseWrapped = BoundaryManager.wrap(content, type: .codebase)
        let fileWrapped = BoundaryManager.wrap(content, type: .file)
        let userInstrWrapped = BoundaryManager.wrap(content, type: .userInstructions)
        let treeWrapped = BoundaryManager.wrap(content, type: .fileTree)
        
        #expect(codebaseWrapped.contains("CODEBASE"), "Should contain CODEBASE type")
        #expect(fileWrapped.contains("FILE"), "Should contain FILE type")
        #expect(userInstrWrapped.contains("USERINSTR"), "Should contain USERINSTR type")
        #expect(treeWrapped.contains("TREE"), "Should contain TREE type")
    }
    
    @Test func boundaryManagerTypeIsolation() {
        let content = "test content"
        let fileWrapped = BoundaryManager.wrap(content, type: .file)
        
        // Should not extract with wrong type
        let codebaseExtracted = BoundaryManager.extract(fileWrapped, type: .codebase)
        #expect(codebaseExtracted.isEmpty, "Should not extract with wrong type")
        
        // Should extract with correct type
        let fileExtracted = BoundaryManager.extract(fileWrapped, type: .file)
        #expect(fileExtracted.count == 1, "Should extract with correct type")
        #expect(fileExtracted.first == content, "Should extract correct content")
    }
    
    // MARK: - Multiple Boundary Tests
    
    @Test func boundaryManagerHandlesMultipleBoundaries() {
        let content1 = "first content"
        let content2 = "second content"
        let content3 = "third content"
        
        let wrapped1 = BoundaryManager.wrap(content1, type: .file)
        let wrapped2 = BoundaryManager.wrap(content2, type: .file)
        let wrapped3 = BoundaryManager.wrap(content3, type: .file)
        
        let combined = "\(wrapped1)\n\(wrapped2)\n\(wrapped3)"
        let extracted = BoundaryManager.extract(combined, type: .file)
        
        #expect(extracted.count == 3, "Should extract all three sections")
        #expect(extracted.contains(content1), "Should contain first content")
        #expect(extracted.contains(content2), "Should contain second content")
        #expect(extracted.contains(content3), "Should contain third content")
    }
    
    @Test func boundaryManagerRemoveSpecificBoundary() {
        let content1 = "keep this"
        let content2 = "remove this"
        
        let wrapped1 = BoundaryManager.wrap(content1, type: .file)
        let wrapped2 = BoundaryManager.wrap(content2, type: .codebase)
        
        let combined = "\(wrapped1)\n\(wrapped2)"
        let removed = BoundaryManager.remove(combined, type: .codebase)
        
        #expect(removed.contains("keep this"), "Should keep file content")
        #expect(!removed.contains("remove this"), "Should remove codebase content")
        #expect(removed.contains("CODECONTEXT-FILE"), "Should keep file boundaries")
        #expect(!removed.contains("CODECONTEXT-CODEBASE"), "Should remove codebase boundaries")
    }
    
    // MARK: - Update Content Tests
    
    @Test func boundaryManagerUpdateContent() {
        let originalContent = "original content"
        let newContent = "updated content"
        let wrapped = BoundaryManager.wrap(originalContent, type: .file)
        
        let updated = BoundaryManager.updateContent(wrapped, type: .file, with: newContent)
        let extracted = BoundaryManager.extract(updated, type: .file)
        
        #expect(extracted.count == 1, "Should have one section after update")
        #expect(extracted.first == newContent, "Should contain updated content")
        #expect(!updated.contains(originalContent), "Should not contain original content")
    }
    
    @Test func boundaryManagerUpdateNonexistentType() {
        let content = "test content"
        let wrapped = BoundaryManager.wrap(content, type: .file)
        
        let updated = BoundaryManager.updateContent(wrapped, type: .codebase, with: "new content")
        
        #expect(updated == wrapped, "Should return unchanged if type not found")
    }
    
    // MARK: - Boundary Detection Tests
    
    @Test func boundaryManagerContainsDetection() {
        let content = "test content"
        let fileWrapped = BoundaryManager.wrap(content, type: .file)
        let codebaseWrapped = BoundaryManager.wrap(content, type: .codebase)
        
        #expect(BoundaryManager.contains(fileWrapped, type: .file), "Should detect file boundaries")
        #expect(!BoundaryManager.contains(fileWrapped, type: .codebase), "Should not detect codebase boundaries in file content")
        #expect(BoundaryManager.contains(codebaseWrapped, type: .codebase), "Should detect codebase boundaries")
    }
    
    // MARK: - Boundary Validation Tests
    
    @Test func boundaryManagerValidateBoundaries() {
        let content = "test content"
        let wrapped = BoundaryManager.wrap(content, type: .file)
        
        let issues = BoundaryManager.validateBoundaries(wrapped)
        #expect(issues.isEmpty, "Valid boundaries should have no issues")
    }
    
    @Test func boundaryManagerValidateMismatchedBoundaries() {
        // Create mismatched boundaries manually
        let invalidXML = """
        <!--CODECONTEXT-FILE-START-ABC123-->
        test content
        <!--CODECONTEXT-FILE-END-XYZ789-->
        <!--CODECONTEXT-FILE-START-DEF456-->
        more content
        """
        
        let issues = BoundaryManager.validateBoundaries(invalidXML)
        #expect(!issues.isEmpty, "Mismatched boundaries should be detected")
    }
    
    // MARK: - Edge Cases Tests
    
    @Test func boundaryManagerHandlesEmptyContent() {
        let emptyContent = ""
        let wrapped = BoundaryManager.wrap(emptyContent, type: .file)
        let extracted = BoundaryManager.extract(wrapped, type: .file)
        
        #expect(extracted.count == 1, "Should handle empty content")
        #expect(extracted.first == "", "Should extract empty string")
    }
    
    @Test func boundaryManagerHandlesWhitespaceContent() {
        let whitespaceContent = "   \n\t  \n   "
        let wrapped = BoundaryManager.wrap(whitespaceContent, type: .file)
        let extracted = BoundaryManager.extract(wrapped, type: .file)
        
        #expect(extracted.count == 1, "Should handle whitespace content")
        #expect(extracted.first == whitespaceContent, "Should preserve whitespace exactly")
    }
    
    @Test func boundaryManagerHandlesSpecialCharacters() {
        let specialContent = "Special chars: @#$%^&*(){}[]|\\:;\"'<>?,./"
        let wrapped = BoundaryManager.wrap(specialContent, type: .file)
        let extracted = BoundaryManager.extract(wrapped, type: .file)
        
        #expect(extracted.count == 1, "Should handle special characters")
        #expect(extracted.first == specialContent, "Should preserve special characters exactly")
    }
    
    @Test func boundaryManagerHandlesUnicodeContent() {
        let unicodeContent = "Unicode: 你好世界 🌍 café naïve"
        let wrapped = BoundaryManager.wrap(unicodeContent, type: .file)
        let extracted = BoundaryManager.extract(wrapped, type: .file)
        
        #expect(extracted.count == 1, "Should handle Unicode content")
        #expect(extracted.first == unicodeContent, "Should preserve Unicode exactly")
    }
    
    @Test func boundaryManagerHandlesMultilineContent() {
        let multilineContent = """
        Line 1
        Line 2
            Indented line
        Line 4
        """
        
        let wrapped = BoundaryManager.wrap(multilineContent, type: .file)
        let extracted = BoundaryManager.extract(wrapped, type: .file)
        
        #expect(extracted.count == 1, "Should handle multiline content")
        #expect(extracted.first == multilineContent, "Should preserve multiline structure exactly")
    }
    
    // MARK: - App Identifier Tests
    
    @Test func boundaryManagerUsesCorrectAppIdentifier() {
        let content = "test"
        let wrapped = BoundaryManager.wrap(content, type: .file)
        
        #expect(wrapped.contains("CODECONTEXT"), "Should use CODECONTEXT app identifier")
        #expect(!wrapped.contains("OTHERAPP"), "Should not use different app identifier")
    }
}