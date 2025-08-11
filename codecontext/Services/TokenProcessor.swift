import Foundation

/// Background actor for processing tokens off the main thread
actor TokenProcessor {
    private let fileReader: AsyncFileReader

    init() {
        fileReader = AsyncFileReader.shared
    }

    /// Process files in parallel and calculate tokens
    func processFiles(_ fileURLs: [URL], maxConcurrency: Int = 8) async throws -> [FileTokenResult] {
        try await withThrowingTaskGroup(of: FileTokenResult?.self) { group in
            var results: [FileTokenResult] = []
            var activeCount = 0
            var urlIterator = fileURLs.makeIterator()

            // Process files with controlled concurrency
            while let url = urlIterator.next() {
                // Wait if we've hit concurrency limit
                while activeCount >= maxConcurrency {
                    if let result = try await group.next() {
                        if let fileResult = result {
                            results.append(fileResult)
                        }
                        activeCount -= 1
                    }
                }

                // Add new task
                group.addTask {
                    try? Task.checkCancellation()
                    return await self.processFile(url)
                }
                activeCount += 1
            }

            // Collect remaining results
            for try await result in group {
                if let fileResult = result {
                    results.append(fileResult)
                }
            }

            return results
        }
    }

    /// Process a single file and return token count
    func processFile(_ url: URL) async -> FileTokenResult? {
        // Check file size first
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? Int,
              fileSize < 10 * 1024 * 1024 // Skip files > 10MB
        else {
            return nil
        }

        // Read file content asynchronously
        guard let content = try? await fileReader.readFile(at: url) else {
            return nil
        }

        // Calculate tokens using actual tokenization
        let tokenCount = await TokenizerService.shared.countTokens(content)

        return FileTokenResult(
            url: url,
            tokenCount: tokenCount,
            fileSize: fileSize,
            content: content
        )
    }

    /// Batch process files and yield results as they complete
    func streamProcessFiles(_ fileURLs: [URL]) -> AsyncThrowingStream<FileTokenResult, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await withThrowingTaskGroup(of: FileTokenResult?.self) { group in
                        // Add all file processing tasks
                        for url in fileURLs {
                            group.addTask {
                                await self.processFile(url)
                            }
                        }

                        // Stream results as they complete
                        for try await result in group {
                            if let fileResult = result {
                                continuation.yield(fileResult)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

/// Result of processing a file for tokens
struct FileTokenResult: Sendable {
    let url: URL
    let tokenCount: Int
    let fileSize: Int
    let content: String
}
