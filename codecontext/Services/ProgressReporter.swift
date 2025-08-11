import Foundation

/// Manages progress reporting with batched updates to reduce main thread overhead
actor ProgressReporter {
    private var continuation: AsyncStream<ProgressUpdate>.Continuation?
    private var lastUpdateTime = Date.distantPast
    private let minUpdateInterval: TimeInterval = 0.1 // 100ms minimum between updates
    private var pendingUpdate: ProgressUpdate?
    private var updateTask: Task<Void, Never>?

    /// Create a progress stream that batches updates
    func progressStream() -> AsyncStream<ProgressUpdate> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    /// Report progress (will be batched)
    func report(progress: Double, message: String) {
        let update = ProgressUpdate(progress: progress, message: message, timestamp: Date())

        // Check if we should send immediately or batch
        let now = Date()
        if now.timeIntervalSince(lastUpdateTime) >= minUpdateInterval {
            // Send immediately
            continuation?.yield(update)
            lastUpdateTime = now
        } else {
            // Schedule for later
            pendingUpdate = update
            scheduleUpdate()
        }
    }

    /// Finish the progress stream
    func finish() {
        // Send any pending update
        if let pending = pendingUpdate {
            continuation?.yield(pending)
            pendingUpdate = nil
        }

        continuation?.finish()
        continuation = nil
        updateTask?.cancel()
        updateTask = nil
    }

    private func scheduleUpdate() {
        // Cancel any existing scheduled update
        updateTask?.cancel()

        // Schedule new update
        updateTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(minUpdateInterval * 1_000_000_000))

            if !Task.isCancelled, let update = pendingUpdate {
                continuation?.yield(update)
                lastUpdateTime = Date()
                pendingUpdate = nil
            }
        }
    }
}

/// Progress update data
struct ProgressUpdate: Sendable {
    let progress: Double
    let message: String
    let timestamp: Date
}
