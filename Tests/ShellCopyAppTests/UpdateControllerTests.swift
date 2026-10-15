import AppKit
import XCTest
@testable import ShellCopy

final class UpdateControllerTests: XCTestCase {
    func testShippingUpdatePolicyRequiresSignaturesAndExplicitInstallConsent() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Config/Release.plist"))
        let config = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(config["SUFeedURL"] as? String,
                       "https://github.com/doriansu/shell-copy/releases/latest/download/appcast.xml")
        let key = try XCTUnwrap(config["SUPublicEDKey"] as? String)
        XCTAssertEqual(Data(base64Encoded: key)?.count, 32)
        for name in ["SUVerifyUpdateBeforeExtraction", "SURequireSignedFeed", "SUEnableAutomaticChecks"] {
            XCTAssertEqual(config[name] as? Bool, true, name)
        }
        for name in ["SUAutomaticallyUpdate", "SUAllowsAutomaticUpdates", "SUEnableSystemProfiling"] {
            XCTAssertEqual(config[name] as? Bool, false, name)
        }
        XCTAssertEqual(config["SUScheduledCheckInterval"] as? Int, 86_400)
    }

    private final class Driver: UpdateChecking {
        var canCheckForUpdates = true
        var automaticallyChecksForUpdates = true
        var startCount = 0
        var checkCount = 0
        var error: Error?
        func start() throws {
            startCount += 1
            if let error { throw error }
        }
        func checkForUpdates() {
            checkCount += 1
            canCheckForUpdates = false
        }
    }

    func testStartKeepsSavedAutomaticPreferenceAndDoesNotManuallyPoll() {
        let driver = Driver()
        driver.automaticallyChecksForUpdates = false
        let controller = UpdateController(driver: driver) { _ in XCTFail("Unexpected error") }
        XCTAssertFalse(controller.checkItem.isEnabled)
        controller.start()
        controller.start()
        XCTAssertEqual(driver.startCount, 1)
        XCTAssertEqual(driver.checkCount, 0)
        XCTAssertEqual(controller.automaticItem.state, .off)
        XCTAssertTrue(controller.checkItem.isEnabled)
    }

    func testManualCheckWorksWithAutomaticChecksDisabledAndPreventsDuplicateCheck() {
        let driver = Driver()
        driver.automaticallyChecksForUpdates = false
        let controller = UpdateController(driver: driver) { _ in XCTFail("Unexpected error") }
        controller.start()
        controller.checkForUpdates()
        controller.checkForUpdates()
        XCTAssertEqual(driver.checkCount, 1)
        XCTAssertFalse(controller.checkItem.isEnabled)
        driver.canCheckForUpdates = true
        controller.refreshMenu()
        XCTAssertTrue(controller.checkItem.isEnabled)
        controller.checkForUpdates()
        XCTAssertEqual(driver.checkCount, 2)
    }

    func testToggleUpdatesPreferenceAndMenuWithoutStartingExtraCheck() {
        let driver = Driver()
        let controller = UpdateController(driver: driver) { _ in XCTFail("Unexpected error") }
        controller.start()
        XCTAssertEqual(controller.automaticItem.state, .on)
        controller.toggleAutomaticChecks()
        XCTAssertFalse(driver.automaticallyChecksForUpdates)
        XCTAssertEqual(controller.automaticItem.state, .off)
        controller.toggleAutomaticChecks()
        XCTAssertTrue(driver.automaticallyChecksForUpdates)
        XCTAssertEqual(controller.automaticItem.state, .on)
        XCTAssertEqual(driver.checkCount, 0)
    }

    func testStartupFailureOnlyShowsErrorForManualCheckAndCanRetry() {
        let driver = Driver()
        driver.error = NSError(domain: "UpdateTest", code: 1)
        var errors: [String] = []
        let controller = UpdateController(driver: driver) { errors.append($0) }
        controller.start()
        XCTAssertTrue(errors.isEmpty)
        XCTAssertFalse(controller.automaticItem.isEnabled)
        XCTAssertTrue(controller.checkItem.isEnabled)
        controller.toggleAutomaticChecks()
        XCTAssertTrue(driver.automaticallyChecksForUpdates)
        controller.checkForUpdates()
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(driver.checkCount, 0)
        driver.error = nil
        controller.start()
        XCTAssertTrue(controller.automaticItem.isEnabled)
        controller.checkForUpdates()
        XCTAssertEqual(driver.checkCount, 1)
    }
}
