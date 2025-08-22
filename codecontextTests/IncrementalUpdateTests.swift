@testable import codecontext
import XCTest

@MainActor
final class IncrementalUpdateTests: XCTestCase {
    func testExtractSelectedPaths() async {
        let engine = await StreamingContextEngine()

        let sampleXML = """
        <codebase>
          <file=main.swift>
          Path: src/main.swift
          `````swift
          print("Hello World")
          `````
          </file=main.swift>

          <file=helper.swift>
          Path: src/helper.swift
          `````swift
          func helper() {}
          `````
          </file=helper.swift>
        </codebase>
        """

        let paths = await engine.extractSelectedPaths(from: sampleXML)
        XCTAssertEqual(paths.count, 2)
        XCTAssertTrue(paths.contains("src/main.swift"))
        XCTAssertTrue(paths.contains("src/helper.swift"))
    }

    func testRemoveFileFromXML() async {
        let engine = await StreamingContextEngine()

        let originalXML = """
        <codebase>
          <file=main.swift>
          Path: src/main.swift
          `````swift
          print("Hello World")
          `````
          </file=main.swift>

          <file=helper.swift>
          Path: src/helper.swift
          `````swift
          func helper() {}
          `````
          </file=helper.swift>
        </codebase>
        """

        let tempURL = URL(fileURLWithPath: "/tmp/test")
        let result = await engine.removeFileFromXML(originalXML, path: "src/helper.swift", rootURL: tempURL)

        // Should remove the helper.swift file but keep main.swift
        XCTAssertTrue(result.contains("main.swift"))
        XCTAssertFalse(result.contains("helper.swift"))
        XCTAssertTrue(result.contains("<codebase>"))
        XCTAssertTrue(result.contains("</codebase>"))
    }

    func testInsertFilesIntoXML() async {
        let engine = await StreamingContextEngine()

        let baseXML = """
        <codebase>
          <file=main.swift>
          Path: src/main.swift
          `````swift
          print("Hello World")
          `````
          </file=main.swift>
        </codebase>
        """

        let newFileXML = """
          <file=helper.swift>
          Path: src/helper.swift
          `````swift
          func helper() {}
          `````
          </file=helper.swift>

        """

        let result = await engine.insertFilesIntoXML(baseXML, newFilesXML: newFileXML)

        // Should contain both files
        XCTAssertTrue(result.contains("main.swift"))
        XCTAssertTrue(result.contains("helper.swift"))
        XCTAssertTrue(result.contains("print(\"Hello World\")"))
        XCTAssertTrue(result.contains("func helper()"))
    }

    func testIncrementalUpdateAddFile() async {
        let engine = await StreamingContextEngine()

        // Create test files
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

        let mainFile = testDir.appendingPathComponent("main.swift")
        let helperFile = testDir.appendingPathComponent("helper.swift")

        try! "print(\"Hello World\")".write(to: mainFile, atomically: true, encoding: .utf8)
        try! "func helper() {}".write(to: helperFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testDir)
        }

        let allFiles = [
            FileInfo(url: mainFile, isDirectory: false, size: 100),
            FileInfo(url: helperFile, isDirectory: false, size: 50),
        ]

        // Start with just main.swift
        let initialXML = "<codebase>\n</codebase>\n"

