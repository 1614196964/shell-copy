import AppKit
import XCTest
@testable import ShellCopy

final class ApplicationMenuTests: XCTestCase {
    @MainActor
    func testCommandVPastesIntoTextEditor() throws {
        _ = NSApplication.shared
        let menu = ApplicationMenu.make()
        let pasteboard = try XCTUnwrap(NSPasteboard.withUniqueName() as NSPasteboard?)
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("test-only-key", forType: .string)
        let responder = IsolatedPasteResponder(pasteboard: pasteboard)
        let editor = responder.editor
        editor.string = "replace this"
        editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
        XCTAssertEqual(editor.string, "replace this")
        bindMenu(menu, to: responder)

        // Exercise AppKit's real shortcut dispatch, without posting a system key event
        // or touching the user's clipboard, keychain, or running application.
        XCTAssertTrue(menu.performKeyEquivalent(with: try key("v", code: 9)))
        XCTAssertEqual(editor.string, "test-only-key")
    }

    @MainActor
    func testCommandVPastesIntoSecureFieldEditor() throws {
        _ = NSApplication.shared
        let menu = ApplicationMenu.make()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 80),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let field = NSSecureTextField(frame: NSRect(x: 20, y: 20, width: 360, height: 24))
        window.contentView?.addSubview(field)
        XCTAssertTrue(window.makeFirstResponder(field))
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        let pasteboard = try XCTUnwrap(NSPasteboard.withUniqueName() as NSPasteboard?)
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("test-only-secure-key", forType: .string)
        let responder = IsolatedPasteResponder(pasteboard: pasteboard, editor: editor)
        bindMenu(menu, to: responder)

        XCTAssertTrue(menu.performKeyEquivalent(with: try key("v", code: 9)))
        XCTAssertEqual(editor.string, "test-only-secure-key")
        XCTAssertTrue(window.makeFirstResponder(nil))
        XCTAssertEqual(field.stringValue, "test-only-secure-key")
    }

    @MainActor
    func testCommandASelectsTheEntireKeyForReplacement() throws {
        _ = NSApplication.shared
        let menu = ApplicationMenu.make()
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        editor.string = "test-only-old-key"
        editor.setSelectedRange(NSRange(location: 4, length: 0))
        bindMenu(menu, to: editor)

        XCTAssertTrue(menu.performKeyEquivalent(with: try key("a", code: 0)))
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: editor.string.utf16.count))
    }

    @MainActor
    private func bindMenu(_ menu: NSMenu, to responder: NSResponder) {
        for item in menu.items {
            if let submenu = item.submenu { bindMenu(submenu, to: responder) }
            else { item.target = responder }
        }
    }

    @MainActor
    private func key(_ character: String, code: UInt16) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                      timestamp: 0, windowNumber: 0, context: nil,
                                      characters: character, charactersIgnoringModifiers: character,
                                      isARepeat: false, keyCode: code))
    }
}

@MainActor
private final class IsolatedPasteResponder: NSResponder {
    let pasteboard: NSPasteboard
    let editor: NSTextView
    init(pasteboard: NSPasteboard, editor: NSTextView? = nil) {
        self.pasteboard = pasteboard
        self.editor = editor ?? NSTextView(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        super.init()
        self.editor.isRichText = false
    }
    required init?(coder: NSCoder) { fatalError("Not used by this test") }
    @objc func paste(_ sender: Any?) {
        _ = editor.readSelection(from: pasteboard)
    }
}
