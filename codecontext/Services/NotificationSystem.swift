import Foundation
import SwiftUI

/// Service for managing non-intrusive notifications about file exclusions
@MainActor
@Observable
final class NotificationSystem {
    
    // MARK: - Types
    
    struct ExclusionNotification: Identifiable {
        let id = UUID()
        let exclusions: [ExclusionDetector.ExclusionResult]
        let timestamp = Date()
        var isVisible = true
        
        var title: String {
            let count = exclusions.count
            if count == 1 {
                return "1 file excluded"
            } else {
                return "\(count) files excluded"
            }
        }
        
        var summary: String {
            let grouped = Dictionary(grouping: exclusions) { $0.exclusionType }
            var summaryParts: [String] = []
            
            if let binaryFiles = grouped[.binary] {
                summaryParts.append("\(binaryFiles.count) binary file\(binaryFiles.count == 1 ? "" : "s")")
            }
            
            let largeFiles = grouped.compactMap { key, value in
                if case .tooLarge = key { return value }
                return nil
            }.flatMap { $0 }
            if !largeFiles.isEmpty {
                summaryParts.append("\(largeFiles.count) large file\(largeFiles.count == 1 ? "" : "s")")
            }
            
            let sensitiveFiles = grouped.compactMap { key, value in
                if case .sensitiveFile = key { return value }
                return nil
            }.flatMap { $0 }
            if !sensitiveFiles.isEmpty {
                summaryParts.append("\(sensitiveFiles.count) sensitive file\(sensitiveFiles.count == 1 ? "" : "s")")
            }
            
            return summaryParts.joined(separator: ", ")
        }
    }
    
    // MARK: - Properties
    
    private(set) var currentNotification: ExclusionNotification?
    private var autoHideTask: Task<Void, Never>?
    
    // Configurable timing
    var autoHideDelay: TimeInterval = 5.0 // 5 seconds
    
    // MARK: - Public Methods
    
    /// Shows a notification for excluded files
    func showExclusionNotification(exclusions: [ExclusionDetector.ExclusionResult]) {
        guard !exclusions.isEmpty else { return }
        
        // Cancel any existing auto-hide task
        autoHideTask?.cancel()
        
        // Create new notification
        let notification = ExclusionNotification(exclusions: exclusions)
        currentNotification = notification
        
        // Start auto-hide timer
        startAutoHideTimer()
    }
    
    /// Manually dismisses the current notification
    func dismissNotification() {
        autoHideTask?.cancel()
        currentNotification = nil
    }
    
    /// Includes files that were excluded, returning the URLs that should be added
    func includeExcludedFiles() -> [URL] {
        guard let notification = currentNotification else { return [] }
        
        let includableFiles = notification.exclusions
            .filter { $0.canOverride }
            .map { $0.url }
        
        // Dismiss the notification after inclusion
        dismissNotification()
        
        return includableFiles
    }
    
    // MARK: - Private Methods
    
    private func startAutoHideTimer() {
        autoHideTask = Task {
            try? await Task.sleep(for: .seconds(autoHideDelay))
            
            if !Task.isCancelled {
                currentNotification = nil
            }
        }
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let fileExclusionsDetected = Notification.Name("fileExclusionsDetected")
    static let includeExcludedFiles = Notification.Name("includeExcludedFiles")
}