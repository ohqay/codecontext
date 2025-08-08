import Foundation

enum LanguageMap {
    nonisolated static func languageHint(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "m", "mm": return "objectivec"
        case "h": return "c"
        case "c": return "c"
        case "cc", "cpp", "cxx", "hpp", "hh": return "cpp"
        case "js": return "javascript"
        case "ts": return "typescript"
        case "tsx": return "tsx"
        case "jsx": return "jsx"
        case "json": return "json"
        case "yml", "yaml": return "yaml"
        case "md": return "markdown"
        case "py": return "python"
        case "rb": return "ruby"
        case "go": return "go"
        case "rs": return "rust"
        case "java": return "java"
        case "kt", "kts": return "kotlin"
        case "php": return "php"
        case "sh", "bash", "zsh": return "bash"
        case "css": return "css"
        case "scss": return "scss"
        case "html", "htm": return "html"
        case "sql": return "sql"
        default: return ""
        }
    }
}

