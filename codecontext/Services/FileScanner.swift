import Foundation

struct FileInfo: Identifiable {
    let id = UUID()
    let url: URL
    let isDirectory: Bool
    let size: UInt64
}

final class FileScanner {
    struct Options {
        let followSymlinks: Bool
        let maxFileSizeBytes: UInt64
        let ignoreRules: IgnoreRules
        let enableExclusionDetection: Bool
        let allowOverrides: Set<URL>

        init(
            followSymlinks: Bool = false,
            maxFileSizeBytes: UInt64 = AppConfiguration.maxFileSizeBytes,
            ignoreRules: IgnoreRules,
            enableExclusionDetection: Bool = true,
            allowOverrides: Set<URL> = []
        ) {
            self.followSymlinks = followSymlinks
            self.maxFileSizeBytes = maxFileSizeBytes
            self.ignoreRules = ignoreRules
            self.enableExclusionDetection = enableExclusionDetection
            self.allowOverrides = allowOverrides
        }
    }

    struct ScanResult {
        let includedFiles: [FileInfo]
        let exclusions: [ExclusionDetector.ExclusionResult]
    }

    private let exclusionDetector = ExclusionDetector()

    func scan(root: URL, options: Options) -> [FileInfo] {
        let result = scanWithExclusions(root: root, options: options)
        return result.includedFiles
    }

    func scanWithExclusions(root: URL, options: Options) -> ScanResult {
        var includedFiles: [FileInfo] = []
        var exclusions: [ExclusionDetector.ExclusionResult] = []

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey], options: [.skipsPackageDescendants, .skipsHiddenFiles]) else {
            return ScanResult(includedFiles: [], exclusions: [])
        }

        for case let fileURL as URL in enumerator {
            do {
                let rv = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
                if rv.isSymbolicLink == true && !options.followSymlinks {
                    enumerator.skipDescendants()
                    continue
                }

                let isDir = rv.isDirectory ?? false
                if options.ignoreRules.isIgnored(path: fileURL.path, isDirectory: isDir) {
                    if isDir { enumerator.skipDescendants() }
                    continue
                }

                let size = UInt64(rv.fileSize ?? 0)

                // Skip directories, add them directly
                if isDir {
                    includedFiles.append(FileInfo(url: fileURL, isDirectory: true, size: size))
                    continue
                }

                // Check for exclusions if enabled
                var shouldExclude = false
                if options.enableExclusionDetection && !options.allowOverrides.contains(fileURL) {
                    if let exclusion = exclusionDetector.checkForExclusion(url: fileURL, size: size) {
                        exclusions.append(exclusion)
                        shouldExclude = true
                    }
                } else {
                    // Fallback to legacy exclusion logic
                    if size > options.maxFileSizeBytes {
                        shouldExclude = true
                    } else if let data = try? Data(contentsOf: fileURL), String(data: data, encoding: .utf8) == nil {
                        shouldExclude = true
                    }
                }

                if !shouldExclude {
                    includedFiles.append(FileInfo(url: fileURL, isDirectory: false, size: size))
                }

            } catch {
                // Exclude unreadable entries silently per SPEC
                continue
            }
        }

        includedFiles.sort { $0.url.path < $1.url.path }
        return ScanResult(includedFiles: includedFiles, exclusions: exclusions)
    }
}
