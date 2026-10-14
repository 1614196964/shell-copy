import AppKit

enum ApplicationMenu {
    static func make() -> NSMenu {
        let menu = NSMenu()
        let application = NSMenu(title: "Shell Copy")
        application.addItem(withTitle: "Quit Shell Copy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let applicationItem = NSMenuItem()
        applicationItem.submenu = application
        menu.addItem(applicationItem)

        // A status-item menu does not supply AppKit's standard editing shortcuts.
        // Nil targets let the active field editor handle each action, including
        // the secure field in the modal API-key dialog.
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        menu.addItem(editItem)
        return menu
    }
}
