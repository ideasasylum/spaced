import AppKit
import Observation
import SpacedCore

@MainActor
@Observable
final class Preferences {
    static let shared = Preferences()

    var dim: Double { didSet { UserDefaults.standard.set(dim, forKey: "dim") } }
    var fontScale: Double { didSet { UserDefaults.standard.set(fontScale, forKey: "fontScale") } }
    var sidebarVisible: Bool { didSet { UserDefaults.standard.set(sidebarVisible, forKey: "sidebarVisible") } }
    var sidebarWidth: Double { didSet { UserDefaults.standard.set(sidebarWidth, forKey: "sidebarWidth") } }
    /// The sidebar's width when a drag on its divider began.
    @ObservationIgnored private var sidebarDragStart: Double?
    var blursBackground: Bool { didSet { UserDefaults.standard.set(blursBackground, forKey: "blursBackground") } }
    var autoAdvancesSpeech: Bool { didSet { UserDefaults.standard.set(autoAdvancesSpeech, forKey: "autoAdvancesSpeech") } }

    private init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: ["dim": 0.85, "fontScale": 1.0, "sidebarVisible": true, "blursBackground": true,
                                     "sidebarWidth": 220.0, "autoAdvancesSpeech": true])
        dim = defaults.double(forKey: "dim")
        fontScale = defaults.double(forKey: "fontScale")
        sidebarVisible = defaults.bool(forKey: "sidebarVisible")
        sidebarWidth = defaults.double(forKey: "sidebarWidth")
        blursBackground = defaults.bool(forKey: "blursBackground")
        autoAdvancesSpeech = defaults.bool(forKey: "autoAdvancesSpeech")
    }

    func dragSidebar(by translation: Double) {
        let start = sidebarDragStart ?? sidebarWidth
        sidebarDragStart = start
        sidebarWidth = min(480, max(140, start + translation))
    }

    func endSidebarDrag() {
        sidebarDragStart = nil
    }

    func adjustDim(by delta: Double) {
        dim = min(1, max(0, dim + delta))
    }

    func adjustFontScale(by delta: Double) {
        fontScale = min(2, max(0.7, fontScale + delta))
    }
}

enum OpenSource {
    case file(URL)
    case text(String)
}

/// The state of one tab: its session, the parsed document, and what the reader is doing right now.
@MainActor
@Observable
final class SessionModel {
    enum Mode {
        case reading, whole, review
    }

    private(set) var session: Session
    private(set) var document: Document
    var mode: Mode = .reading {
        didSet { if mode == .review { stopSpeaking() } }
    }
    private(set) var isSpeaking = false
    /// The block and character range being read aloud right now.
    private(set) var spokenBlock: Int?
    private(set) var spokenRange: Range<Int>?
    /// Non-nil while a note is being written.
    var noteDraft: String?
    /// Non-nil while a stray thought is being parked.
    var parkDraft: String?
    /// Non-nil while the questions are being edited.
    var askDraft: String?
    private(set) var notesCopied = false

    @ObservationIgnored var onTitleChange: ((String) -> Void)?
    @ObservationIgnored var onOpen: ((OpenSource) -> Void)?
    @ObservationIgnored var onFinish: (() -> Void)?

    @ObservationIgnored private let store: SessionStore
    @ObservationIgnored private var pendingSave: DispatchWorkItem?
    @ObservationIgnored private var editingNoteID: UUID?

    init(session: Session, store: SessionStore) {
        self.session = session
        self.store = store
        document = Document(markdown: session.markdown)
    }

    var isEmpty: Bool { document.isEmpty }
    var navigator: Navigator { Navigator(document: document, position: session.position, level: session.level) }
    var unit: ReadingUnit? { navigator.unit }
    var isAwaited: Bool { session.awaitedRequestID != nil }
    var hasUncopiedNotes: Bool { !session.notes.isEmpty && !notesCopied }

    var currentBlocks: Range<Int> {
        unit.map(document.blockRange(of:)) ?? 0..<0
    }

    var progress: ReadingProgress {
        document.progress(at: navigator.position)
    }

    var currentSection: Int? {
        isEmpty ? nil : document.blocks[navigator.position.block].section
    }

    func load(markdown: String, sourcePath: String?, title: String?, asks: [String], awaitedRequestID: UUID?, promptForAsk: Bool) {
        stopSpeaking()
        document = Document(markdown: markdown)
        session.markdown = markdown
        session.sourcePath = sourcePath
        session.title = title ?? Session.title(for: document, markdown: markdown, sourcePath: sourcePath)
        session.asks = asks
        session.notes = []
        session.parked = []
        session.position = Position()
        session.awaitedRequestID = awaitedRequestID
        mode = .reading
        noteDraft = nil
        askDraft = promptForAsk && asks.isEmpty && !document.isEmpty ? "" : nil
        onTitleChange?(session.title)
        changed()
    }

    // MARK: Moving

    func next() {
        guard mode != .review else { return }
        var navigator = navigator
        if navigator.next() {
            apply(navigator)
        } else {
            mode = .review
        }
    }

    func previous() {
        if mode == .review {
            mode = .reading
            return
        }
        move { $0.previous() }
    }

