import Foundation

struct FileInfo: Identifiable {
    let id = UUID()
    let url: URL
    let isDirectory: Bool
    let size: UInt64
}

final class FileScanner {
    struct Options {
        let followSymlinks: Bool = false
        let maxFileSizeBytes: UInt64 = 5 * 1024 * 1024 // 5 MB sensible default
        let ignoreRules: IgnoreRules
    }

    func scan(root: URL, options: Options) -> [FileInfo] {
        var results: [FileInfo] = []
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey], options: [.skipsPackageDescendants, .skipsHiddenFiles]) else {
            return []
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
                if !isDir && size > options.maxFileSizeBytes {
                    continue
                }
                // Very rough binary filter: skip non-UTF8
                if !isDir {
                    if let data = try? Data(contentsOf: fileURL), String(data: data, encoding: .utf8) == nil {
                        continue
                    }
                }
                results.append(FileInfo(url: fileURL, isDirectory: isDir, size: size))
            } catch {
                // Exclude unreadable entries silently per SPEC
                continue
            }
        }
        results.sort { $0.url.path < $1.url.path }
        return results
    }
}

