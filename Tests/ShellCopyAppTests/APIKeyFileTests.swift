import Foundation
import XCTest
@testable import ShellCopy

final class APIKeyFileTests: XCTestCase {
    func testExistingJevKeychainIdentityIsPreservedAndBjevIsSeparate() {
        XCTAssertEqual(APIKeyStore.service(for: .jev), "local.shell-copy.app.typesafe")
        XCTAssertEqual(APIKeyStore.service(for: .bjev), "local.shell-copy.app.bjev")
    }

    func testPlainTextImportTrimsFinalNewlineAndRejectsOtherContent() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("synthetic-test-key\n".utf8).write(to: url)
        XCTAssertEqual(try APIKeyFile.read(url), "synthetic-test-key")
        for invalid in ["", "key\nsecond", "export BJEV_API_KEY=secret", "key\0", String(repeating: "x", count: 16_385)] {
            try Data(invalid.utf8).write(to: url)
            XCTAssertThrowsError(try APIKeyFile.read(url))
        }
        try Data([0xff]).write(to: url)
        XCTAssertThrowsError(try APIKeyFile.read(url))
    }
}
