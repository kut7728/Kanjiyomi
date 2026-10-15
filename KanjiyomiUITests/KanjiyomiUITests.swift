//
//  KanjiyomiUITests.swift
//  KanjiyomiUITests
//
//  Created by kut7728 on 2026/08/09.
//

import XCTest

final class KanjiyomiUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testOnboardingCompletionPersists() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "NO"]
        app.launch()

        let next = app.buttons["onboarding.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        assertOnboardingFits(app, note: "onboarding.introductionNote", forward: "onboarding.next")
        XCTAssertFalse(app.buttons["onboarding.previous"].isEnabled)
        next.tap()
        XCTAssertEqual(app.staticTexts["onboarding.progress"].label, "사용 안내 · 2 / 3")
        assertOnboardingFits(app, note: "onboarding.modeNote", forward: "onboarding.next")
        app.buttons["onboarding.previous"].tap()
        XCTAssertEqual(app.staticTexts["onboarding.progress"].label, "사용 안내 · 1 / 3")
        next.tap()
        next.tap()
        assertOnboardingFits(app, note: "onboarding.apiNote", forward: "onboarding.finish")
        app.buttons["onboarding.finish"].tap()
        XCTAssertTrue(app.buttons["앨범에서 선택"].waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["앨범에서 선택"].waitForExistence(timeout: 5))
        XCTAssertFalse(next.exists)
    }

    @MainActor
    func testOnboardingSettingsRouteAndReplay() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "NO"]
        app.launch()

        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 10))
        app.buttons["onboarding.next"].tap()
        app.buttons["onboarding.next"].tap()
        app.buttons["onboarding.configure"].tap()
        XCTAssertTrue(app.navigationBars["설정"].waitForExistence(timeout: 5))

        let replay = app.buttons["settings.onboarding"]
        for _ in 0..<4 {
            if replay.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(replay.isHittable)
        replay.tap()
        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["onboarding.progress"].label, "사용 안내 · 1 / 3")
        app.buttons["onboarding.skip"].tap()
        XCTAssertTrue(app.navigationBars["설정"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func assertOnboardingFits(_ app: XCUIApplication, note: String, forward: String) {
        let previous = app.buttons["onboarding.previous"].frame
        let next = app.buttons[forward].frame
        let lastNote = app.staticTexts[note]
        XCTAssertTrue(lastNote.isHittable, "마지막 안내가 스크롤 없이 보여야 합니다.")
        XCTAssertLessThanOrEqual(lastNote.frame.maxY, next.minY)
        XCTAssertEqual(previous.midY, next.midY, accuracy: 2)
        XCTAssertLessThanOrEqual(previous.maxX, next.minX)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
