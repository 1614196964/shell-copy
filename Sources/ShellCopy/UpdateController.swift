import AppKit
import Sparkle

protocol UpdateChecking: AnyObject {
    var canCheckForUpdates: Bool { get }
    var automaticallyChecksForUpdates: Bool { get set }
    func start() throws
    func checkForUpdates()
}

final class SparkleUpdateDriver: UpdateChecking {
    private let controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil
    )

    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func start() throws { try controller.updater.start() }
    func checkForUpdates() { controller.checkForUpdates(nil) }
}

final class UpdateController: NSObject {
    let checkItem = NSMenuItem(title: "Check for Updates…", action: nil, keyEquivalent: "")
    let automaticItem = NSMenuItem(title: "Automatically Check for Updates", action: nil, keyEquivalent: "")
    private let driver: UpdateChecking
    private let showError: (String) -> Void
    private var startupError: String?
    private var started = false

    init(driver: UpdateChecking = SparkleUpdateDriver(), showError: @escaping (String) -> Void) {
        self.driver = driver
        self.showError = showError
        super.init()
        checkItem.target = self
        checkItem.action = #selector(checkForUpdates)
        automaticItem.target = self
        automaticItem.action = #selector(toggleAutomaticChecks)
        refreshMenu()
    }

    func start() {
        guard !started else { return }
        do {
            try driver.start()
            started = true
            startupError = nil
        } catch {
            // Updating must never prevent local clipboard processing from starting.
            startupError = "Updates are unavailable in this build. \(error.localizedDescription)"
        }
        refreshMenu()
    }

    func refreshMenu() {
        checkItem.isEnabled = startupError != nil || (started && driver.canCheckForUpdates)
        automaticItem.isEnabled = started
        automaticItem.state = started && driver.automaticallyChecksForUpdates ? .on : .off
    }

    @objc func checkForUpdates() {
        if let startupError {
            showError(startupError)
            return
        }
        guard started, driver.canCheckForUpdates else { return }
        driver.checkForUpdates()
        refreshMenu()
    }

    @objc func toggleAutomaticChecks() {
        guard started else { return }
        driver.automaticallyChecksForUpdates.toggle()
        refreshMenu()
    }
}
