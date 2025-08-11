@testable import codecontext
import XCTest

@MainActor
final class IgnoreRulesTests: XCTestCase {
    func testProjectPbxprojShouldNotBeIgnored() {
        let rules = IgnoreRules(
            respectGitIgnore: false,
            respectDotIgnore: false,
            showHiddenFiles: true,
            excludeNodeModules: true,
            excludeGit: true,
            excludeBuild: true,
            excludeDist: true,
            excludeNext: true,
            excludeVenv: true,
            excludeDSStore: true,
            excludeDerivedData: true,
            customPatterns: [],
            rootPath: "/Users/test/project"
        )

        // Test that project.pbxproj inside .xcodeproj is NOT ignored
        let pbxprojPath = "/Users/test/project/MyApp.xcodeproj/project.pbxproj"
        let isIgnored = rules.isIgnored(path: pbxprojPath, isDirectory: false)

        XCTAssertFalse(isIgnored, "project.pbxproj files should not be ignored")
    }

    func testXcworkspaceFilesShouldBeIgnored() {
        let rules = IgnoreRules(
            respectGitIgnore: false,
            respectDotIgnore: false,
            showHiddenFiles: true,
            excludeNodeModules: true,
            excludeGit: true,
            excludeBuild: true,
            excludeDist: true,
            excludeNext: true,
            excludeVenv: true,
            excludeDSStore: true,
            excludeDerivedData: true,
            customPatterns: ["*.xcworkspace"],
            rootPath: "/Users/test/project"
        )

        // Test that .xcworkspace files ARE ignored when explicitly added to custom patterns
        let xcworkspacePath = "/Users/test/project/MyApp.xcworkspace"
        let isIgnored = rules.isIgnored(path: xcworkspacePath, isDirectory: true)

        XCTAssertTrue(isIgnored, ".xcworkspace files should be ignored when in custom patterns")
    }

    func testWildcardPatternMatching() {
        let rules = IgnoreRules(
            respectGitIgnore: false,
            respectDotIgnore: false,
            showHiddenFiles: true,
            customPatterns: ["*.log", "temp*", "*cache*"],
            rootPath: "/Users/test/project"
        )

        // Test extension patterns
        XCTAssertTrue(rules.isIgnored(path: "/Users/test/project/debug.log", isDirectory: false))
        XCTAssertFalse(rules.isIgnored(path: "/Users/test/project/debug.txt", isDirectory: false))

        // Test prefix patterns
        XCTAssertTrue(rules.isIgnored(path: "/Users/test/project/tempfile.txt", isDirectory: false))
        XCTAssertFalse(rules.isIgnored(path: "/Users/test/project/mytempfile.txt", isDirectory: false))

        // Test contains patterns
        XCTAssertTrue(rules.isIgnored(path: "/Users/test/project/mycache", isDirectory: true))
        XCTAssertTrue(rules.isIgnored(path: "/Users/test/project/cache.tmp", isDirectory: false))
    }

    func testBuildArtifactExclusions() {
        let rules = IgnoreRules(
            respectGitIgnore: false,
            respectDotIgnore: false,
            showHiddenFiles: true,
            excludeNodeModules: true,
            excludeGit: true,
            excludeBuild: true,
            excludeDist: true,
            excludeNext: true,
            excludeVenv: true,
            excludeDSStore: true,
            excludeDerivedData: true,
            customPatterns: [],
            rootPath: "/Users/test/project"
        )

        // Test that build artifacts are ignored
        XCTAssertTrue(rules.isIgnored(path: "/Users/test/project/node_modules", isDirectory: true))
        XCTAssertTrue(rules.isIgnored(path: "/Users/test/project/DerivedData", isDirectory: true))
        XCTAssertTrue(rules.isIgnored(path: "/Users/test/project/build", isDirectory: true))
        XCTAssertTrue(rules.isIgnored(path: "/Users/test/project/.DS_Store", isDirectory: false))

        // Test that legitimate files are NOT ignored
        XCTAssertFalse(rules.isIgnored(path: "/Users/test/project/src/main.swift", isDirectory: false))
        XCTAssertFalse(rules.isIgnored(path: "/Users/test/project/README.md", isDirectory: false))
        XCTAssertFalse(rules.isIgnored(path: "/Users/test/project/MyApp.xcodeproj/project.pbxproj", isDirectory: false))
    }

    func testXcodeProjectFilesAreNotExcluded() {
        let rules = IgnoreRules(
            respectGitIgnore: false,
            respectDotIgnore: false,
            showHiddenFiles: true,
            excludeNodeModules: true,
            excludeGit: true,
            excludeBuild: true,
            excludeDist: true,
            excludeNext: true,
            excludeVenv: true,
            excludeDSStore: true,
            excludeDerivedData: true,
            customPatterns: [],
            rootPath: "/Users/test/project"
        )

        // These should NOT be ignored - they're project configuration files
        let testCases = [
            "/Users/test/project/MyApp.xcodeproj/project.pbxproj",
            "/Users/test/project/MyApp.xcodeproj/project.xcworkspace/contents.xcworkspacedata",
            "/Users/test/project/Package.swift",
            "/Users/test/project/Podfile",
            "/Users/test/project/Cartfile",
        ]

        for testPath in testCases {
            let isIgnored = rules.isIgnored(path: testPath, isDirectory: false)
            XCTAssertFalse(isIgnored, "\(testPath) should not be ignored as it's a project configuration file")
        }
    }

    func testUserDataShouldBeIgnored() {
        let rules = IgnoreRules(
            respectGitIgnore: false,
            respectDotIgnore: false,
            showHiddenFiles: true,
            excludeNodeModules: true,
            excludeGit: true,
            excludeBuild: true,
            excludeDist: true,
            excludeNext: true,
            excludeVenv: true,
            excludeDSStore: true,
            excludeDerivedData: true,
            customPatterns: [],
            rootPath: "/Users/test/project"
        )

        // These SHOULD be ignored - they're user-specific data
        let testCases = [
            "/Users/test/project/MyApp.xcodeproj/xcuserdata",
            "/Users/test/project/MyApp.xcodeproj/project.xcworkspace/xcuserdata",
        ]

        for testPath in testCases {
            let isIgnored = rules.isIgnored(path: testPath, isDirectory: true)
            XCTAssertTrue(isIgnored, "\(testPath) should be ignored as it's user-specific data")
        }
    }
}
