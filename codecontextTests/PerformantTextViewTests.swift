@testable import codecontext
import AppKit
import SwiftUI
import XCTest

@MainActor
final class PerformantTextViewTests: XCTestCase {
    
    func testPerformantTextViewInitialization() {
        let text = "Sample text content"
        let performantTextView = PerformantTextView(text: text)
        
        // Test that the view stores the correct text and font
        XCTAssertEqual(performantTextView.text, text, "Should store the provided text")
        XCTAssertEqual(performantTextView.font, .monospacedSystemFont(ofSize: 14, weight: .regular), "Should use default monospaced font")
    }
    
    func testPerformantTextViewWithCustomFont() {
        let text = "Sample text content"
        let customFont = NSFont.systemFont(ofSize: 16)
        let performantTextView = PerformantTextView(text: text, font: customFont)
        
        // Test that the view stores the correct text and custom font
        XCTAssertEqual(performantTextView.text, text, "Should store the provided text")
        XCTAssertEqual(performantTextView.font, customFont, "Should store the provided custom font")
    }
    
    func testPerformantTextViewDefaultFontProperties() {
        let performantTextView = PerformantTextView(text: "Test")
        let defaultFont = performantTextView.font
        
        // Test that default font is monospaced with correct properties
        XCTAssertTrue(defaultFont.isFixedPitch, "Default font should be monospaced")
        XCTAssertEqual(defaultFont.pointSize, 14, "Default font should be 14pt")
    }
    
    func testBoundaryManagerIntegration() {
        // Test that PerformantTextView can work with boundary-wrapped content
        let originalContent = "Test content for boundary cleaning"
        let wrappedContent = BoundaryManager.wrap(originalContent, type: .file)
        
        // Should be able to create view with boundary-wrapped content
        let performantTextView = PerformantTextView(text: wrappedContent)
        XCTAssertEqual(performantTextView.text, wrappedContent, "Should store boundary-wrapped content")
        
        // Test that BoundaryManager can clean the content
        let cleanedContent = BoundaryManager.cleanForDisplay(wrappedContent)
        XCTAssertEqual(cleanedContent.trimmingCharacters(in: .whitespacesAndNewlines), originalContent, "BoundaryManager should clean content correctly")
        XCTAssertFalse(cleanedContent.contains("CODECONTEXT"), "Cleaned content should not contain boundary markers")
    }
    
    func testPerformantTextViewHandlesDifferentTextSizes() {
        // Test with empty content
        let emptyView = PerformantTextView(text: "")
        XCTAssertEqual(emptyView.text, "", "Should handle empty text")
        
        // Test with small content
        let smallText = "Hello, World!"
        let smallView = PerformantTextView(text: smallText)
        XCTAssertEqual(smallView.text, smallText, "Should handle small text")
        
        // Test with large content
        let largeText = String(repeating: "This is a line of text with some content.\n", count: 1000)
        let largeView = PerformantTextView(text: largeText)
        XCTAssertEqual(largeView.text, largeText, "Should handle large text")
        XCTAssertTrue(largeView.text.count > 40000, "Large text should be substantially large")
    }
    
    func testPerformantTextViewHandlesSpecialCharacters() {
        let specialText = "Special chars: @#$%^&*(){}[]|\\:;\"'<>?,./ Unicode: 你好世界 🌍 café naïve"
        let performantTextView = PerformantTextView(text: specialText)
        
        XCTAssertEqual(performantTextView.text, specialText, "Should handle special characters and unicode")
    }
    
    func testPerformantTextViewMultilineContent() {
        let multilineText = """
        Line 1: This is the first line
        Line 2: This is the second line
        Line 3: This is the third line
        
        Line 5: This line has empty line above
        """
        
        let performantTextView = PerformantTextView(text: multilineText)
        XCTAssertEqual(performantTextView.text, multilineText, "Should handle multiline content")
        XCTAssertTrue(performantTextView.text.contains("\n"), "Should preserve newlines")
    }
    
    func testPerformantTextViewPerformanceCharacteristics() {
        // Test that the view can handle very large content without issues
        let veryLargeText = String(repeating: "Performance test content with sufficient length to test handling.\n", count: 10000)
        
        // This should complete quickly without performance issues
        let startTime = CFAbsoluteTimeGetCurrent()
        let performantTextView = PerformantTextView(text: veryLargeText)
        let endTime = CFAbsoluteTimeGetCurrent()
        
        XCTAssertEqual(performantTextView.text, veryLargeText, "Should handle very large content")
        XCTAssertLessThan(endTime - startTime, 0.1, "Should create view quickly even with large content")
    }
}