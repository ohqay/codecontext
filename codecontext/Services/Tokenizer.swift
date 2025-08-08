import Foundation
import Tokenizers

protocol Tokenizer: Sendable {
    func countTokens(_ text: String) async throws -> Int
}

// Production tokenizer using Hugging Face swift-transformers
@MainActor
final class HuggingFaceTokenizer: Tokenizer {
    private var tokenizer: (any Tokenizers.Tokenizer)?
    private let modelName: String
    
    init(modelName: String = "gpt2") {
        self.modelName = modelName
    }
    
    private func ensureTokenizerLoaded() async throws {
        if tokenizer == nil {
            tokenizer = try await AutoTokenizer.from(pretrained: modelName)
        }
    }
    
    func countTokens(_ text: String) async throws -> Int {
        try await ensureTokenizerLoaded()
        
        guard let tokenizer = tokenizer else {
            throw NSError(domain: "Tokenizer", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to load tokenizer model"
            ])
        }
        
        // Encode the text to get token IDs
        let encoded = tokenizer.encode(text: text)
        return encoded.count
    }
}