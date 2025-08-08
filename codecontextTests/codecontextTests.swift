//
//  codecontextTests.swift
//  codecontextTests
//
//  Created by Tarek Alexander on 08-08-2025.
//

import Testing
import Foundation
@testable import codecontext

struct codecontextTests {

    @Test func fallbackTokenizerCounts() async throws {
        let t = FallbackTokenizer()
        let emptyCount = await t.countTokens("")
        #expect(emptyCount == 0)
        
        let shortCount = await t.countTokens("abcd")
        #expect(shortCount == 1)
        
        let longCount = await t.countTokens(String(repeating: "a", count: 100))
        #expect(longCount >= 20)
    }

    @Test @MainActor func xmlFormatterRendersFile() async throws {
        let svc = XMLFormatterService()
        let tmp = URL(fileURLWithPath: "/tmp")
        let xml = svc.render(codebaseRoot: tmp, files: [
            .init(displayName: "Test.swift", absolutePath: "/tmp/Test.swift", languageHint: "swift", contents: "print(\"Hello\")")
        ], includeTree: true)
        #expect(xml.contains("<codebase>"))
        #expect(xml.contains("<file=Test.swift>"))
        #expect(xml.contains("`````swift"))
        #expect(xml.contains("</codebase>\n"))
    }

    @Test @MainActor func ignoreRulesExcludeDefaults() async throws {
        let rules = IgnoreRules()
        #expect(rules.isIgnored(path: "/a/b/.git", isDirectory: true))
        #expect(rules.isIgnored(path: "/a/b/node_modules", isDirectory: true))
        #expect(rules.isIgnored(path: "/a/.DS_Store", isDirectory: false))
    }
    
    @Test func languageMapIdentifiesLanguages() async throws {
        #expect(LanguageMap.languageHint(for: URL(fileURLWithPath: "test.swift")) == "swift")
        #expect(LanguageMap.languageHint(for: URL(fileURLWithPath: "test.js")) == "javascript")
        #expect(LanguageMap.languageHint(for: URL(fileURLWithPath: "test.py")) == "python")
        #expect(LanguageMap.languageHint(for: URL(fileURLWithPath: "test.rs")) == "rust")
        #expect(LanguageMap.languageHint(for: URL(fileURLWithPath: "test.unknown")) == "")
    }

}
