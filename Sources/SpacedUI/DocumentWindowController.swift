import AppKit
import SpacedCore
import SwiftUI

@MainActor
final class DocumentWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    let model: SessionModel
    private unowned let app: AppDelegate

    init(session: Session, app: AppDelegate) {
        self.app = app
        model = SessionModel(session: session, store: app.store)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.tabbingIdentifier = "SpacedDocument"
        window.tabbingMode = .preferred
        window.minSize = NSSize(width: 520, height: 400)
        window.title = session.title
        let content = NSHostingView(rootView: RootView(model: model, preferences: .shared))
        content.sizingOptions = []
        window.contentView = content
        window.setContentSize(NSSize(width: 980, height: 720))
        window.center()

        let controls = NSHostingView(rootView: TitlebarControls(preferences: .shared))
        controls.frame.size = controls.fittingSize
        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = controls
        accessory.layoutAttribute = .trailing
        window.addTitlebarAccessoryViewController(accessory)

        super.init(window: window)
        window.delegate = self

        model.onTitleChange = { [weak window] in window?.title = $0 }
        model.onOpen = { [weak app] in app?.open($0) }
        model.onFinish = { [weak self] in self?.window?.close() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    /// Selectable (read-only) text can also be first responder; only an editable field counts as typing.
    private var isEditingText: Bool {
        (window?.firstResponder as? NSTextView)?.isEditable == true
    }

    // MARK: Keys

    /// Handles the unmodified reading keys. Returns true when the event was consumed.
    func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if isEditingText {
            if event.keyCode == 53 {
                model.cancelEditing()
                window?.makeFirstResponder(nil)
                return true
            }
            if event.keyCode == 36, flags == .command, model.noteDraft != nil {
                model.commitNote()
                window?.makeFirstResponder(nil)
                return true
            }
            return false
        }
        if flags == .command, event.keyCode == 8, !model.isEmpty {
            copyUnlessSelectionDoes()
            return false
        }
        guard !flags.contains(.command), !flags.contains(.control), !model.isEmpty else { return false }
        if model.mode == .review {
            // Leave Return and Space for the buttons on the review screen.
            guard event.keyCode == 53 || event.keyCode == 123 else { return false }
            model.mode = .reading
            return true
        }
        switch event.keyCode {
        case 49: flags.contains(.shift) ? model.previous() : model.next()
        case 124: model.next()
        case 123: model.previous()
        case 126: flags.contains(.option) ? Preferences.shared.adjustDim(by: 0.1) : model.widen()
        case 125: flags.contains(.option) ? Preferences.shared.adjustDim(by: -0.1) : model.narrow()
        case 53: model.toggleWhole()
        case 36, 76: model.startNote()
        case 1: model.toggleSpeech()
        case 35: model.startParking()
        default: return false
        }
        return true
    }

    // MARK: Menu actions

    @objc func nextUnit(_ sender: Any?) { model.next() }
    @objc func previousUnit(_ sender: Any?) { model.previous() }
    @objc func widenFocus(_ sender: Any?) { model.widen() }
    @objc func narrowFocus(_ sender: Any?) { model.narrow() }
    @objc func nextSection(_ sender: Any?) { model.nextSection() }
    @objc func previousSection(_ sender: Any?) { model.previousSection() }
    @objc func toggleWholeDocument(_ sender: Any?) { model.mode == .review ? (model.mode = .reading) : model.toggleWhole() }
    @objc func addNote(_ sender: Any?) { model.startNote() }
    @objc func reviewNotes(_ sender: Any?) { model.mode = model.mode == .review ? .reading : .review }
    @objc func editQuestion(_ sender: Any?) { model.editAsks() }
    @objc func copyNotes(_ sender: Any?) { model.copyNotes() }
    @objc func toggleSidebar(_ sender: Any?) { Preferences.shared.sidebarVisible.toggle() }
    @objc func parkThought(_ sender: Any?) { model.startParking() }
    @objc func readAloud(_ sender: Any?) { model.toggleSpeech() }
    @objc func toggleSpeechAutoAdvance(_ sender: Any?) { Preferences.shared.autoAdvancesSpeech.toggle() }
    @objc func toggleWordStartEmphasis(_ sender: Any?) { Preferences.shared.emphasisesWordStarts.toggle() }
    @objc func toggleBlur(_ sender: Any?) { Preferences.shared.blursBackground.toggle() }
    @objc func moreDimming(_ sender: Any?) { Preferences.shared.adjustDim(by: 0.1) }
    @objc func lessDimming(_ sender: Any?) { Preferences.shared.adjustDim(by: -0.1) }
    @objc func biggerText(_ sender: Any?) { Preferences.shared.adjustFontScale(by: 0.1) }
    @objc func smallerText(_ sender: Any?) { Preferences.shared.adjustFontScale(by: -0.1) }
    @objc func actualSizeText(_ sender: Any?) { Preferences.shared.fontScale = 1 }

    /// Reached when no selected text handles Copy: copies what's on screen instead.
    @objc func copy(_ sender: Any?) {
        if model.mode == .review {
            model.copyNotes()
        } else {
            model.copyCurrentUnit()
        }
    }

    @objc func copyWholeDocument(_ sender: Any?) { model.copyDocument() }

    /// A click on selectable text makes it first responder even with nothing selected, and it then
    /// swallows Copy without copying. If the pasteboard is untouched after the key press, copy ourselves.
    private func copyUnlessSelectionDoes() {
        let before = NSPasteboard.general.changeCount
        DispatchQueue.main.async { [weak self] in
            if NSPasteboard.general.changeCount == before {
                self?.copy(nil)
            }
        }
    }

    @objc func paste(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        app.open(.text(text))
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(paste(_:)):
            return NSPasteboard.general.string(forType: .string) != nil
        case #selector(toggleSpeechAutoAdvance(_:)):
            menuItem.state = Preferences.shared.autoAdvancesSpeech ? .on : .off
            return true
        case #selector(readAloud(_:)):
            menuItem.title = model.isSpeaking ? "Stop Reading Aloud" : "Read Aloud"
            return !model.isEmpty && !isEditingText && model.mode != .review
        case #selector(toggleWordStartEmphasis(_:)):
            menuItem.state = Preferences.shared.emphasisesWordStarts ? .on : .off
            return true
        case #selector(toggleBlur(_:)):
            menuItem.state = Preferences.shared.blursBackground ? .on : .off
            return true
        case #selector(toggleSidebar(_:)), #selector(moreDimming(_:)), #selector(lessDimming(_:)),
             #selector(biggerText(_:)), #selector(smallerText(_:)), #selector(actualSizeText(_:)):
            return true
        case #selector(copy(_:)), #selector(copyWholeDocument(_:)):
            return !model.isEmpty
        case #selector(copyNotes(_:)):
            return !model.session.notes.isEmpty
        case #selector(reviewNotes(_:)), #selector(toggleWholeDocument(_:)), #selector(previousUnit(_:)),
             #selector(editQuestion(_:)):
            return !model.isEmpty && !isEditingText
        default:
            // The reading keys have no modifiers, so they must stay out of the way while typing
            // and while the review screen's buttons want Return and Space.
            return !model.isEmpty && !isEditingText && model.mode != .review
        }
    }

    // MARK: Closing

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model.hasUncopiedNotes, !model.isAwaited else { return true }
        let count = model.session.notes.count
        let alert = NSAlert()
        alert.messageText = "Close this document and discard \(count) note\(count == 1 ? "" : "s")?"
        alert.informativeText = "The notes haven't been copied yet."
        alert.addButton(withTitle: "Copy Notes & Close")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            model.copyNotes()
            return true
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    func windowWillClose(_ notification: Notification) {
        app.documentClosed(self)
    }
}
