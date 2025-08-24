//
//  codecontextTests.swift
//  codecontextTests
//
//  Created by Tarek Alexander on 08-08-2025.
//

@testable import codecontext
import Foundation
import Testing

struct codecontextTests {
    @Test func tokenizerServiceWorks() async throws {
        // Test that the TokenizerService can count tokens accurately
        let emptyCount = await TokenizerService.shared.countTokens("")
        #expect(emptyCount == 0)

        let simpleCount = await TokenizerService.shared.countTokens("Hello world")
        #expect(simpleCount > 0)

        let longTextCount = await TokenizerService.shared.countTokens("The quick brown fox jumps over the lazy dog.")
        #expect(longTextCount > 5) // Should be multiple tokens for this sentence
    }

    @Test @MainActor func xmlFormatterRendersFile() async throws {
        let svc = XMLFormatterService()
        let tmp = URL(fileURLWithPath: "/tmp")
        let xml = svc.render(codebaseRoot: tmp, files: [
            .init(displayName: "Test.swift", absolutePath: "/tmp/Test.swift", languageHint: "swift", contents: "print(\"Hello\")"),
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
        #expect(LanguageMap.languageHint(for: URL(fileURLWithPath: "test.unknown")) == "unknown")
    }

    @Test func userInstructionsWrapsContextCorrectly() async throws {
        let engine = await StreamingContextEngine()
        let testXML = "<codebase>\n  <file=test.swift>\n  Path: test.swift\n  `````swift\n  print(\"Hello\")\n  `````\n  </file=test.swift>\n</codebase>\n"
        let instructions = "Please analyze this code for bugs and suggest improvements."
        let rootURL = URL(fileURLWithPath: "/tmp")

        let result = try await engine.updateContext(
            currentXML: testXML,
            addedPaths: [],
            removedPaths: [],
            allFiles: [],
            includeTree: false,
            includeFiles: true,
            rootURL: rootURL,
            userInstructions: instructions
        )

        // Should contain instructions at both top and bottom
        #expect(result.xml.hasPrefix("<userInstructions>\n\(instructions)\n</userInstructions>\n\n"))
        #expect(result.xml.hasSuffix("\n<userInstructions>\n\(instructions)\n</userInstructions>\n"))

        // Should contain the original context in the middle
        #expect(result.xml.contains(testXML))

        // Token count should include instructions
        #expect(result.tokenCount > 0)
    }

    @Test func emptyUserInstructionsDoesNotWrapContext() async throws {
        let engine = await StreamingContextEngine()
        let testXML = "<codebase>\n  <file=test.swift>\n  Path: test.swift\n  `````swift\n  print(\"Hello\")\n  `````\n  </file=test.swift>\n</codebase>\n"
        let rootURL = URL(fileURLWithPath: "/tmp")

        let result = try await engine.updateContext(
            currentXML: testXML,
            addedPaths: [],
            removedPaths: [],
            allFiles: [],
            includeTree: false,
            includeFiles: true,
            rootURL: rootURL,
            userInstructions: ""
        )

        // Should not contain userInstructions tags when empty
        #expect(!result.xml.contains("<userInstructions>"))
        #expect(result.xml == testXML)
    }

    @Test func whitespaceOnlyInstructionsDoesNotWrapContext() async throws {
        let engine = await StreamingContextEngine()
        let testXML = "<codebase>\n</codebase>\n"
        let rootURL = URL(fileURLWithPath: "/tmp")

        let result = try await engine.updateContext(
            currentXML: testXML,
            addedPaths: [],
            removedPaths: [],
            allFiles: [],
            includeTree: false,
            includeFiles: true,
            rootURL: rootURL,
            userInstructions: "   \n\t  "
        )

        // Should not wrap context when instructions are only whitespace
        #expect(!result.xml.contains("<userInstructions>"))
        #expect(result.xml == testXML)
    }

    @Test func noContentWithInstructionsShowsInstructionsOnce() async throws {
        let engine = await StreamingContextEngine()
        let testXML = "<codebase>\n</codebase>\n"
        let instructions = "Please analyze this code."
        let rootURL = URL(fileURLWithPath: "/tmp")

        let result = try await engine.updateContext(
            currentXML: testXML,
            addedPaths: [],
            removedPaths: [],
            allFiles: [],
            includeTree: false,
            includeFiles: false,
            rootURL: rootURL,
            userInstructions: instructions
        )

        // Should not contain codebase tags when no content
        #expect(!result.xml.contains("<codebase>"))
        // Should contain instructions only once
        let expectedXML = "<userInstructions>\n\(instructions)\n</userInstructions>"
        #expect(result.xml == expectedXML)
    }

    @Test func noContentNoInstructionsReturnsEmpty() async throws {
        let engine = await StreamingContextEngine()
        let testXML = "<codebase>\n</codebase>\n"
        let rootURL = URL(fileURLWithPath: "/tmp")

        let result = try await engine.updateContext(
            currentXML: testXML,
            addedPaths: [],
            removedPaths: [],
            allFiles: [],
            includeTree: false,
            includeFiles: false,
            rootURL: rootURL,
            userInstructions: ""
        )

        // Should return empty string when nothing is enabled
        #expect(result.xml.isEmpty)
    }
}