    func widen() { move { $0.widen() } }
    func narrow() { move { $0.narrow() } }
    func nextSection() { move { $0.nextSection() } }
    func previousSection() { move { $0.previousSection() } }

    func jump(toBlock block: Int) {
        move { $0.jump(toBlock: block) }
    }

    func jump(toSection section: Int) {
        if mode == .review { mode = .reading }
        move { $0.jump(toSection: section) }
    }

    func toggleWhole() {
        mode = mode == .reading ? .whole : .reading
    }

    private func move(_ change: (inout Navigator) -> Void) {
        guard mode != .review else { return }
        var navigator = navigator
        change(&navigator)
        apply(navigator)
    }

    private func apply(_ navigator: Navigator) {
        guard navigator.position != session.position || navigator.level != session.level else { return }
        session.position = navigator.position
        session.level = navigator.level
        noteDraft = nil
        changed()
        if isSpeaking {
            speakCurrentUnit()
        }
    }

    // MARK: Reading aloud

    func toggleSpeech() {
        if isSpeaking {
            stopSpeaking()
        } else {
            speakCurrentUnit()
        }
    }

    func stopSpeaking() {
        guard isSpeaking else { return }
        speechEnded()
        Speaker.shared.stop()
    }

    func spokenRange(in block: Int) -> Range<Int>? {
        spokenBlock == block ? spokenRange : nil
    }

    private func speakCurrentUnit() {
        guard let unit, mode != .review else { return }
        isSpeaking = true
        spokenBlock = nil
        spokenRange = nil
        Speaker.shared.speak(document.speechItems(for: unit), for: self, handlers: Speaker.Handlers(
            onWord: { [weak self] block, range in
                self?.spokenBlock = block
                self?.spokenRange = range
            },
            onFinish: { [weak self] in self?.finishedSpeakingUnit() },
            onInterrupt: { [weak self] in self?.speechEnded() }
        ))
    }

    private func finishedSpeakingUnit() {
        var navigator = navigator
        guard Preferences.shared.autoAdvancesSpeech, navigator.next() else {
            speechEnded()
            return
        }
        apply(navigator)
    }

    private func speechEnded() {
        isSpeaking = false
        spokenBlock = nil
        spokenRange = nil
    }

    // MARK: Notes

    func notes(in blocks: Range<Int>) -> [Note] {
        session.notes.filter { blocks.contains($0.blockID) }
    }

    func startNote() {
        guard let unit, mode != .review else { return }
        mode = .reading
        let quote = document.plainText(of: unit)
        let existing = session.notes.first { $0.blockID == currentBlocks.lowerBound && $0.quote == quote }
        editingNoteID = existing?.id
        noteDraft = existing?.response ?? ""
    }

    func commitNote() {
        guard let draft = noteDraft, let unit else { return }
        let response = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = editingNoteID, let index = session.notes.firstIndex(where: { $0.id == id }) {
            if response.isEmpty {
                session.notes.remove(at: index)
            } else {
                session.notes[index].response = response
            }
        } else if !response.isEmpty {
            session.notes.append(Note(blockID: currentBlocks.lowerBound, quote: document.plainText(of: unit), response: response))
        }
        noteDraft = nil
        editingNoteID = nil
        notesCopied = false
        changed()
    }

    func deleteNote(_ id: UUID) {
        session.notes.removeAll { $0.id == id }
        notesCopied = false
        changed()
    }

    var notesMarkdown: String {
        NotesExporter.markdown(notes: session.notes)
    }

    func copyNotes() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(notesMarkdown, forType: .string)
        notesCopied = true
    }

    // MARK: Parking lot

    func startParking() {
        guard !isEmpty, mode != .review else { return }
        parkDraft = ""
    }

    func commitParking() {
        guard let draft = parkDraft else { return }
        let thought = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !thought.isEmpty {
            session.parked.append(thought)
            changed()
        }
        parkDraft = nil
    }

    func deleteParked(at index: Int) {
        guard session.parked.indices.contains(index) else { return }
        session.parked.remove(at: index)
        changed()
    }

    func copyParked() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(session.parked.map { "- \($0)" }.joined(separator: "\n") + "\n", forType: .string)
    }

    // MARK: Questions

    func editAsks() {
        askDraft = session.asks.joined(separator: "\n")
    }

    func commitAsks() {
        guard let draft = askDraft else { return }
        session.asks = draft.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        askDraft = nil
        changed()
    }

    func cancelEditing() {
        noteDraft = nil
        editingNoteID = nil
        askDraft = nil
        parkDraft = nil
    }

    // MARK: Saving

    private func changed() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        guard !session.markdown.isEmpty else { return }
        try? store.save(session)
    }

    /// Removes the stored session and, if a CLI call is waiting on it, hands the notes back.
    func discard(paths: SpacedPaths) {
        stopSpeaking()
        pendingSave?.cancel()
        pendingSave = nil
        if let id = session.awaitedRequestID {
            let notes = notesMarkdown
            try? ReviewRequest.writeResult(notes.isEmpty ? NotesExporter.emptyMessage : notes, for: id, in: paths)
        }
        store.delete(session.id)
    }
}
