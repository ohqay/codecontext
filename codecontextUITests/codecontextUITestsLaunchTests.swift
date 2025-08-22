//
//  codecontextUITestsLaunchTests.swift
//  codecontextUITests
//
//  Created by Tarek Alexander on 08-08-2025.
//

import XCTest

final class codecontextUITestsLaunchTests: XCTestCase {
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // Verify the app launches successfully and main interface is present
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "App should launch within 10 seconds")
        
        // Verify basic UI elements are present
        // Note: These would need to be updated based on actual UI accessibility identifiers
        XCTAssertTrue(app.windows.firstMatch.exists, "Main window should be visible")
        
        // Take screenshot for visual verification if needed
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
