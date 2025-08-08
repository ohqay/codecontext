import Foundation
import Dispatch

/// A service that monitors file system changes in a directory using DispatchSource
@MainActor
final class FileSystemWatcher {
    
    // MARK: - Types
    
    enum ChangeType: CustomStringConvertible {
        case created
        case modified
        case deleted
        case renamed
        case unknown
        
        var description: String {
            switch self {
            case .created: return "created"
            case .modified: return "modified"
            case .deleted: return "deleted"
            case .renamed: return "renamed"
            case .unknown: return "unknown"
            }
        }
    }
    
    struct FileChange {
        let url: URL
        let changeType: ChangeType
        let timestamp: Date
    }
    
    // MARK: - Properties
    
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let watchedURL: URL
    private let debounceInterval: TimeInterval
    private var debounceTimer: Timer?
    private var pendingChanges: [FileChange] = []
    
    // Callback for when changes are detected (after debouncing)
    var onChanges: ([FileChange]) -> Void = { _ in }
    
    // MARK: - Initialization
    
    init(url: URL, debounceInterval: TimeInterval = 0.3) {
        self.watchedURL = url
        self.debounceInterval = debounceInterval
    }
    
    deinit {
        // Note: Can't access Timer from nonisolated deinit in Swift 6
        // Timer cleanup is handled in stopWatching()
        dispatchSource?.cancel()
        dispatchSource = nil
    }
    
    // MARK: - Public Methods
    
    func startWatching() throws {
        guard dispatchSource == nil else {
            print("FileSystemWatcher: Already watching \(watchedURL.path)")
            return
        }
        
        // Open file descriptor for the directory
        fileDescriptor = open(watchedURL.path, O_EVTONLY)
        guard fileDescriptor != -1 else {
            throw NSError(domain: "FileSystemWatcher", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to open file descriptor for \(watchedURL.path)"
            ])
        }
        
        // Create dispatch source
        dispatchSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .revoke],
            queue: DispatchQueue.main
        )
        
        guard let source = dispatchSource else {
            close(fileDescriptor)
            fileDescriptor = -1
            throw NSError(domain: "FileSystemWatcher", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Failed to create dispatch source"
            ])
        }
        
        // Set event handler
        source.setEventHandler { [weak self] in
            self?.handleFileSystemEvent()
        }
        
        // Set cancellation handler
        source.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd != -1 {
                close(fd)
                self?.fileDescriptor = -1
            }
        }
        
        // Activate the source
        source.activate()
        
        print("FileSystemWatcher: Started watching \(watchedURL.path)")
    }
    
    func stopWatching() {
        guard let source = dispatchSource else { return }
        
        source.cancel()
        dispatchSource = nil
        
        // Cancel any pending debounce timer
        debounceTimer?.invalidate()
        debounceTimer = nil
        
        print("FileSystemWatcher: Stopped watching \(watchedURL.path)")
    }
    
    // MARK: - Private Methods
    
    private func handleFileSystemEvent() {
        guard let source = dispatchSource else { return }
        
        let eventMask = source.data
        let timestamp = Date()
        
        // Determine change type from event mask
        let changeType = determineChangeType(from: eventMask)
        
        // Create a change event
        let change = FileChange(
            url: watchedURL,
            changeType: changeType,
            timestamp: timestamp
        )
        
        // Add to pending changes
        pendingChanges.append(change)
        
        // Debounce the changes
        debounceChanges()
    }
    
    private func determineChangeType(from eventMask: DispatchSource.FileSystemEvent) -> ChangeType {
        if eventMask.contains(.delete) {
            return .deleted
        } else if eventMask.contains(.rename) {
            return .renamed
        } else if eventMask.contains(.write) {
            return .modified
        } else {
            return .unknown
        }
    }
    
    private func debounceChanges() {
        // Cancel existing timer
        debounceTimer?.invalidate()
        
        // Start new timer
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.flushPendingChanges()
            }
        }
    }
    
    private func flushPendingChanges() {
        guard !pendingChanges.isEmpty else { return }
        
        // Group changes by type and deduplicate
        let changes = deduplicateChanges(pendingChanges)
        pendingChanges.removeAll()
        
        // Notify observers
        onChanges(changes)
    }
    
    private func deduplicateChanges(_ changes: [FileChange]) -> [FileChange] {
        // For simplicity, just return the most recent change for each type
        var latestChanges: [ChangeType: FileChange] = [:]
        
        for change in changes {
            if let existing = latestChanges[change.changeType] {
                if change.timestamp > existing.timestamp {
                    latestChanges[change.changeType] = change
                }
            } else {
                latestChanges[change.changeType] = change
            }
        }
        
        return Array(latestChanges.values).sorted { $0.timestamp < $1.timestamp }
    }
}

// MARK: - Directory Scanner Extension

extension FileSystemWatcher {
    
    /// Scans the watched directory to detect specific file changes
    /// This provides more detailed change information than just directory-level events
    func scanForChanges(using scanner: FileScanner, options: FileScanner.Options, previousFiles: [FileInfo]) -> [FileChange] {
        let currentFiles = scanner.scan(root: watchedURL, options: options)
        var changes: [FileChange] = []
        let timestamp = Date()
        
        // Create sets for efficient lookup
        let previousURLs = Set(previousFiles.map { $0.url })
        let currentURLs = Set(currentFiles.map { $0.url })
        
        // Find new files (created)
        for fileInfo in currentFiles {
            if !previousURLs.contains(fileInfo.url) {
                changes.append(FileChange(
                    url: fileInfo.url,
                    changeType: .created,
                    timestamp: timestamp
                ))
            }
        }
        
        // Find deleted files
        for fileInfo in previousFiles {
            if !currentURLs.contains(fileInfo.url) {
                changes.append(FileChange(
                    url: fileInfo.url,
                    changeType: .deleted,
                    timestamp: timestamp
                ))
            }
        }
        
        // Find modified files (by comparing modification dates)
        let currentFileMap = Dictionary(uniqueKeysWithValues: currentFiles.map { ($0.url, $0) })
        let previousFileMap = Dictionary(uniqueKeysWithValues: previousFiles.map { ($0.url, $0) })
        
        for url in currentURLs.intersection(previousURLs) {
            guard let _ = currentFileMap[url],
                  let previousFile = previousFileMap[url] else { continue }
            
            // Check if file was modified by comparing modification times
            do {
                let currentModDate = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                let previousModDate = try previousFile.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                
                if let current = currentModDate, let previous = previousModDate, current > previous {
                    changes.append(FileChange(
                        url: url,
                        changeType: .modified,
                        timestamp: timestamp
                    ))
                }
            } catch {
                // If we can't get modification date, assume it might be modified
                changes.append(FileChange(
                    url: url,
                    changeType: .modified,
                    timestamp: timestamp
                ))
            }
        }
        
        return changes
    }
}