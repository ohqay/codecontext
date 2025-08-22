import Foundation

/// Manages file selection operations off the main thread for performance
actor SelectionManager {
    private var selectedPaths: Set<String> = []  // All selected paths (files and directories)
    private var selectedFiles: Set<String> = []  // Only selected files (for token counting)
    private var tokenCounts: [String: Int] = [:]
    private var totalTokens: Int = 0

    /// Toggle selection for a node and all its children
    func toggleSelection(
        for nodePath: String, affectedPaths: Set<String>, affectedFiles: Set<String>
    ) async -> SelectionUpdate {
        print(
            "[DEBUG] SelectionManager: Toggling selection for \(nodePath), affected paths: \(affectedPaths.count), files: \(affectedFiles.count)"
        )
        let startTime = Date()

        // Update selection state
        let wasSelected = selectedPaths.contains(nodePath)
        print("[DEBUG] SelectionManager: Previous state - wasSelected: \(wasSelected)")

        if wasSelected {
            // Deselect - remove all affected paths and files
            for path in affectedPaths {
                selectedPaths.remove(path)
            }

            for filePath in affectedFiles {
                selectedFiles.remove(filePath)
                if let tokens = tokenCounts[filePath] {
                    totalTokens -= tokens
                    tokenCounts.removeValue(forKey: filePath)
                }
            }
            print("[DEBUG] SelectionManager: Deselected, new totalTokens: \(totalTokens)")
        } else {
            // Select - add all affected paths and files
            for path in affectedPaths {
                selectedPaths.insert(path)
            }

            for filePath in affectedFiles {
                selectedFiles.insert(filePath)
                // Token counts will be calculated asynchronously
            }
            print("[DEBUG] SelectionManager: Selected, tokens will be calculated async")
        }

        let duration = Date().timeIntervalSince(startTime)
        print("[DEBUG] SelectionManager: Toggle completed in \(String(format: "%.3fs", duration))")

        return SelectionUpdate(
            selectedPaths: selectedPaths,
            totalTokens: totalTokens,
            affectedPaths: affectedPaths,
            isSelected: !wasSelected
        )
    }

    /// Update token counts for selected files
    func updateTokenCounts(for files: Set<String>, tokenProcessor: TokenProcessor) async {
        let startTime = Date()
        let urls = files.map { URL(fileURLWithPath: $0) }

        // Process in batches to avoid overwhelming the system
        let batchSize = 100
        let batches = urls.chunkedForSelection(into: batchSize)

        for (index, batch) in batches.enumerated() {
            if let results = try? await tokenProcessor.processFiles(batch, maxConcurrency: 8) {
                for result in results {
                    let path = result.url.path
                    tokenCounts[path] = result.tokenCount
                }
            }

            // Report progress for large selections
            if batches.count > 1 {
                let progress = Double(index + 1) / Double(batches.count)
                print("[SelectionManager] Token calculation progress: \(Int(progress * 100))%")
            }
        }

        // Recalculate total
        totalTokens = tokenCounts.values.reduce(0, +)

        let duration = Date().timeIntervalSince(startTime)
        print(
            "[SelectionManager] Token counts updated in \(String(format: "%.3fs", duration)) for \(files.count) files"
        )
    }

    /// Get current selection state
    func getSelectionState() -> (paths: Set<String>, files: Set<String>, tokens: Int) {
        return (selectedPaths, selectedFiles, totalTokens)
    }

    /// Set selection state from JSON (contains only file paths)
    func setSelection(from json: String) async {
        guard let data = json.data(using: .utf8),
            let files = try? JSONDecoder().decode(Set<String>.self, from: data)
        else {
            return
        }

        // JSON only contains files, not directories
        selectedFiles = files
        // selectedPaths will be updated when UI applies selection
        // Token counts will be updated separately
    }

    /// Clear all selections
    func clearAll() {
        selectedPaths.removeAll()
        selectedFiles.removeAll()
        tokenCounts.removeAll()
        totalTokens = 0
    }
}

/// Result of a selection update
struct SelectionUpdate: Sendable {
    let selectedPaths: Set<String>
    let totalTokens: Int
    let affectedPaths: Set<String>
    let isSelected: Bool
}

// Helper extension for chunking
extension Array {
    nonisolated func chunkedForSelection(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
