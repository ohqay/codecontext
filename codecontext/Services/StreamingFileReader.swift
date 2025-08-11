import Foundation

/// Async sequence for streaming file content line by line
nonisolated struct FileLineSequence: AsyncSequence, Sendable {
    typealias Element = String

    let url: URL
    let encoding: String.Encoding
    let chunkSize: Int

    init(url: URL, encoding: String.Encoding = .utf8, chunkSize: Int = 65536) {
        self.url = url
        self.encoding = encoding
        self.chunkSize = chunkSize
    }

    func makeAsyncIterator() -> FileLineIterator {
        FileLineIterator(url: url, encoding: encoding, chunkSize: chunkSize)
    }
}

/// Iterator for streaming file lines
final nonisolated class FileLineIterator: AsyncIteratorProtocol {
    typealias Element = String

    private let url: URL
    private let encoding: String.Encoding
    private let chunkSize: Int
    private var fileHandle: FileHandle?
    private var buffer: String = ""
    private var isComplete = false

    init(url: URL, encoding: String.Encoding, chunkSize: Int) {
        self.url = url
        self.encoding = encoding
        self.chunkSize = chunkSize
    }

    func next() async throws -> String? {
        // Initialize file handle on first call
        if fileHandle == nil {
            fileHandle = try FileHandle(forReadingFrom: url)
        }

        guard let handle = fileHandle else { return nil }

        // Process buffered content
        while true {
            // Check for a complete line in buffer
            if let lineEnd = buffer.firstIndex(of: "\n") {
                let line = String(buffer[..<lineEnd])
                buffer.removeSubrange(...lineEnd)
                return line
            }

            // If file is complete, return remaining buffer or nil
            if isComplete {
                if !buffer.isEmpty {
                    let remaining = buffer
                    buffer = ""
                    return remaining
                }
                try? handle.close()
                return nil
            }

            // Read more data
            let data = handle.readData(ofLength: chunkSize)
            if data.isEmpty {
                isComplete = true
                continue // Process any remaining buffer content
            }

            // Append to buffer
            if let chunk = String(data: data, encoding: encoding) {
                buffer.append(chunk)
            }
        }
    }
}

/// High-performance streaming file reader
nonisolated actor StreamingFileReader {
    /// Read file content as an async stream of lines
    nonisolated static func lines(from url: URL, encoding: String.Encoding = .utf8) -> FileLineSequence {
        FileLineSequence(url: url, encoding: encoding)
    }

    /// Read file in chunks for processing
    static func chunks(
        from url: URL,
        chunkSize: Int = 65536,
        process: @escaping (Data) async throws -> Void
    ) async throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        while true {
            let chunk = handle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }

            try await process(chunk)

            // Yield to prevent blocking
            await Task.yield()
        }
    }

    /// Stream file content with progress reporting
    static func streamWithProgress(
        from url: URL,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void,
        onChunk: @escaping @Sendable (String) async -> Void
    ) async throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let totalSize = (attributes[.size] as? Int64) ?? 0
        var bytesRead: Int64 = 0

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let chunkSize = 65536 // 64KB chunks

        while true {
            let chunk = handle.readData(ofLength: chunkSize)
            guard !chunk.isEmpty else { break }

            bytesRead += Int64(chunk.count)
            onProgress(bytesRead, totalSize)

            if let text = String(data: chunk, encoding: .utf8) {
                await onChunk(text)
            }

            // Yield periodically
            await Task.yield()
        }
    }

    /// Efficiently count lines in a file without loading it into memory
    static func countLines(in url: URL) async throws -> Int {
        var lineCount = 0

        for try await _ in lines(from: url) {
            lineCount += 1

            // Yield every 1000 lines to prevent blocking
            if lineCount % 1000 == 0 {
                await Task.yield()
            }
        }

        return lineCount
    }

    /// Read first N lines of a file
    static func head(from url: URL, lines: Int) async throws -> [String] {
        var result: [String] = []
        var count = 0

        for try await line in Self.lines(from: url) {
            result.append(line)
            count += 1
            if count >= lines { break }
        }

        return result
    }

    /// Read last N lines of a file efficiently
    static func tail(from url: URL, lines: Int) async throws -> [String] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        // Get file size
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let fileSize = attributes[.size] as? Int64, fileSize > 0 else {
            return []
        }

        // Read from end in chunks
        let chunkSize: Int64 = 65536
        var buffer = ""
        var linesFound: [String] = []
        var offset = fileSize

        while offset > 0, linesFound.count < lines {
            let readSize = min(chunkSize, offset)
            offset -= readSize

            try handle.seek(toOffset: UInt64(offset))
            let data = handle.readData(ofLength: Int(readSize))

            if let chunk = String(data: data, encoding: .utf8) {
                buffer = chunk + buffer
                let allLines = buffer.split(separator: "\n", omittingEmptySubsequences: false)

                if offset == 0 {
                    // We've read the entire file
                    linesFound = allLines.suffix(lines).map(String.init)
                } else if allLines.count > 1 {
                    // Keep the incomplete first line in buffer
                    buffer = String(allLines[0])
                    linesFound = allLines.dropFirst().map(String.init) + linesFound

                    if linesFound.count > lines {
                        linesFound = Array(linesFound.suffix(lines))
                    }
                }
            }
        }

        return linesFound
    }
}
