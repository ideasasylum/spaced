import Foundation
import Testing
@testable import SpacedCore

private let fixture = """
Intro paragraph before any heading.

# Title

First sentence here. Second sentence here! A third one?

- Item one
- Item two with **bold**
  - Nested item
- [ ] Todo
- [x] Done

1. First
2. Second

## Data

| Name | Value |
| --- | --- |
| alpha | 1 |
| beta | `2` |

```swift
let x = 1
let y = 2
```

> A quoted line.

---

### Deep

Last paragraph.
"""

@Suite struct ParserTests {
    let document = Document(markdown: fixture)

    @Test func flattensBlocksInReadingOrder() {
        let kinds = document.blocks.map(\.kind)
        #expect(kinds[0] == .paragraph)
        #expect(kinds[1] == .heading(level: 1))
        #expect(kinds[2] == .paragraph)
        #expect(kinds[3] == .listItem(depth: 0, marker: "•"))
        #expect(kinds[5] == .listItem(depth: 1, marker: "•"))
        #expect(kinds[6] == .listItem(depth: 0, marker: "☐"))
        #expect(kinds[7] == .listItem(depth: 0, marker: "☑"))
        #expect(kinds[8] == .listItem(depth: 0, marker: "1."))
        #expect(kinds[9] == .listItem(depth: 0, marker: "2."))
        #expect(kinds[10] == .heading(level: 2))
        #expect(kinds[13] == .code(language: "swift"))
        #expect(kinds[14] == .quote)
        #expect(kinds[15] == .heading(level: 3))
        #expect(document.blocks.count == 17)
    }

    @Test func keepsInlineStylingOutOfPlainText() {
        #expect(document.blocks[4].plainText == "Item two with bold")
        #expect(document.blocks[13].plainText == "let x = 1\nlet y = 2")
        #expect(document.blocks[14].plainText == "A quoted line.")
    }

    @Test func tableRowsCarryTheirHeader() {
        guard case .tableRow(let header, let cells, let row) = document.blocks[12].kind else {
            Issue.record("expected a table row")
            return
        }
        #expect(header.map { String($0.characters) } == ["Name", "Value"])
        #expect(cells.map { String($0.characters) } == ["beta", "2"])
        #expect(row == 1)
        #expect(document.blocks[11].plainText == "alpha | 1")
    }

    @Test func sectionsRunFromHeadingToHeading() {
        #expect(document.sections.map(\.title) == ["", "Title", "Data", "Deep"])
        #expect(document.sections.map(\.blocks) == [0..<1, 1..<10, 10..<15, 15..<17])
        #expect(document.blocks[12].section == 2)
        #expect(document.title == "Title")
    }

    @Test func splitsSentences() {
        let block = document.blocks[2]
        #expect(block.sentences.count == 3)
        #expect(block.sentencePlainText(0) == "First sentence here.")
        #expect(block.sentencePlainText(2) == "A third one?")
        #expect(document.blocks[13].sentences.count == 1)
    }

    @Test func softBreaksBecomeSpaces() {
        let wrapped = Document(markdown: "one\ntwo")
        #expect(wrapped.blocks[0].plainText == "one two")
    }
}

@Suite struct NavigatorTests {
    let document = Document(markdown: fixture)

    @Test func stepsThroughBlocks() {
        var navigator = Navigator(document: document)
        #expect(navigator.unit == .block(0))
        let moved1 = navigator.next()
        #expect(moved1)
        #expect(navigator.unit == .block(1))
        let moved2 = navigator.previous()
        #expect(moved2)
        let moved3 = navigator.previous()
        #expect(!moved3)
        navigator.jump(toBlock: 16)
        let moved4 = navigator.next()
        #expect(!moved4)
    }

    @Test func stepsThroughSentencesAcrossBlocks() {
        var navigator = Navigator(document: document, position: Position(block: 2), level: .sentence)
        navigator.next()
        navigator.next()
        #expect(navigator.unit == .sentence(block: 2, index: 2))
        navigator.next()
        #expect(navigator.unit == .sentence(block: 3, index: 0))
        navigator.previous()
        #expect(navigator.unit == .sentence(block: 2, index: 2))
    }

    @Test func wideningAndNarrowingKeepsThePlace() {
        var navigator = Navigator(document: document, position: Position(block: 4))
        navigator.widen()
        #expect(navigator.unit == .section(1))
        navigator.widen()
        #expect(navigator.level == .section)
        navigator.narrow()
        #expect(navigator.unit == .block(4))
        navigator.narrow()
        #expect(navigator.unit == .sentence(block: 4, index: 0))
        navigator.narrow()
        #expect(navigator.level == .sentence)
    }

