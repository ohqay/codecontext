@testable import codecontext
import XCTest

@MainActor
final class PerformantTextViewTests: XCTestCase {
    func testPerformantTextViewInitialization() {
        let text = "Sample text content"
        let view = PerformantTextView(text: text)

        // Test that the view initializes with the correct properties
        XCTAssertEqual(view.text, text)
        XCTAssertNotNil(view.font)
    }

    func testPerformantTextViewWithCustomFont() {
        let text = "Sample text content"
        let customFont = NSFont.systemFont(ofSize: 16)
        let view = PerformantTextView(text: text, font: customFont)

        XCTAssertEqual(view.text, text)
        XCTAssertEqual(view.font, customFont)
    }

    func testPerformantTextViewHandlesSmallText() {
        // Verify PerformantTextView works well with small content
        let smallText = "Hello, World!"
        let view = PerformantTextView(text: smallText)

        XCTAssertEqual(view.text, smallText)
    }

    func testPerformantTextViewHandlesLargeText() {
        // Verify PerformantTextView works well with large content
        let largeText = String(repeating: "This is a line of text.\n", count: 5000)
        let view = PerformantTextView(text: largeText)

        XCTAssertEqual(view.text, largeText)
        XCTAssertTrue(largeText.count > 100_000, "Test text should be large")
    }

    func testPerformantTextViewDefaultFont() {
        let text = "Sample text"
        let view = PerformantTextView(text: text)

        // Should use monospaced font by default
        XCTAssertTrue(view.font.isFixedPitch, "Default font should be monospaced")
    }
}
