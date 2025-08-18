import Foundation

/// Manages XML boundary markers to prevent content collision issues
/// Provides a modular system for wrapping, extracting, and cleaning XML content
struct BoundaryManager {
    
    // MARK: - Configuration
    
    /// Single source of truth for app identifier - change here to rebrand
    nonisolated static let appIdentifier = "CODECONTEXT"
    
    // MARK: - Boundary Types
    
    /// Type-safe enum for different boundary categories
    /// Add new cases here for future context features
    enum BoundaryType: String, CaseIterable {
        case codebase = "CODEBASE"
        case userInstructions = "USERINSTR"
        case fileTree = "TREE"
        case file = "FILE"
        
        // Future examples:
        // case documentation = "DOCS"
        // case configuration = "CONFIG"
        // case metadata = "META"
    }
    
    // MARK: - Boundary Structure
    
    /// Represents a unique boundary marker pair
    struct Boundary {
        let type: String
        let uuid: String
        
        nonisolated init(type: String) {
            self.type = type
            self.uuid = String(UUID().uuidString.prefix(8))
        }
        
        nonisolated var startMarker: String {
            "<!--\(appIdentifier)-\(type)-START-\(uuid)-->"
        }
        
        nonisolated var endMarker: String {
            "<!--\(appIdentifier)-\(type)-END-\(uuid)-->"
        }
        
        /// Wraps content with this boundary's markers
        nonisolated func wrap(_ content: String) -> String {
            "\(startMarker)\n\(content)\n\(endMarker)"
        }
    }
    
    // MARK: - Public API
    
    /// Wraps content with boundary markers of the specified type
    nonisolated static func wrap(_ content: String, type: BoundaryType) -> String {
        let boundary = Boundary(type: type.rawValue)
        return boundary.wrap(content)
    }
    
    /// Extracts all content sections wrapped with the specified boundary type
    nonisolated static func extract(_ xml: String, type: BoundaryType) -> [String] {
        let pattern = "<!--\(appIdentifier)-\(type.rawValue)-START-([A-Z0-9]+)-->\n(.*?)\n<!--\(appIdentifier)-\(type.rawValue)-END-\\1-->"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            logDebug("Failed to create regex for boundary extraction", details: "Type: \(type.rawValue)")
            return []
        }
        
        let range = NSRange(location: 0, length: xml.utf16.count)
        let matches = regex.matches(in: xml, options: [], range: range)
        
        var extractedContent: [String] = []
        for match in matches {
            if match.numberOfRanges >= 3 {
                let contentRange = match.range(at: 2)
                if let swiftRange = Range(contentRange, in: xml) {
                    extractedContent.append(String(xml[swiftRange]))
                }
            }
        }
        
        return extractedContent
    }
    
    /// Removes all sections wrapped with the specified boundary type
    nonisolated static func remove(_ xml: String, type: BoundaryType) -> String {
        let pattern = "<!--\(appIdentifier)-\(type.rawValue)-START-[A-Z0-9]+-->\n.*?\n<!--\(appIdentifier)-\(type.rawValue)-END-[A-Z0-9]+-->\n?"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            logDebug("Failed to create regex for boundary removal", details: "Type: \(type.rawValue)")
            return xml
        }
        
        let range = NSRange(location: 0, length: xml.utf16.count)
        let result = regex.stringByReplacingMatches(in: xml, options: [], range: range, withTemplate: "")
        
        return result
    }
    
    /// Removes ALL boundary markers for clean user display/copy
    nonisolated static func cleanForDisplay(_ xml: String) -> String {
        let pattern = "<!--\(appIdentifier)-[A-Z]+-(?:START|END)-[A-Z0-9]+-->\n?"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            logDebug("Failed to create regex for boundary cleanup", details: "Pattern: \(pattern)")
            return xml
        }
        
        let range = NSRange(location: 0, length: xml.utf16.count)
        let result = regex.stringByReplacingMatches(in: xml, options: [], range: range, withTemplate: "")
        
        return result
    }
    
    /// Finds and updates content within a specific boundary type
    nonisolated static func updateContent(_ xml: String, type: BoundaryType, with newContent: String) -> String {
        let pattern = "(<!--\(appIdentifier)-\(type.rawValue)-START-[A-Z0-9]+-->)\n.*?\n(<!--\(appIdentifier)-\(type.rawValue)-END-[A-Z0-9]+-->)"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            logDebug("Failed to create regex for boundary update", details: "Type: \(type.rawValue)")
            return xml
        }
        
        let range = NSRange(location: 0, length: xml.utf16.count)
        let result = regex.stringByReplacingMatches(in: xml, options: [], range: range, withTemplate: "$1\n\(newContent)\n$2")
        
        return result
    }
    
    /// Checks if XML contains boundaries of the specified type
    nonisolated static func contains(_ xml: String, type: BoundaryType) -> Bool {
        return xml.contains("<!--\(appIdentifier)-\(type.rawValue)-START-")
    }
    
    // MARK: - Debug Helpers
    
    /// Debug logging helper
    private nonisolated static func logDebug(_ message: String, details: String = "") {
        print("[BoundaryManager] \(message): \(details)")
    }
    
    /// Validates boundary integrity in XML
    nonisolated static func validateBoundaries(_ xml: String) -> [String] {
        var issues: [String] = []
        
        for type in BoundaryType.allCases {
            let startPattern = "<!--\(appIdentifier)-\(type.rawValue)-START-([A-Z0-9]+)-->"
            let endPattern = "<!--\(appIdentifier)-\(type.rawValue)-END-([A-Z0-9]+)-->"
            
            guard let startRegex = try? NSRegularExpression(pattern: startPattern, options: []),
                  let endRegex = try? NSRegularExpression(pattern: endPattern, options: []) else {
                continue
            }
            
            let range = NSRange(location: 0, length: xml.utf16.count)
            let startMatches = startRegex.matches(in: xml, options: [], range: range)
            let endMatches = endRegex.matches(in: xml, options: [], range: range)
            
            if startMatches.count != endMatches.count {
                issues.append("Mismatched \(type.rawValue) boundaries: \(startMatches.count) start, \(endMatches.count) end")
            }
        }
        
        return issues
    }
}