//
//  HybridCoderUITests.swift
//  HybridCoderUITests
//
//  Created by Rork on April 3, 2026.
//

import XCTest

final class HybridCoderUITests: XCTestCase {
    private var app: XCUIApplication?

    private func makeLaunchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["HYBRIDCODER_UI_TEST"] = "1"
        app.launchEnvironment["HYBRIDCODER_DISABLE_WARMUP"] = "1"
        app.launchEnvironment["HYBRIDCODER_SKIP_LAST_REPOSITORY"] = "1"
        return app
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = makeLaunchApp()
    }

    override func tearDownWithError() throws {
        if let app, app.state != .notRunning {
            app.terminate()
        }
        app = nil
    }

    @MainActor
    func testExample() throws {
        guard let app else {
            XCTFail("Failed to initialize XCUIApplication for UI test")
            return
        }

        app.launch()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 30),
            "HybridCoder failed to reach foreground state after launch."
        )
    }

    @MainActor
    func testLaunchPerformance() throws {
        guard ProcessInfo.processInfo.environment["HYBRIDCODER_ENABLE_UI_PERF_TESTS"] == "1" else {
            throw XCTSkip("Launch performance UI test is opt-in via HYBRIDCODER_ENABLE_UI_PERF_TESTS=1.")
        }

        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = makeLaunchApp()
            app.launch()
            XCTAssertTrue(
                app.wait(for: .runningForeground, timeout: 30),
                "HybridCoder failed to reach foreground state during launch metric run."
            )
            app.terminate()
        }
    }
}
