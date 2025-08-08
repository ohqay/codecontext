import Foundation

/// Service for detecting files that should be excluded from scanning
final class ExclusionDetector {
    
    // MARK: - Constants
    
    private static let MAX_FILE_SIZE_BYTES: UInt64 = 5 * 1024 * 1024 // 5 MB
    private static let MAX_SAMPLE_SIZE = 1024 // Read first 1KB to check for binary content
    
    // MARK: - Exclusion Types
    
    enum ExclusionType: Equatable, Hashable {
        case binary
        case tooLarge(size: UInt64)
        case sensitiveFile(reason: SensitiveReason)
        
        enum SensitiveReason: String, CaseIterable {
            case dotenvFile = "Environment file"
            case apiKeyPattern = "Contains API key patterns"
            case secretPattern = "Contains secret patterns"
            case privateKey = "Contains private key"
        }
        
        var displayReason: String {
            switch self {
            case .binary:
                return "Binary file"
            case .tooLarge(let size):
                return "Large file (\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))"
            case .sensitiveFile(let reason):
                return reason.rawValue
            }
        }
    }
    
    struct ExclusionResult {
        let url: URL
        let exclusionType: ExclusionType
        let canOverride: Bool
        
        init(url: URL, exclusionType: ExclusionType, canOverride: Bool = true) {
            self.url = url
            self.exclusionType = exclusionType
            self.canOverride = canOverride
        }
    }
    
    // MARK: - Public Methods
    
    /// Checks if a file should be excluded and returns exclusion information
    func checkForExclusion(url: URL, size: UInt64) -> ExclusionResult? {
        // Check file size first (most efficient)
        if size > Self.MAX_FILE_SIZE_BYTES {
            return ExclusionResult(url: url, exclusionType: .tooLarge(size: size))
        }
        
        // Check for sensitive file patterns by filename
        if let sensitiveReason = checkSensitiveFilename(url: url) {
            return ExclusionResult(url: url, exclusionType: .sensitiveFile(reason: sensitiveReason))
        }
        
        // Check file content for binary and sensitive patterns
        return checkFileContent(url: url)
    }
    
    // MARK: - Private Methods
    
    private func checkSensitiveFilename(url: URL) -> ExclusionType.SensitiveReason? {
        let filename = url.lastPathComponent.lowercased()
        
        // Check for dotenv files
        let dotenvPatterns = [
            ".env", ".env.local", ".env.development", ".env.production",
            ".env.staging", ".env.test", ".env.example"
        ]
        
        for pattern in dotenvPatterns {
            if filename == pattern || filename.hasPrefix(pattern + ".") {
                return .dotenvFile
            }
        }
        
        return nil
    }
    
    private func checkFileContent(url: URL) -> ExclusionResult? {
        guard let data = readFileSample(url: url) else {
            return nil
        }
        
        // Check if file is binary (not valid UTF-8)
        if String(data: data, encoding: .utf8) == nil {
            return ExclusionResult(url: url, exclusionType: .binary)
        }
        
        // Convert to string for pattern matching
        guard let content = String(data: data, encoding: .utf8) else {
            return ExclusionResult(url: url, exclusionType: .binary)
        }
        
        // Check for sensitive patterns in content
        if let sensitiveReason = detectSensitivePatterns(content: content) {
            return ExclusionResult(url: url, exclusionType: .sensitiveFile(reason: sensitiveReason))
        }
        
        return nil
    }
    
    private func readFileSample(url: URL) -> Data? {
        do {
            let data = try Data(contentsOf: url)
            // Only read first part of file for efficiency
            let sampleSize = min(data.count, Self.MAX_SAMPLE_SIZE)
            return data.prefix(sampleSize)
        } catch {
            return nil
        }
    }
    
    private func detectSensitivePatterns(content: String) -> ExclusionType.SensitiveReason? {
        // Check for private keys first (highest priority)
        if containsPrivateKey(content: content) {
            return .privateKey
        }
        
        // Check for API key patterns
        if containsAPIKeys(content: content) {
            return .apiKeyPattern
        }
        
        // Check for generic secret patterns
        if containsSecrets(content: content) {
            return .secretPattern
        }
        
        return nil
    }
    
    private func containsPrivateKey(content: String) -> Bool {
        let privateKeyPatterns = [
            "-----BEGIN RSA PRIVATE KEY-----",
            "-----BEGIN DSA PRIVATE KEY-----",
            "-----BEGIN EC PRIVATE KEY-----",
            "-----BEGIN OPENSSH PRIVATE KEY-----",
            "-----BEGIN PGP PRIVATE KEY BLOCK-----",
            "-----BEGIN PRIVATE KEY-----"
        ]
        
        return privateKeyPatterns.contains { content.contains($0) }
    }
    
    private func containsAPIKeys(content: String) -> Bool {
        let apiKeyPatterns = [
            // AWS patterns
            #"AKIA[0-9A-Z]{16}"#,
            #"(?i)aws(.{0,20})?(?-i)['"][0-9a-zA-Z\/+]{40}['"]"#,
            
            // GitHub patterns
            #"ghp_[0-9a-zA-Z]{36}"#,
            #"gho_[0-9a-zA-Z]{36}"#,
            #"ghu_[0-9a-zA-Z]{36}"#,
            #"ghs_[0-9a-zA-Z]{36}"#,
            #"ghr_[0-9a-zA-Z]{36}"#,
            
            // Google API Key
            #"AIza[0-9A-Za-z\-_]{35}"#,
            
            // Slack Token
            #"xox[baprs]-[0-9]{10,12}-[0-9]{10,12}-[0-9A-Za-z]{24,32}"#,
            
            // Generic API key patterns
            #"[aA][pP][iI][_]?[kK][eE][yY].*['"][0-9a-zA-Z]{20,}['"]"#,
            #"[aA][pP][iI][_]?[tT][oO][kK][eE][nN].*['"][0-9a-zA-Z]{20,}['"]"#
        ]
        
        return apiKeyPatterns.contains { pattern in
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
                let range = NSRange(content.startIndex..<content.endIndex, in: content)
                return regex.firstMatch(in: content, options: [], range: range) != nil
            } catch {
                return false
            }
        }
    }
    
    private func containsSecrets(content: String) -> Bool {
        let secretPatterns = [
            // Generic secret patterns
            #"[sS][eE][cC][rR][eE][tT].*['"][0-9a-zA-Z]{20,}['"]"#,
            #"[pP][aA][sS][sS][wW][oO][rR][dD].*['"][0-9a-zA-Z]{8,}['"]"#,
            #"[tT][oO][kK][eE][nN].*['"][0-9a-zA-Z]{20,}['"]"#,
            
            // JWT tokens
            #"eyJ[a-zA-Z0-9\-_]+\.[a-zA-Z0-9\-_]+\.[a-zA-Z0-9\-_]+"#,
            
            // Bearer tokens
            #"Bearer\s+[a-zA-Z0-9\-._~+/]+=*"#
        ]
        
        return secretPatterns.contains { pattern in
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
                let range = NSRange(content.startIndex..<content.endIndex, in: content)
                return regex.firstMatch(in: content, options: [], range: range) != nil
            } catch {
                return false
            }
        }
    }
}