import Foundation

/// High-performance async file reader
actor AsyncFileReader {
    static let shared = AsyncFileReader()

    private init() {}

    /// Read file asynchronously without blocking
    func readFile(at url: URL) async throws -> String {
        // Use async URL loading which doesn't block the calling thread
        let (data, _) = try await URLSession.shared.data(from: url)

        guard let text = String(data: data, encoding: .utf8) else {
            throw FileReaderError.encodingError
        }

        return text
    }

    /// Read file data asynchronously
    func readFileData(at url: URL) async throws -> Data {
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }

    /// Stream file contents line by line for memory efficiency
    func streamLines(from url: URL) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let handle = try FileHandle(forReadingFrom: url)
                    defer { try? handle.close() }

                    var buffer = Data()
                    let chunkSize = 65536 // 64KB chunks

                    while true {
                        let chunk = try handle.read(upToCount: chunkSize) ?? Data()

                        if chunk.isEmpty {
                            // Process any remaining buffer
                            if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8) {
                                continuation.yield(line)
                            }
                            break
                        }

                        buffer.append(chunk)

                        // Process complete lines
                        while let newlineIndex = buffer.firstIndex(of: 10) { // ASCII newline
                            let lineData = buffer[..<newlineIndex]
                            if let line = String(data: lineData, encoding: .utf8) {
                                continuation.yield(line)
                            }
                            buffer = buffer[(newlineIndex + 1)...]
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Read file with FileHandle for better control
    func readFileWithHandle(at url: URL) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                do {
                    let handle = try FileHandle(forReadingFrom: url)
                    defer { try? handle.close() }

                    let data = try handle.readToEnd() ?? Data()

                    guard let text = String(data: data, encoding: .utf8) else {
                        continuation.resume(throwing: FileReaderError.encodingError)
                        return
                    }

                    continuation.resume(returning: text)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

enum FileReaderError: LocalizedError {
    case encodingError

    nonisolated var errorDescription: String? {
        switch self {
        case .encodingError:
            return "Failed to decode file as UTF-8 text"
        }
    }
}
