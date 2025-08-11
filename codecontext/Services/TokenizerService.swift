import Foundation

/// Centralized tokenizer service using tiktoken-rs via FFI
/// Uses cl100k_base encoding (GPT-4/GPT-3.5-turbo) for accurate tokenization
actor TokenizerService {
    static let shared = TokenizerService()

    private var isInitialized = false

    private init() {}

    /// Initialize the tokenizer at app startup
    /// This MUST be called before any tokenization operations
    func initialize() async throws {
        guard !isInitialized else { return }

        // Initialize the Rust tokenizer via FFI
        let result = tokenizer_initialize()
        guard result == 0 else {
            throw TokenizerError.initializationFailed
        }

        // Verify it's ready
        guard tokenizer_is_ready() == 1 else {
            throw TokenizerError.initializationFailed
        }

        isInitialized = true
        print("[TokenizerService] Successfully initialized with tiktoken-rs (cl100k_base encoding)")

        #if DEBUG
            // Run verification tests in debug builds
            await runInitializationTests()
        #endif
    }

    /// Count tokens in the given text using actual tokenization
    /// - Parameter text: The text to tokenize
    /// - Returns: Exact token count
    func countTokens(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }

        guard isInitialized else {
            #if DEBUG
                fatalError("[TokenizerService] Tokenizer not initialized. Call initialize() at app startup.")
            #else
                print("[TokenizerService] CRITICAL: Tokenizer not initialized!")
                return 0
            #endif
        }

        // Call the Rust FFI function
        let count = text.withCString { cString in
            Int(tokenizer_count_tokens(cString))
        }

        // Check for errors
        guard count >= 0 else {
            print("[TokenizerService] Error tokenizing text")
            return 0
        }

        return count
    }

    /// Encode text to tokens
    func encode(_ text: String) -> [Int] {
        guard !text.isEmpty else { return [] }

        guard isInitialized else {
            #if DEBUG
                fatalError("[TokenizerService] Tokenizer not initialized")
            #else
                return []
            #endif
        }

        // Allocate buffer for tokens (generous estimate based on UTF-8 bytes)
        // Emojis can generate multiple tokens, so use UTF-8 byte count as estimate
        let bufferSize = max(100, text.utf8.count * 2)
        var tokenBuffer = [Int32](repeating: 0, count: bufferSize)

        let tokenCount = text.withCString { cString in
            tokenBuffer.withUnsafeMutableBufferPointer { buffer in
                Int(tokenizer_encode(cString, buffer.baseAddress, bufferSize))
            }
        }

        guard tokenCount > 0 else { return [] }

        // Convert to Int array and trim to actual size
        return Array(tokenBuffer.prefix(tokenCount).map { Int($0) })
    }

    /// Decode tokens back to text
    func decode(_ tokens: [Int]) -> String {
        guard !tokens.isEmpty else { return "" }

        guard isInitialized else {
            #if DEBUG
                fatalError("[TokenizerService] Tokenizer not initialized")
            #else
                return ""
            #endif
        }

        // Convert to Int32 array for FFI
        let int32Tokens = tokens.map { Int32($0) }

        let decodedPtr = int32Tokens.withUnsafeBufferPointer { buffer in
            tokenizer_decode(buffer.baseAddress, buffer.count)
        }

        guard let ptr = decodedPtr else { return "" }

        // Convert C string to Swift String and free the memory
        let result = String(cString: ptr)
        tokenizer_free_string(ptr)

        return result
    }

    /// Check if the tokenizer is ready
    var isReady: Bool {
        isInitialized && tokenizer_is_ready() == 1
    }

    #if DEBUG
        /// Run basic tests to verify tokenizer is working correctly
        /// These tests MUST pass - if they fail, it means tokenization is broken
        private func runInitializationTests() {
            print("[TokenizerService] Running initialization tests...")

            // Test 1: Empty string should produce 0 tokens
            let emptyCount = countTokens("")
            assert(emptyCount == 0, "Empty string should produce 0 tokens")

            // Test 2: Simple text should produce tokens
            let simpleCount = countTokens("Hello, world!")
            assert(simpleCount == 4, "Expected 4 tokens for 'Hello, world!', got \(simpleCount)")

            // Test 3: Encode/decode round trip
            let testText = "Testing round trip"
            let encoded = encode(testText)
            let decoded = decode(encoded)
            assert(decoded == testText, "Encode/decode round trip should preserve text")

            // Test 4: Critical user-provided verification cases
            // These EXACT token counts are required for production accuracy
            let criticalTests: [(String, Int, String)] = [
                ("The quick brown fox jumped over the lazy dog.", 10, "classic test sentence"),
                ("My heel-turn unzipped the mountain.", 9, "creative sentence with hyphenation"),
                ("Think of AI like a genius with no soul. It can analyze, synthesize, and generate endlessly. But it's never felt the weight of a decision, the pull of an aesthetic, or why something matters. All that brilliance, waiting for someone who gives a shit.", 55, "complex paragraph with varied punctuation"),
            ]

            for (text, expectedCount, description) in criticalTests {
                let actualCount = countTokens(text)
                assert(actualCount == expectedCount,
                       "CRITICAL TOKENIZATION ERROR: \(description) - expected \(expectedCount) tokens, got \(actualCount). This indicates a serious tokenization accuracy problem that MUST be fixed before production.")
            }

            // Test 5: Additional accuracy verification
            let accuracyTests: [(String, Int)] = [
                (" ", 1), // Single space
                ("Hello", 1), // Single word
                ("func test() {}", 4), // Swift function
                ("<codebase></codebase>", 7), // XML tags
                ("   ", 1), // Multiple spaces
                ("\n", 1), // Newline
                ("\t", 1), // Tab
            ]

            for (text, expectedCount) in accuracyTests {
                let actualCount = countTokens(text)
                assert(actualCount == expectedCount,
                       "Tokenization accuracy failure for '\(text.debugDescription)': expected \(expectedCount), got \(actualCount)")
            }

            print("[TokenizerService] All initialization tests passed ✓")
            print("[TokenizerService] Tokenization accuracy verified for production use")
        }
    #endif
}

enum TokenizerError: Error {
    case initializationFailed
    case encodingNotSupported(String)
}

extension TokenizerError: LocalizedError {
    nonisolated var errorDescription: String? {
        switch self {
        case .initializationFailed:
            return "Failed to initialize tokenizer with cl100k_base encoding"
        case let .encodingNotSupported(encoding):
            return "Encoding '\(encoding)' is not supported"
        }
    }
}
