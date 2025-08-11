@testable import codecontext
import Foundation
import Testing

/// Comprehensive tests for TokenizerService using tiktoken-rs
/// These tests MUST pass for every build - no exceptions
struct TokenizerServiceTests {
    // MARK: - Initialization Tests

    @Test func tokenizerInitialization() async throws {
        // Test the shared instance initialization
        try await TokenizerService.shared.initialize()

        // Should be ready after initialization
        let isReady = await TokenizerService.shared.isReady
        #expect(isReady, "Tokenizer should be ready after initialization")

        // Should be able to tokenize immediately
        let count = await TokenizerService.shared.countTokens("test")
        #expect(count > 0, "Should be able to tokenize after initialization")
    }

    @Test func tokenizerInitializesOnlyOnce() async throws {
        // Initialize multiple times on shared instance
        try await TokenizerService.shared.initialize()
        try await TokenizerService.shared.initialize()
        try await TokenizerService.shared.initialize()

        // Should still work correctly
        let count = await TokenizerService.shared.countTokens("test")
        #expect(count > 0, "Tokenizer should work after multiple initialization calls")
    }

    // MARK: - Exact Token Count Tests

    @Test func exactTokenCounts() async throws {
        // Ensure tokenizer is initialized
        try await TokenizerService.shared.initialize()

        // These are exact token counts for cl100k_base encoding
        // If these fail, the tokenizer is NOT working correctly
        let testCases: [(String, Int)] = [
            // Simple cases
            ("", 0), // Empty string must be 0
            (" ", 1), // Single space
            ("Hello", 1), // Single word
            ("Hello, world!", 4), // Simple phrase

            // Code samples
            ("func test() {}", 4), // Swift function
            ("print(\"Hello\")", 4), // Print statement
            ("let x = 42", 5), // Variable declaration

            // XML samples (important for our use case)
            ("<codebase></codebase>", 7), // Empty codebase
            ("<file>content</file>", 7), // Simple file tag

            // Edge cases
            ("   ", 1), // Multiple spaces
            ("\n", 1), // Newline
            ("\t", 1), // Tab

            // User-provided test cases for verification
            ("The quick brown fox jumped over the lazy dog.", 10), // Classic test sentence
            ("My heel-turn unzipped the mountain.", 9), // Creative sentence
            ("Think of AI like a genius with no soul. It can analyze, synthesize, and generate endlessly. But it's never felt the weight of a decision, the pull of an aesthetic, or why something matters. All that brilliance, waiting for someone who gives a shit.", 55), // Complex paragraph
        ]

        for (input, expectedCount) in testCases {
            let actualCount = await TokenizerService.shared.countTokens(input)
            #expect(actualCount == expectedCount,
                    "Token count mismatch for '\(input.debugDescription)': expected \(expectedCount), got \(actualCount)")
        }
    }

    @Test func largeXMLTokenization() async throws {
        try await TokenizerService.shared.initialize()

        // Test with actual XML structure we generate
        let xml = """
        <codebase>
          <fileTree>
            ├─ src/
            │  ├─ main.swift
            │  └─ utils.swift
          </fileTree>
          <file=main.swift>
          Path: /project/src/main.swift
          `````swift
          import Foundation

          func main() {
              print("Hello, World!")
          }
          `````
          </file=main.swift>
        </codebase>
        """

        let tokenCount = await TokenizerService.shared.countTokens(xml)

        // Should produce a reasonable number of tokens
        #expect(tokenCount > 50, "Large XML should produce many tokens")
        #expect(tokenCount < 200, "Token count should be reasonable for this content")

        // Consistency check - same input should always give same output
        let secondCount = await TokenizerService.shared.countTokens(xml)
        #expect(tokenCount == secondCount, "Token counts must be consistent")
    }

    // MARK: - Encoding/Decoding Tests

    @Test func encodingDecodingRoundTrip() async throws {
        try await TokenizerService.shared.initialize()

        let testTexts = [
            "Hello, World!",
            "func test() { return 42 }",
            "<xml>content</xml>",
            "Special chars: @#$%^&*()",
            "Unicode: 你好世界 🌍",
            "Mixed\n\ttabs\nand  spaces",
        ]

        for text in testTexts {
            let encoded = await TokenizerService.shared.encode(text)
            #expect(!encoded.isEmpty, "Encoding should produce tokens for: \(text)")

            let decoded = await TokenizerService.shared.decode(encoded)
            #expect(decoded == text, "Round trip failed for: \(text)")
        }
    }

    // MARK: - Edge Cases

    @Test func emptyStringReturnsZeroTokens() async throws {
        try await TokenizerService.shared.initialize()

        let count = await TokenizerService.shared.countTokens("")
        #expect(count == 0, "Empty string must return exactly 0 tokens")
    }

    @Test func whitespaceHandling() async throws {
        try await TokenizerService.shared.initialize()

        // Each type of whitespace should produce tokens
        let whitespaceTests: [(String, String)] = [
            (" ", "single space"),
            ("  ", "double space"),
            ("\n", "newline"),
            ("\r\n", "CRLF"),
            ("\t", "tab"),
            ("   \n\t  ", "mixed whitespace"),
        ]

        for (whitespace, description) in whitespaceTests {
            let count = await TokenizerService.shared.countTokens(whitespace)
            #expect(count > 0, "Whitespace should produce tokens: \(description)")
        }
    }

    @Test func unicodeAndEmoji() async throws {
        try await TokenizerService.shared.initialize()

        let unicodeTests = [
            "你好世界", // Chinese
            "مرحبا بالعالم", // Arabic
            "Здравствуй мир", // Russian
            "🚀🎉🌍", // Emojis - full test string
            "café", // Accented characters
        ]

        for text in unicodeTests {
            let count = await TokenizerService.shared.countTokens(text)
            #expect(count > 0, "Unicode/emoji should tokenize: \(text)")

            // Round trip test
            let encoded = await TokenizerService.shared.encode(text)
            let decoded = await TokenizerService.shared.decode(encoded)
            #expect(decoded == text, "Unicode round trip failed: \(text)")
        }
    }

    // MARK: - Performance and Consistency Tests

    @Test func consistentTokenization() async throws {
        try await TokenizerService.shared.initialize()

        let text = "The quick brown fox jumps over the lazy dog."

        // Run tokenization multiple times
        var counts: [Int] = []
        for _ in 0 ..< 10 {
            let count = await TokenizerService.shared.countTokens(text)
            counts.append(count)
        }

        // All counts should be identical
        let firstCount = counts.first!
        for count in counts {
            #expect(count == firstCount, "Token count should be consistent across calls")
        }
    }

    @Test func largeFileTokenization() async throws {
        try await TokenizerService.shared.initialize()

        // Create a large text (simulating a large source file)
        var largeText = ""
        for i in 0 ..< 1000 {
            largeText += "func function\(i)() { print(\"Line \(i)\") }\n"
        }

        let tokenCount = await TokenizerService.shared.countTokens(largeText)

        // Should handle large files without issues
        #expect(tokenCount > 1000, "Large file should produce many tokens")

        // Should be consistent
        let secondCount = await TokenizerService.shared.countTokens(largeText)
        #expect(tokenCount == secondCount, "Large file tokenization should be consistent")
    }

    // MARK: - Critical Accuracy Tests

    @Test func noEstimationEverUsed() async throws {
        try await TokenizerService.shared.initialize()

        // This test ensures we NEVER fall back to estimation
        // If the tokenizer fails, it should fail hard in debug mode

        let testInputs = [
            "Simple text",
            String(repeating: "a", count: 10000), // Large repetitive text
            "<xml>" + String(repeating: "<tag>content</tag>", count: 100) + "</xml>", // Large XML
        ]

        for input in testInputs {
            let count1 = await TokenizerService.shared.countTokens(input)
            let count2 = await TokenizerService.shared.countTokens(input)

            // Exact same count every time (no estimation variance)
            #expect(count1 == count2, "Counts must be identical (no estimation allowed)")

            // Should produce reasonable token counts (not character-based ratios)
            let charCount = input.count
            let ratio = Double(charCount) / Double(count1)

            // cl100k_base typically has 2-5 chars per token for English/code
            // If ratio is exactly 3.0 or similar round number, it's likely estimation
            #expect(ratio != 3.0, "Suspicious ratio suggests estimation is being used")
            #expect(ratio != 2.5, "Suspicious ratio suggests estimation is being used")
            #expect(ratio != 4.0, "Suspicious ratio suggests estimation is being used")
        }
    }

    @Test func xMLContextAccuracy() async throws {
        try await TokenizerService.shared.initialize()

        // Test actual context generation output format
        let contextXML = """
        <codebase>
          <fileTree>
            └─ test.swift
          </fileTree>
          <file=test.swift>
          Path: /test.swift
          `````swift
          print("test")
          `````
          </file=test.swift>
        </codebase>
        """

        let tokenCount = await TokenizerService.shared.countTokens(contextXML)

        // This specific format should produce a predictable token count
        // The exact count will depend on cl100k_base encoding
        #expect(tokenCount > 20, "Context XML should have reasonable token count")
        #expect(tokenCount < 100, "Context XML token count seems too high")

        // Verify adding more content increases tokens proportionally
        let doubleContext = contextXML + contextXML
        let doubleCount = await TokenizerService.shared.countTokens(doubleContext)

        // Should be roughly double (might not be exact due to token boundaries)
        let ratio = Double(doubleCount) / Double(tokenCount)
        #expect(ratio > 1.9 && ratio < 2.1, "Doubling content should roughly double tokens")
    }
}
