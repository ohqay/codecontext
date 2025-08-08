import Foundation

protocol Tokenizer {
    func countTokens(_ text: String) async -> Int
}

// Production tokenizer using Hugging Face swift-transformers
@MainActor
final class TransformersTokenizer: Tokenizer {
    private var tokenizer: Any?
    private let modelName: String
    
    init(modelName: String = "gpt2") {
        self.modelName = modelName
        Task {
            await loadTokenizer()
        }
    }
    
    private func loadTokenizer() async {
        // Note: Requires adding swift-transformers package dependency
        // import Tokenizers
        // do {
        //     tokenizer = try await AutoTokenizer.from(pretrained: modelName)
        // } catch {
        //     print("TransformersTokenizer: Failed to load \(modelName): \(error)")
        // }
    }
    
    func countTokens(_ text: String) async -> Int {
        // When tokenizer is loaded:
        // guard let tokenizer = tokenizer as? AutoTokenizer else {
        //     return await FallbackTokenizer().countTokens(text)
        // }
        // let tokens = tokenizer.encode(text: text)
        // return tokens.count
        
        // Fallback until package is added
        return await FallbackTokenizer().countTokens(text)
    }
}

// Alternative: GPTEncoder implementation (OpenAI-specific)
final class GPTEncoderTokenizer: Tokenizer {
    private let encoder: Any?
    
    init() {
        // Note: Requires adding GPTEncoder package dependency
        // import GPTEncoder
        // encoder = SwiftGPTEncoder()
        encoder = nil
    }
    
    func countTokens(_ text: String) async -> Int {
        // When encoder is available:
        // guard let encoder = encoder as? SwiftGPTEncoder else {
        //     return await FallbackTokenizer().countTokens(text)
        // }
        // let tokens = encoder.encode(text: text)
        // return tokens.count
        
        // Fallback until package is added
        return await FallbackTokenizer().countTokens(text)
    }
}

// Improved fallback tokenizer with better algorithm
struct FallbackTokenizer: Tokenizer {
    func countTokens(_ text: String) async -> Int {
        if text.isEmpty { return 0 }
        
        // Use a more sophisticated approach based on word boundaries and punctuation
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        let punctuationCount = text.filter { $0.isPunctuation }.count
        
        // Most tokenizers split on:
        // - Word boundaries (each word is often 1-2 tokens)
        // - Punctuation (usually separate tokens)
        // - Subword units for longer words
        
        var tokenCount = 0
        
        for word in words {
            if word.count <= 4 {
                tokenCount += 1  // Short words are usually single tokens
            } else if word.count <= 8 {
                tokenCount += 2  // Medium words often split into 2 tokens
            } else {
                // Longer words split roughly every 4-5 characters
                tokenCount += (word.count + 3) / 4
            }
        }
        
        // Add punctuation tokens
        tokenCount += punctuationCount
        
        // Add some tokens for whitespace patterns (newlines, etc.)
        let newlineCount = text.filter { $0.isNewline }.count
        tokenCount += newlineCount
        
        return max(1, tokenCount)
    }
}

// Synchronous wrapper for compatibility with existing code
struct SyncTokenizerAdapter: Tokenizer {
    private let asyncTokenizer: Tokenizer
    
    init(tokenizer: Tokenizer) {
        self.asyncTokenizer = tokenizer
    }
    
    func countTokens(_ text: String) async -> Int {
        await asyncTokenizer.countTokens(text)
    }
    
    // Synchronous version for backward compatibility
    func countTokensSync(_ text: String) -> Int {
        // Use the fallback tokenizer synchronously for now
        let fallback = FallbackTokenizer()
        return Task.synchronous {
            await fallback.countTokens(text)
        }
    }
}

// Helper extension for synchronous task execution
extension Task where Success == Int, Failure == Never {
    static func synchronous(_ operation: @Sendable @escaping () async -> Int) -> Int {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Int = 0
        
        Task {
            result = await operation()
            semaphore.signal()
            return result
        }
        
        semaphore.wait()
        return result
    }
}