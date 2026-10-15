// Standalone Sparkle integration driver; never linked into the shipping app.
import AppKit
import CryptoKit
import Sparkle

final class TestDriver: NSObject, SPUUserDriver {
    let mode: String
    var found = false
    private var finished = false
    init(mode: String) { self.mode = mode }
    func finish(_ message: String, code: Int32 = 0) {
        guard !finished else { return }
        finished = true
        print(message)
        if CommandLine.arguments.count == 4 {
            try? "\(code)".write(toFile: CommandLine.arguments[3], atomically: true, encoding: .utf8)
        }
        fflush(stdout)
        // Let Sparkle finish asynchronous installer/session cleanup before the next scenario.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { exit(code) }
    }
    func show(_ request: SPUUpdatePermissionRequest,
                                     reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        found = true
        if mode == "error" || mode == "bad-feed" {
            reply(.dismiss)
            finish("Unexpected trusted update", code: 1)
            return
        }
        print("Found update \(appcastItem.versionString)")
        if mode == "auto-dismiss" && state.userInitiated {
            finish("Expected automatic check", code: 1)
            reply(.dismiss)
            return
        }
        reply(mode == "dismiss" || mode == "auto-dismiss" ? .dismiss : .install)
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        acknowledgement()
        finish("No update: \(error)", code: mode == "current" ? 0 : 1)
    }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        acknowledgement()
        func signatureRejected(_ error: NSError) -> Bool {
            if error.domain == "SUSparkleErrorDomain" && [3001, 3002].contains(error.code) { return true }
            return (error.userInfo[NSUnderlyingErrorKey] as? NSError).map(signatureRejected) ?? false
        }
        let expected = mode == "error" || (["bad-feed", "bad-archive"].contains(mode) && signatureRejected(error as NSError))
        finish("Updater error: \(error)", code: expected ? 0 : 1)
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        if mode == "cancel-download" { cancellation() }
    }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() { print("Extracting update"); fflush(stdout) }
    func showExtractionReceivedProgress(_ progress: Double) { print("Extraction progress \(progress)"); fflush(stdout) }
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        print("Ready to install"); fflush(stdout)
        reply(.install)
    }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                             retryTerminatingApplication: @escaping () -> Void) {
        print("Installing; applicationTerminated=\(applicationTerminated)"); fflush(stdout)
    }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
        finish("Installed; relaunched=\(relaunched)")
    }
    func dismissUpdateInstallation() {
        if found && ["dismiss", "auto-dismiss", "cancel-download"].contains(mode) { finish("Canceled without installation") }
    }
}

if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--generate-test-key" {
    let key = Curve25519.Signing.PrivateKey()
    let path = CommandLine.arguments[2]
    guard FileManager.default.createFile(atPath: path,
        contents: Data(key.rawRepresentation.base64EncodedString().utf8),
        attributes: [.posixPermissions: 0o600]) else { fatalError("Cannot write test key") }
    print(key.publicKey.rawRepresentation.base64EncodedString())
    exit(0)
}

guard CommandLine.arguments.count == 4,
      let host = Bundle(path: CommandLine.arguments[1]),
      host.bundleIdentifier?.hasPrefix("local.shell-copy.update-test.") == true else {
    fatalError("Usage: integration-driver isolated-test.app dismiss|cancel-download|install|current|error|bad-archive")
}
let app = NSApplication.shared
let driver = TestDriver(mode: CommandLine.arguments[2])
let updater = SPUUpdater(hostBundle: host, applicationBundle: host, userDriver: driver, delegate: nil)
do { try updater.start() } catch { driver.finish("Startup failed: \(error)", code: 1) }
if driver.mode != "auto-dismiss" {
    updater.automaticallyChecksForUpdates = false
    updater.checkForUpdates()
}
DispatchQueue.main.asyncAfter(deadline: .now() + 60) { driver.finish("Timed out", code: 1) }
app.run()
