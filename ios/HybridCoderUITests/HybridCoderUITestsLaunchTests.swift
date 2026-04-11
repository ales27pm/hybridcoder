//
//  HybridCoderUITestsLaunchTests.swift
//  HybridCoderUITests
//
//  Created by Rork on April 3, 2026.
//

import XCTest

final class HybridCoderUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    private func makeLaunchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["HYBRIDCODER_UI_TEST"] = "1"
        app.launchEnvironment["HYBRIDCODER_DISABLE_WARMUP"] = "1"
        app.launchEnvironment["HYBRIDCODER_SKIP_LAST_REPOSITORY"] = "1"
        return app
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = makeLaunchApp()
        app.launch()

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
