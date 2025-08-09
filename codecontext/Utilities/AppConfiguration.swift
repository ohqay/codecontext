import Foundation

/// Centralized configuration for file size limits and other app-wide settings
/// 
/// This configuration provides a single source of truth for file handling limits
/// and other configurable values used throughout the app. It follows Swift 6.2
/// best practices by avoiding global mutable state and providing clear,
/// documented constants.
struct AppConfiguration {
    
    // MARK: - File Size Limits
    
    /// Maximum file size in bytes for content inclusion and processing
    /// Default: 5MB (5 * 1024 * 1024 bytes)
    ///
    /// This limit is used by:
    /// - FileScanner for filtering files during directory scanning
    /// - ExclusionDetector for determining if files are too large
    /// - WorkspaceEngine for XML generation
    /// - FileNode for token count calculation
    static let maxFileSizeBytes: UInt64 = 5 * 1024 * 1024
    
    /// Maximum file size in bytes for progressive XML generation
    /// Default: 1MB (1 * 1024 * 1024 bytes)
    ///
    /// This smaller limit is used specifically by ProgressiveXMLGenerator
    /// to avoid memory issues during streaming XML generation while maintaining
    /// responsiveness of the UI.
    static let maxFileSizeBytesForXMLGeneration: UInt64 = 1 * 1024 * 1024
    
    /// Sample size in bytes for content analysis
    /// Default: 1KB (1024 bytes)
    ///
    /// Used by ExclusionDetector to read file samples for binary detection
    /// and sensitive pattern matching without loading entire files into memory.
    static let maxSampleSizeBytes: Int = 1024
    
    // MARK: - Processing Limits
    
    /// Maximum number of files that can be processed in a single operation
    /// Default: 1000 files
    ///
    /// Used by WorkspaceEngine to prevent hanging on operations with too many files
    static let maxProcessableFiles: Int = 1000
    
    /// Maximum number of files for progressive XML generation
    /// Default: 500 files
    ///
    /// Used by ProgressiveXMLGenerator to limit batch operations
    static let maxProgressiveXMLFiles: Int = 500
    
    /// Batch size for processing operations
    /// Default: 10 files
    ///
    /// Used for processing files in batches to maintain UI responsiveness
    static let processingBatchSize: Int = 10
    
    // MARK: - Performance Settings
    
    /// Token estimation ratio (characters per token)
    /// Default: 4 characters per token
    ///
    /// Used for quick token count estimation without expensive tokenization
    static let charactersPerTokenEstimate: Int = 4
    
    /// File system change throttle limit
    /// Default: 100 changes
    ///
    /// Maximum number of file system changes to process in a single batch
    /// to avoid excessive UI updates
    static let maxFileSystemChanges: Int = 100
    
    /// File selection warning threshold
    /// Default: 100 files
    ///
    /// Number of files selected that triggers a performance warning
    static let fileSelectionWarningThreshold: Int = 100
    
    // MARK: - Utility Methods
    
    /// Convert bytes to a human-readable string format
    /// - Parameter bytes: Number of bytes
    /// - Returns: Formatted string (e.g., "5.0 MB", "1.5 KB")
    static func formatBytes(_ bytes: UInt64) -> String {
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
    
    /// Check if a file size exceeds the general limit
    /// - Parameter sizeBytes: File size in bytes
    /// - Returns: True if file exceeds the limit
    static func exceedsGeneralSizeLimit(_ sizeBytes: UInt64) -> Bool {
        return sizeBytes > maxFileSizeBytes
    }
    
    /// Check if a file size exceeds the XML generation limit
    /// - Parameter sizeBytes: File size in bytes
    /// - Returns: True if file exceeds the XML generation limit
    static func exceedsXMLGenerationSizeLimit(_ sizeBytes: UInt64) -> Bool {
        return sizeBytes > maxFileSizeBytesForXMLGeneration
    }
}

// MARK: - Environment-based Configuration

extension AppConfiguration {
    
    /// Runtime configuration that can be adjusted based on environment or user preferences
    /// 
    /// While the main configuration uses static constants for predictable behavior,
    /// this nested type provides a way to override values at runtime if needed
    /// for testing, debugging, or user customization.
    @MainActor
    final class Runtime {
        
        /// Shared instance for runtime configuration overrides
        /// 
        /// Note: While this uses a singleton pattern, it's isolated to @MainActor
        /// and used only for runtime overrides, following Swift 6.2 best practices.
        static let shared = Runtime()
        
        private init() {}
        
        /// Override for maximum file size (defaults to AppConfiguration.maxFileSizeBytes)
        private var _maxFileSizeBytesOverride: UInt64?
        
        /// Get the effective maximum file size (override or default)
        var maxFileSizeBytes: UInt64 {
            return _maxFileSizeBytesOverride ?? AppConfiguration.maxFileSizeBytes
        }
        
        /// Set a runtime override for maximum file size
        /// - Parameter size: New maximum file size in bytes
        func setMaxFileSizeOverride(_ size: UInt64) {
            _maxFileSizeBytesOverride = size
        }
        
        /// Clear the runtime override and use default value
        func clearMaxFileSizeOverride() {
            _maxFileSizeBytesOverride = nil
        }
    }
}