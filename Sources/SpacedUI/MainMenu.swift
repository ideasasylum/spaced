import AppKit

@MainActor
enum MainMenu {
    private static let up = String(UnicodeScalar(NSUpArrowFunctionKey)!)
    private static let down = String(UnicodeScalar(NSDownArrowFunctionKey)!)
    private static let left = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
    private static let right = String(UnicodeScalar(NSRightArrowFunctionKey)!)

    static func build() -> NSMenu {
        let main = NSMenu()

        main.addItem(submenu("Spaced", [
            item("About Spaced", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Hide Spaced", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quit Spaced", #selector(NSApplication.terminate(_:)), "q"),
        ]))

        main.addItem(submenu("File", [
            item("New Window", #selector(AppDelegate.newDocument(_:)), "n"),
            item("New Tab", #selector(AppDelegate.newWindowForTab(_:)), "t"),
            item("Open…", #selector(AppDelegate.openDocument(_:)), "o"),
            .separator(),
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
        ]))

        main.addItem(submenu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
        ]))

        main.addItem(submenu("View", [
            item("Toggle Sidebar", #selector(DocumentWindowController.toggleSidebar(_:)), "s", [.command, .control]),
            item("Show Whole Document", #selector(DocumentWindowController.toggleWholeDocument(_:)), "\u{1b}", []),
            .separator(),
            item("More Dimming", #selector(DocumentWindowController.moreDimming(_:)), up, [.option]),
            item("Less Dimming", #selector(DocumentWindowController.lessDimming(_:)), down, [.option]),
            item("Blur Background", #selector(DocumentWindowController.toggleBlur(_:)), "b", [.command, .option]),
            .separator(),
            item("Emphasise Word Starts", #selector(DocumentWindowController.toggleWordStartEmphasis(_:)), "e",
                 [.command, .option]),
            .separator(),
            item("Bigger Text", #selector(DocumentWindowController.biggerText(_:)), "+"),
            item("Smaller Text", #selector(DocumentWindowController.smallerText(_:)), "-"),
            item("Actual Size", #selector(DocumentWindowController.actualSizeText(_:)), "0"),
            .separator(),
            item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
        ]))

        main.addItem(submenu("Read", [
            item("Next", #selector(DocumentWindowController.nextUnit(_:)), " ", []),
            item("Previous", #selector(DocumentWindowController.previousUnit(_:)), " ", [.shift]),
            item("Next", #selector(DocumentWindowController.nextUnit(_:)), right, [], alternate: true),
            item("Previous", #selector(DocumentWindowController.previousUnit(_:)), left, [], alternate: true),
            .separator(),
            item("Widen Focus", #selector(DocumentWindowController.widenFocus(_:)), up, []),
            item("Narrow Focus", #selector(DocumentWindowController.narrowFocus(_:)), down, []),
            .separator(),
            item("Previous Section", #selector(DocumentWindowController.previousSection(_:)), "["),
            item("Next Section", #selector(DocumentWindowController.nextSection(_:)), "]"),
            .separator(),
            item("Add Note", #selector(DocumentWindowController.addNote(_:)), "\r", []),
            item("Read Aloud", #selector(DocumentWindowController.readAloud(_:)), "s", []),
            item("Keep Reading Aloud to the End", #selector(DocumentWindowController.toggleSpeechAutoAdvance(_:))),
            .separator(),
            item("Park a Thought", #selector(DocumentWindowController.parkThought(_:)), "p", []),
            item("Review Notes", #selector(DocumentWindowController.reviewNotes(_:)), "r", [.command, .shift]),
            item("Copy Notes as Markdown", #selector(DocumentWindowController.copyNotes(_:)), "c", [.command, .shift]),
            .separator(),
            item("Edit Question…", #selector(DocumentWindowController.editQuestion(_:))),
        ]))

        let window = submenu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
            .separator(),
            item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))),
        ])
        main.addItem(window)
        NSApp.windowsMenu = window.submenu

        return main
    }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func item(_ title: String, _ action: Selector, _ key: String = "",
                             _ modifiers: NSEvent.ModifierFlags = .command, alternate: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        // Arrow keys do the same as Space; listing them twice would only add noise.
        item.isHidden = alternate
        item.allowsKeyEquivalentWhenHidden = alternate
        return item
    }
}
