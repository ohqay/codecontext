import Foundation
import Tokenizers
import CryptoKit

protocol Tokenizer: Sendable {
    func countTokens(_ text: String) async throws -> Int
    func estimateTokens(_ text: String, languageHint: String?) -> Int
}

/// Constants for token estimation ratios based on 2025 research
private enum TokenRatios {
    // Character-to-token ratios for different file types
    // Based on GPT-4 tokenizer efficiency improvements and code-specific patterns
    static let swift: Double = 3.2          // Swift has moderate density
    static let python: Double = 3.5         // Python improved with GPT-4 indentation handling  
    static let javascript: Double = 3.0     // JS has more punctuation and operators
    static let typescript: Double = 3.0     // Similar to JS
    static let java: Double = 3.4           // Java has verbose syntax
    static let kotlin: Double = 3.2         // More concise than Java
    static let csharp: Double = 3.4         // Similar to Java
    static let cpp: Double = 2.8            // C++ has many operators and symbols
    static let c: Double = 2.9              // Similar to C++
    static let rust: Double = 3.1           // Rust has moderate token density
    static let go: Double = 3.3             // Go has clean syntax
    static let html: Double = 2.5           // HTML has many angle brackets
    static let xml: Double = 2.5            // Similar to HTML
    static let css: Double = 2.7            // CSS has many colons, semicolons
    static let json: Double = 2.2           // JSON has lots of punctuation
    static let yaml: Double = 3.8           // YAML is more text-like
    static let markdown: Double = 4.2       // Closest to natural language
    static let text: Double = 4.0           // Natural language baseline
    static let code: Double = 3.0           // Generic code fallback
}

// Production tokenizer using intelligent estimation for performance
@MainActor
final class HuggingFaceTokenizer: Tokenizer {
    private var actualTokenizer: (any Tokenizers.Tokenizer)?
    private let modelName: String
    private var tokenCache = NSCache<NSString, NSNumber>()
    private let cacheMaxSize = 1000 // Increased cache size
    
    // Configuration constants
    private let actualTokenizationThreshold = 5000 // Use actual tokenization for smaller files
    private let maxFileSize = 1_000_000 // 1MB limit to avoid memory issues
    
    init(modelName: String = "gpt2") {
        self.modelName = modelName
        tokenCache.countLimit = cacheMaxSize
    }
    
    private func ensureTokenizerLoaded() async throws {
        if actualTokenizer == nil {
            actualTokenizer = try await AutoTokenizer.from(pretrained: modelName)
        }
    }
    
    /// Primary method - intelligently chooses between actual tokenization and estimation
    func countTokens(_ text: String) async throws -> Int {
        // Handle empty or very large texts
        guard !text.isEmpty else { return 0 }
        guard text.count < maxFileSize else { 
            return estimateTokens(text, languageHint: nil)
        }
        
        // Create stable cache key using SHA256 hash
        let cacheKey = NSString(string: createStableCacheKey(from: text))
        if let cached = tokenCache.object(forKey: cacheKey) {
            return cached.intValue
        }
        
        let tokenCount: Int
        
        // For small to medium files, use actual tokenization for accuracy
        if text.count <= actualTokenizationThreshold {
            tokenCount = try await performActualTokenization(text)
        } else {
            // For large files, use smart estimation for performance
            tokenCount = estimateTokens(text, languageHint: nil)
        }
        
        // Cache the result
        tokenCache.setObject(NSNumber(value: tokenCount), forKey: cacheKey)
        
        return tokenCount
    }
    
    /// Estimate tokens using language-aware ratios
    func estimateTokens(_ text: String, languageHint: String?) -> Int {
        guard !text.isEmpty else { return 0 }
        
        let ratio = getRatioForLanguage(languageHint)
        let estimated = max(1, Int(Double(text.count) / ratio))
        
        return estimated
    }
    
    /// Perform actual tokenization for accurate counts
    private func performActualTokenization(_ text: String) async throws -> Int {
        try await ensureTokenizerLoaded()
        
        guard let tokenizer = actualTokenizer else {
            throw NSError(domain: "Tokenizer", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to load tokenizer model"
            ])
        }
        
        // Encode the text to get token IDs
        let encoded = tokenizer.encode(text: text)
        return encoded.count
    }
    
    /// Create stable cache key using content hash instead of hashValue
    private func createStableCacheKey(from text: String) -> String {
        let data = Data(text.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Get character-to-token ratio based on language hint
    private func getRatioForLanguage(_ languageHint: String?) -> Double {
        guard let hint = languageHint?.lowercased() else { 
            return TokenRatios.code 
        }
        
        switch hint {
        case "swift":
            return TokenRatios.swift
        case "python", "py":
            return TokenRatios.python
        case "javascript", "js":
            return TokenRatios.javascript
        case "typescript", "ts":
            return TokenRatios.typescript
        case "java":
            return TokenRatios.java
        case "kotlin":
            return TokenRatios.kotlin
        case "csharp", "cs", "c#":
            return TokenRatios.csharp
        case "cpp", "c++", "cxx":
            return TokenRatios.cpp
        case "c":
            return TokenRatios.c
        case "rust", "rs":
            return TokenRatios.rust
        case "go":
            return TokenRatios.go
        case "html":
            return TokenRatios.html
        case "xml":
            return TokenRatios.xml
        case "css":
            return TokenRatios.css
        case "json":
            return TokenRatios.json
        case "yaml", "yml":
            return TokenRatios.yaml
        case "markdown", "md":
            return TokenRatios.markdown
        case "txt", "text":
            return TokenRatios.text
        default:
            return TokenRatios.code
        }
    }
}