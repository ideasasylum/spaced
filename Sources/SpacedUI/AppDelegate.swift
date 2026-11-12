import AppKit
import SpacedCore
import UniformTypeIdentifiers

public enum SpacedApplication {
    @MainActor private static var delegate: AppDelegate?

    @MainActor
    public static func run() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        self.delegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let paths = SpacedPaths.standard
    var store: SessionStore { SessionStore(directory: paths.sessions) }

    private var controllers: [DocumentWindowController] = []
    private var isTerminating = false
    private var requestWatcher: DispatchSourceFileSystemObject?
    private var keyMonitor: Any?
    /// Files handed over by Finder before launch has finished restoring tabs.
    private var filesToOpen: [URL] = []
    private var hasLaunched = false

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? paths.createDirectories()
        NSWindow.allowsAutomaticWindowTabbing = true
        NSApp.mainMenu = MainMenu.build()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let consumed = MainActor.assumeIsolated {
                (event.window?.windowController as? DocumentWindowController)?.handleKeyDown(event) ?? false
            }
            return consumed ? nil : event
        }

        for session in store.loadAll() where !session.markdown.isEmpty {
            show(DocumentWindowController(session: session, app: self), asTab: true)
        }
        hasLaunched = true
        filesToOpen.forEach { open(.file($0)) }
        filesToOpen = []
        openPendingRequests()
        watchRequests()
        if controllers.isEmpty {
            show(DocumentWindowController(session: Session(), app: self), asTab: false)
        }
        NSApp.activate()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        isTerminating = true
        controllers.forEach { $0.model.saveNow() }
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            newDocument(nil)
        }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        openPendingRequests()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard hasLaunched else {
            filesToOpen += urls
            return
        }
        urls.forEach { open(.file($0)) }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: Opening

    func open(_ source: OpenSource) {
        switch source {
        case .file(let url):
            guard let data = try? Data(contentsOf: url) else {
                NSSound.beep()
                return
            }
            open(markdown: String(decoding: data, as: UTF8.self), sourcePath: url.path, title: nil, asks: [],
                 awaitedRequestID: nil)
        case .text(let text):
            open(markdown: text, sourcePath: nil, title: nil, asks: [], awaitedRequestID: nil)
        }
    }

    private func open(markdown: String, sourcePath: String?, title: String?, asks: [String], awaitedRequestID: UUID?) {
        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let controller: DocumentWindowController
        if let current = currentController, current.model.isEmpty {
            controller = current
        } else {
            controller = DocumentWindowController(session: Session(), app: self)
            show(controller, asTab: true)
        }
        controller.model.load(markdown: markdown, sourcePath: sourcePath, title: title, asks: asks,
                              awaitedRequestID: awaitedRequestID, promptForAsk: true)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private var currentController: DocumentWindowController? {
        let window = NSApp.keyWindow ?? NSApp.mainWindow
        return (window?.windowController as? DocumentWindowController) ?? controllers.last
    }

    private func show(_ controller: DocumentWindowController, asTab: Bool) {
        guard let window = controller.window else { return }
        let host = asTab ? currentController?.window : nil
        controllers.append(controller)
        if let host {
            host.addTabbedWindow(window, ordered: .above)
        } else {
            window.tabbingMode = .disallowed
        }
        window.makeKeyAndOrderFront(nil)
        window.tabbingMode = .preferred
    }

    func documentClosed(_ controller: DocumentWindowController) {
        controllers.removeAll { $0 === controller }
        guard !isTerminating else { return }
        controller.model.discard(paths: paths)
    }

    // MARK: CLI requests

    private func openPendingRequests() {
        let requests = ReviewRequest.takePending(from: paths)
        for request in requests {
            open(markdown: request.markdown, sourcePath: request.sourcePath, title: request.title,
                 asks: request.asks, awaitedRequestID: request.wait ? request.id : nil)
        }
        if !requests.isEmpty {
            NSApp.activate()
        }
    }

    private func watchRequests() {
        let descriptor = Darwin.open(paths.requests.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.openPendingRequests() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        requestWatcher = source
    }

    // MARK: Menu actions

    @objc func newDocument(_ sender: Any?) {
        show(DocumentWindowController(session: Session(), app: self), asTab: false)
    }

    @objc func newWindowForTab(_ sender: Any?) {
        show(DocumentWindowController(session: Session(), app: self), asTab: true)
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [UTType(filenameExtension: "md"), .plainText, .text].compactMap { $0 }
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach { open(.file($0)) }
    }
}