    @Test func stepsThroughSections() {
        var navigator = Navigator(document: document, position: Position(block: 4), level: .section)
        navigator.next()
        #expect(navigator.unit == .section(2))
        #expect(navigator.position.block == 10)
        navigator.next()
        let moved5 = navigator.next()
        #expect(!moved5)
        navigator.previous()
        #expect(navigator.unit == .section(2))
    }

    @Test func sectionJumps() {
        var navigator = Navigator(document: document, position: Position(block: 12))
        navigator.previousSection()
        #expect(navigator.position.block == 10)
        navigator.previousSection()
        #expect(navigator.position.block == 1)
        navigator.nextSection()
        #expect(navigator.position.block == 10)
    }

    @Test func clampsStalePositions() {
        let navigator = Navigator(document: document, position: Position(block: 99, sentence: 99))
        #expect(navigator.position == Position(block: 16, sentence: 0))
        #expect(Navigator(document: Document(markdown: "")).unit == nil)
    }

    @Test func progressCountsWordsBeforeThePosition() {
        let short = Document(markdown: "# One two\n\nThree four. Five six.\n\nSeven eight nine ten.")
        #expect(short.progress(at: Position()) == ReadingProgress(fraction: 0, wordsLeft: 10))
        #expect(short.progress(at: Position(block: 1, sentence: 1)) == ReadingProgress(fraction: 0.4, wordsLeft: 6))
        #expect(short.progress(at: Position(block: 2)).wordsLeft == 4)
        #expect(ReadingProgress(fraction: 0, wordsLeft: 201).minutesLeft == 2)
        #expect(Document(markdown: "").progress(at: Position()).fraction == 0)
    }

    @Test func unitText() {
        #expect(document.plainText(of: .sentence(block: 2, index: 1)) == "Second sentence here!")
        #expect(document.plainText(of: .section(3)) == "Deep\n\nLast paragraph.")
    }
}

@Suite struct ExportAndStorageTests {
    @Test func exportsNotesAsBlockquoteThenResponse() {
        let notes = [
            Note(blockID: 5, quote: "Later", response: "second\n"),
            Note(blockID: 1, quote: "Line one\n\nLine two", response: "first"),
        ]
        #expect(NotesExporter.markdown(notes: notes) == """
        > Line one
        >
        > Line two

        first

        > Later

        second

        """)
        #expect(NotesExporter.markdown(notes: []) == "")
    }

    @Test func sessionsRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(directory: directory)
        var session = Session(title: "Doc", markdown: "# Doc", asks: ["Why?"], createdAt: Date(timeIntervalSince1970: 100))
        session.notes = [Note(blockID: 0, quote: "Doc", response: "ok", created: Date(timeIntervalSince1970: 50))]
        session.position = Position(block: 3, sentence: 1)
        session.level = .sentence
        try store.save(session)
        try store.save(Session(title: "Earlier", createdAt: Date(timeIntervalSince1970: 10)))
        let loaded = store.loadAll()
        #expect(loaded.map(\.title) == ["Earlier", "Doc"])
        #expect(loaded[1] == session)
        store.delete(session.id)
        #expect(store.loadAll().count == 1)
    }

    @Test func requestsAndResultsPassThroughTheFileSystem() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SpacedPaths(root: root)
        let request = ReviewRequest(title: "Plan", markdown: "# Plan", asks: ["Safe?"], wait: true)
        try request.write(to: paths)
        #expect(ReviewRequest.takePending(from: paths) == [request])
        #expect(ReviewRequest.takePending(from: paths).isEmpty)
        #expect(ReviewRequest.takeResult(for: request.id, in: paths) == nil)
        try ReviewRequest.writeResult("> a\n\nb\n", for: request.id, in: paths)
        #expect(ReviewRequest.takeResult(for: request.id, in: paths) == "> a\n\nb\n")
        #expect(ReviewRequest.takeResult(for: request.id, in: paths) == nil)
    }

    @Test func titlesFallBackSensibly() {
        #expect(Session.title(for: Document(markdown: "# Hello"), markdown: "# Hello", sourcePath: "/tmp/a.md") == "Hello")
        #expect(Session.title(for: Document(markdown: "text"), markdown: "text", sourcePath: "/tmp/a.md") == "a.md")
        #expect(Session.title(for: Document(markdown: "just text"), markdown: "just text", sourcePath: nil) == "just text")
    }
}