        do {
            let result = try await engine.updateContext(
                currentXML: initialXML,
                addedPaths: [mainFile.path],
                removedPaths: [],
                allFiles: allFiles,
                includeTree: false,
                rootURL: testDir
            )

            XCTAssertTrue(result.xml.contains("main.swift"))
            XCTAssertTrue(result.xml.contains("Hello World"))
            XCTAssertFalse(result.xml.contains("helper.swift"))
            XCTAssertGreaterThan(result.tokenCount, 0)
            XCTAssertEqual(result.filesProcessed, 1)
        } catch {
            XCTFail("Incremental update failed: \(error)")
        }
    }

    func testBasicFileTreeGeneration() async {
        let engine = await StreamingContextEngine()

        // Create test files
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

        let mainFile = testDir.appendingPathComponent("main.swift")
        try! "print(\"Hello World\")".write(to: mainFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testDir)
        }

        let allFiles = [
            FileInfo(url: mainFile, isDirectory: false, size: 100),
        ]

        // Select the file
        let selectedPaths: Set<String> = [mainFile.path]

        do {
            let result = try await engine.updateContext(
                currentXML: "<codebase>\n</codebase>\n",
                addedPaths: selectedPaths,
                removedPaths: [],
                allFiles: allFiles,
                includeTree: true, // Include file tree
                rootURL: testDir
            )

            // Just verify file tree is generated with the one file
            XCTAssertTrue(result.xml.contains("<fileTree>"), "Should contain fileTree opening tag")
            XCTAssertTrue(result.xml.contains("</fileTree>"), "Should contain fileTree closing tag")
            XCTAssertTrue(result.xml.contains("main.swift"), "Should contain main.swift in tree")
        } catch {
            XCTFail("Basic file tree test failed: \(error)")
        }
    }

    func testFileTreeIncludesAllFiles() async {
        let engine = await StreamingContextEngine()

        // Create test files
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

        let mainFile = testDir.appendingPathComponent("main.swift")
        let helperFile = testDir.appendingPathComponent("helper.swift")
        let configFile = testDir.appendingPathComponent("config.json")

        try! "print(\"Hello World\")".write(to: mainFile, atomically: true, encoding: .utf8)
        try! "func helper() {}".write(to: helperFile, atomically: true, encoding: .utf8)
        try! "{\"setting\": \"value\"}".write(to: configFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testDir)
        }

        let allFiles = [
            FileInfo(url: mainFile, isDirectory: false, size: 100),
            FileInfo(url: helperFile, isDirectory: false, size: 50),
            FileInfo(url: configFile, isDirectory: false, size: 30),
        ]

        // Only select main.swift for content generation
        let selectedPaths: Set<String> = [mainFile.path]

        do {
            let result = try await engine.updateContext(
                currentXML: "<codebase>\n</codebase>\n",
                addedPaths: selectedPaths,
                removedPaths: [],
                allFiles: allFiles,
                includeTree: true, // Include file tree
                rootURL: testDir
            )

            // Content should only include selected file
            XCTAssertTrue(result.xml.contains("<file=main.swift>"), "Should contain main.swift file block")
            XCTAssertTrue(result.xml.contains("Hello World"), "Should contain main.swift content")
            XCTAssertFalse(result.xml.contains("func helper()"), "Should NOT contain helper.swift content")
            XCTAssertFalse(result.xml.contains("\"setting\": \"value\""), "Should NOT contain config.json content")

            // But file tree should show ALL files
            XCTAssertTrue(result.xml.contains("<fileTree>"), "Should contain fileTree opening tag")
            XCTAssertTrue(result.xml.contains("</fileTree>"), "Should contain fileTree closing tag")

            // Check that all files appear in the tree section
            // Use simpler check without regex
            if let treeStart = result.xml.range(of: "<fileTree>"),
               let treeEnd = result.xml.range(of: "</fileTree>")
            {
                let startIndex = treeStart.upperBound
                let endIndex = treeEnd.lowerBound
                let fileTreeContent = String(result.xml[startIndex ..< endIndex])

                XCTAssertTrue(fileTreeContent.contains("main.swift"), "File tree should contain main.swift")
                XCTAssertTrue(fileTreeContent.contains("helper.swift"), "File tree should contain helper.swift")
                XCTAssertTrue(fileTreeContent.contains("config.json"), "File tree should contain config.json")
            } else {
                XCTFail("Could not find fileTree section in XML")
            }
        } catch {
            XCTFail("File tree test failed: \(error)")
        }
    }

    func testRemoveFileByRelativePath() async {
        let engine = await StreamingContextEngine()

        let originalXML = """
        <codebase>
          <file=main.swift>
          Path: src/main.swift
          `````swift
          print("Hello World")
          `````
          </file=main.swift>

          <file=helper.swift>
          Path: src/utils/helper.swift
          `````swift
          func helper() {}
          `````
          </file=helper.swift>

          <file=index.js>
          Path: src/index.js
          `````javascript
          console.log("hello");
          `````
          </file=index.js>

          <file=index.js>
          Path: dist/index.js
          `````javascript
          console.log("built");
          `````
          </file=index.js>
        </codebase>
        """

        let tempURL = URL(fileURLWithPath: "/tmp/test")

        // Test removing file by relative path
        let result1 = await engine.removeFileFromXML(originalXML, path: "src/utils/helper.swift", rootURL: tempURL)
        XCTAssertTrue(result1.contains("src/main.swift"), "Should keep main.swift")
        XCTAssertFalse(result1.contains("src/utils/helper.swift"), "Should remove helper.swift")
        XCTAssertTrue(result1.contains("src/index.js"), "Should keep src/index.js")
        XCTAssertTrue(result1.contains("dist/index.js"), "Should keep dist/index.js")

        // Test removing one of two files with same name but different paths
        let result2 = await engine.removeFileFromXML(originalXML, path: "dist/index.js", rootURL: tempURL)
        XCTAssertTrue(result2.contains("src/index.js"), "Should keep src/index.js")
        XCTAssertFalse(result2.contains("dist/index.js"), "Should remove dist/index.js")
        XCTAssertTrue(result2.contains("src/main.swift"), "Should keep main.swift")
        XCTAssertTrue(result2.contains("src/utils/helper.swift"), "Should keep helper.swift")
    }

    func testIncrementalSelectDeselectCycle() async {
        let engine = await StreamingContextEngine()

        // Create test files in subdirectories
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent(UUID().uuidString)
        let srcDir = testDir.appendingPathComponent("src")
        let distDir = testDir.appendingPathComponent("dist")

        try! FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: distDir, withIntermediateDirectories: true)

        let mainFile = srcDir.appendingPathComponent("main.swift")
        let helperFile = srcDir.appendingPathComponent("helper.swift")
        let distFile = distDir.appendingPathComponent("main.js")

        try! "print(\"Hello World\")".write(to: mainFile, atomically: true, encoding: .utf8)
        try! "func helper() {}".write(to: helperFile, atomically: true, encoding: .utf8)
        try! "console.log('built');".write(to: distFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testDir)
        }

        let allFiles = [
            FileInfo(url: mainFile, isDirectory: false, size: 100),
            FileInfo(url: helperFile, isDirectory: false, size: 50),
            FileInfo(url: distFile, isDirectory: false, size: 40),
        ]

        do {
            // Step 1: Select main.swift
            let result1 = try await engine.updateContext(
                currentXML: "<codebase>\n</codebase>\n",
                addedPaths: [mainFile.path],
                removedPaths: [],
                allFiles: allFiles,
                includeTree: false,
                rootURL: testDir
            )

            XCTAssertTrue(result1.xml.contains("src/main.swift"), "Step 1: Should contain main.swift")
            XCTAssertFalse(result1.xml.contains("src/helper.swift"), "Step 1: Should not contain helper.swift")
            let step1TokenCount = result1.tokenCount

            // Step 2: Add helper.swift
            let result2 = try await engine.updateContext(
                currentXML: result1.xml,
                addedPaths: [helperFile.path],
                removedPaths: [],
                allFiles: allFiles,
                includeTree: false,
                rootURL: testDir
            )

            XCTAssertTrue(result2.xml.contains("src/main.swift"), "Step 2: Should contain main.swift")
            XCTAssertTrue(result2.xml.contains("src/helper.swift"), "Step 2: Should contain helper.swift")
            let step2TokenCount = result2.tokenCount
            XCTAssertGreaterThan(step2TokenCount, step1TokenCount, "Step 2: Token count should increase")

            // Step 3: Remove helper.swift (this is where the bug was)
            let result3 = try await engine.updateContext(
                currentXML: result2.xml,
                addedPaths: [],
                removedPaths: [helperFile.path],
                allFiles: allFiles,
                includeTree: false,
                rootURL: testDir
            )

            XCTAssertTrue(result3.xml.contains("src/main.swift"), "Step 3: Should still contain main.swift")
            XCTAssertFalse(result3.xml.contains("src/helper.swift"), "Step 3: Should no longer contain helper.swift")
            XCTAssertFalse(result3.xml.contains("func helper()"), "Step 3: Should not contain helper content")

            // This is the critical test - token count should return to step 1 level
            let step3TokenCount = result3.tokenCount
            XCTAssertEqual(step3TokenCount, step1TokenCount, "Step 3: Token count should return to original after removing helper.swift")

            // Step 4: Add helper.swift back - should match step 2
            let result4 = try await engine.updateContext(
                currentXML: result3.xml,
                addedPaths: [helperFile.path],
                removedPaths: [],
                allFiles: allFiles,
                includeTree: false,
                rootURL: testDir
            )

            XCTAssertTrue(result4.xml.contains("src/main.swift"), "Step 4: Should contain main.swift")
            XCTAssertTrue(result4.xml.contains("src/helper.swift"), "Step 4: Should contain helper.swift")
            let step4TokenCount = result4.tokenCount
            XCTAssertEqual(step4TokenCount, step2TokenCount, "Step 4: Token count should match step 2")

        } catch {
            XCTFail("Incremental select/deselect cycle failed: \(error)")
        }
    }

    func testRemoveFileWithSpecialCharacters() async {
        let engine = await StreamingContextEngine()

        let originalXML = """
        <codebase>
          <file=test.file>
          Path: src/components/Button (1).tsx
          `````typescript
          const Button = () => {};
          `````
          </file=test.file>

          <file=config.json>
          Path: config/app.config.json
          `````json
          {"key": "value"}
          `````
          </file=config.json>
        </codebase>
        """

        let tempURL = URL(fileURLWithPath: "/tmp/test")

        // Test removing file with parentheses and dots in path
        let result1 = await engine.removeFileFromXML(originalXML, path: "src/components/Button (1).tsx", rootURL: tempURL)
        XCTAssertFalse(result1.contains("Button (1).tsx"), "Should remove file with special characters")
        XCTAssertTrue(result1.contains("app.config.json"), "Should keep other file")

        // Test removing file with dots in path
        let result2 = await engine.removeFileFromXML(originalXML, path: "config/app.config.json", rootURL: tempURL)
        XCTAssertFalse(result2.contains("app.config.json"), "Should remove config file")
        XCTAssertTrue(result2.contains("Button (1).tsx"), "Should keep other file")
    }

    func testEndToEndFolderSelectDeselectScenario() async {
        let engine = await StreamingContextEngine()

        // Create test directory structure that mirrors the real-world scenario
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent(UUID().uuidString)
        let srcDir = testDir.appendingPathComponent("src")
        let componentsDir = srcDir.appendingPathComponent("components")
        let utilsDir = srcDir.appendingPathComponent("utils")

        try! FileManager.default.createDirectory(at: componentsDir, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: utilsDir, withIntermediateDirectories: true)

        // Create files in folder A (src/components)
        let buttonFile = componentsDir.appendingPathComponent("Button.tsx")
        let inputFile = componentsDir.appendingPathComponent("Input.tsx")
        try! "export const Button = () => {};".write(to: buttonFile, atomically: true, encoding: .utf8)
        try! "export const Input = () => {};".write(to: inputFile, atomically: true, encoding: .utf8)

        // Create files in folder B (src/utils)
        let helperFile = utilsDir.appendingPathComponent("helper.ts")
        let formatFile = utilsDir.appendingPathComponent("format.ts")
        try! "export function helper() {}".write(to: helperFile, atomically: true, encoding: .utf8)
        try! "export function format() {}".write(to: formatFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testDir)
        }

        let allFiles = [
            FileInfo(url: buttonFile, isDirectory: false, size: 100),
            FileInfo(url: inputFile, isDirectory: false, size: 100),
            FileInfo(url: helperFile, isDirectory: false, size: 100),
            FileInfo(url: formatFile, isDirectory: false, size: 100),
        ]

        do {
            // Step 1: Select folder A (components) - this is the initial selection
            let step1Paths: Set<String> = [buttonFile.path, inputFile.path]
            let result1 = try await engine.updateContext(
                currentXML: "<codebase>\n</codebase>\n",
                addedPaths: step1Paths,
                removedPaths: [],
                allFiles: allFiles,
                includeTree: false,
                rootURL: testDir
            )

            XCTAssertTrue(result1.xml.contains("src/components/Button.tsx"), "Step 1: Should contain Button")
            XCTAssertTrue(result1.xml.contains("src/components/Input.tsx"), "Step 1: Should contain Input")
            XCTAssertFalse(result1.xml.contains("src/utils/helper.ts"), "Step 1: Should not contain helper")
            XCTAssertFalse(result1.xml.contains("src/utils/format.ts"), "Step 1: Should not contain format")
            let step1TokenCount = result1.tokenCount

            // Step 2: Select folder B (utils) - adding more files
            let step2Paths: Set<String> = [helperFile.path, formatFile.path]
            let result2 = try await engine.updateContext(
                currentXML: result1.xml,
                addedPaths: step2Paths,
                removedPaths: [],
                allFiles: allFiles,
                includeTree: false,
                rootURL: testDir
            )

            XCTAssertTrue(result2.xml.contains("src/components/Button.tsx"), "Step 2: Should still contain Button")
            XCTAssertTrue(result2.xml.contains("src/components/Input.tsx"), "Step 2: Should still contain Input")
            XCTAssertTrue(result2.xml.contains("src/utils/helper.ts"), "Step 2: Should now contain helper")
            XCTAssertTrue(result2.xml.contains("src/utils/format.ts"), "Step 2: Should now contain format")
            let step2TokenCount = result2.tokenCount
            XCTAssertGreaterThan(step2TokenCount, step1TokenCount, "Step 2: Token count should increase")

            // Step 3: Deselect folder B (utils) - this is where the bug was happening
            let result3 = try await engine.updateContext(
                currentXML: result2.xml,
                addedPaths: [],
                removedPaths: step2Paths,
                allFiles: allFiles,
                includeTree: false,
                rootURL: testDir
            )

            XCTAssertTrue(result3.xml.contains("src/components/Button.tsx"), "Step 3: Should still contain Button")
            XCTAssertTrue(result3.xml.contains("src/components/Input.tsx"), "Step 3: Should still contain Input")
            XCTAssertFalse(result3.xml.contains("src/utils/helper.ts"), "Step 3: Should NO LONGER contain helper")
            XCTAssertFalse(result3.xml.contains("src/utils/format.ts"), "Step 3: Should NO LONGER contain format")

            // Critical test: token count should return to step 1 level
            let step3TokenCount = result3.tokenCount
            XCTAssertEqual(step3TokenCount, step1TokenCount, "Step 3: Token count should return to step 1 level")

            // Step 4: Re-select folder B - should return to step 2 state
            let result4 = try await engine.updateContext(
                currentXML: result3.xml,
                addedPaths: step2Paths,
                removedPaths: [],
                allFiles: allFiles,
                includeTree: false,
                rootURL: testDir
            )

            XCTAssertTrue(result4.xml.contains("src/components/Button.tsx"), "Step 4: Should contain Button")
            XCTAssertTrue(result4.xml.contains("src/components/Input.tsx"), "Step 4: Should contain Input")
            XCTAssertTrue(result4.xml.contains("src/utils/helper.ts"), "Step 4: Should contain helper again")
            XCTAssertTrue(result4.xml.contains("src/utils/format.ts"), "Step 4: Should contain format again")
            let step4TokenCount = result4.tokenCount
            XCTAssertEqual(step4TokenCount, step2TokenCount, "Step 4: Token count should match step 2")

        } catch {
            XCTFail("End-to-end test failed: \(error)")
        }
    }
}
