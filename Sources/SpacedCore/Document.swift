import Foundation

/// How wide a table column wants to be, in characters, worked out across the whole table.
public struct TableColumnSize: Equatable, Sendable {
    /// The longest single word, which the column must fit to avoid breaking words.
    public let longestWord: Int
    /// The longest cell, which the column would need to avoid wrapping at all.
    public let longestCell: Int

    public init(longestWord: Int, longestCell: Int) {
        self.longestWord = longestWord
        self.longestCell = longestCell
    }
}

/// One piece of the document in reading order: a heading, paragraph, list item, table row, code block or quote.
public struct Block: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case heading(level: Int)
        case paragraph
        case listItem(depth: Int, marker: String)
        case tableRow(header: [AttributedString], cells: [AttributedString], row: Int, columns: [TableColumnSize])
        case code(language: String?)
        case quote
    }

    public let id: Int
    public let kind: Kind
    public let text: AttributedString
    public let plainText: String
    /// Character-offset ranges into `plainText`. Always at least one.
    public let sentences: [Range<Int>]
    public let section: Int

    public var isTableRow: Bool {
        if case .tableRow = kind { return true }
        return false
    }

    public var isFirstTableRow: Bool {
        if case .tableRow(_, _, 0, _) = kind { return true }
        return false
    }

    public func sentenceText(_ index: Int) -> AttributedString {
        guard sentences.count > 1, sentences.indices.contains(index) else { return text }
        let range = sentences[index]
        let chars = text.characters
        let start = chars.index(chars.startIndex, offsetBy: range.lowerBound)
        let end = chars.index(chars.startIndex, offsetBy: range.upperBound)
        return AttributedString(text[start..<end])
    }

    public func sentencePlainText(_ index: Int) -> String {
        String(sentenceText(index).characters)
    }
}

/// Everything from one heading up to the next. Blocks before the first heading form an untitled section.
public struct Section: Identifiable, Equatable, Sendable {
    public let id: Int
    public let title: String
    public let level: Int
    public let blocks: Range<Int>
}

public enum ReadingUnit: Equatable, Sendable {
    case sentence(block: Int, index: Int)
    case block(Int)
    case section(Int)
}

public struct ReadingProgress: Equatable, Sendable {
    public static let wordsPerMinute = 200.0

    /// How much of the document comes before the current position, from 0 to 1.
    public let fraction: Double
    public let wordsLeft: Int

    public var minutesLeft: Int {
        Int((Double(wordsLeft) / Self.wordsPerMinute).rounded(.up))
    }
}

public struct Document: Equatable, Sendable {
    public let blocks: [Block]
    public let sections: [Section]
    private let wordCounts: [Int]

    public init(blocks: [Block], sections: [Section]) {
        self.blocks = blocks
        self.sections = sections
        wordCounts = blocks.map { $0.plainText.split(whereSeparator: \.isWhitespace).count }
    }

    /// Progress by word count. The current sentence or block counts as still to read.
    public func progress(at position: Position) -> ReadingProgress {
        let total = wordCounts.reduce(0, +)
        guard total > 0, blocks.indices.contains(position.block) else {
            return ReadingProgress(fraction: 0, wordsLeft: 0)
        }
        let block = blocks[position.block]
        let withinBlock = wordCounts[position.block] * position.sentence / block.sentences.count
        let read = wordCounts[..<position.block].reduce(0, +) + withinBlock
        return ReadingProgress(fraction: Double(read) / Double(total), wordsLeft: total - read)
    }

    public init(markdown: String) {
        self = MarkdownParser.parse(markdown)
    }

    public var isEmpty: Bool { blocks.isEmpty }

    public var title: String? {
        sections.first(where: { !$0.title.isEmpty })?.title
    }

    public func blockRange(of unit: ReadingUnit) -> Range<Int> {
        switch unit {
        case .sentence(let block, _), .block(let block):
            return block..<(block + 1)
        case .section(let section):
            return sections[section].blocks
        }
    }

    public func plainText(of unit: ReadingUnit) -> String {
        switch unit {
        case .sentence(let block, let index):
            return blocks[block].sentencePlainText(index)
        case .block(let block):
            return blocks[block].plainText
        case .section(let section):
            return blocks[sections[section].blocks].map(\.plainText).joined(separator: "\n\n")
        }
    }
}

/// One stretch of text to read aloud, tied to the block it comes from so the spoken word can be highlighted.
public struct SpeechItem: Equatable, Sendable {
    public let block: Int
    public let text: String
    /// Where `text` starts within the block's plain text, or nil when the spoken words aren't the block's own
    /// (a description of a table row or code block), in which case nothing is highlighted.
    public let offsetInBlock: Int?
}

extension Document {
    /// What to say for a reading unit: prose as written, table rows with their column names, and code
    /// blocks as a short description, since code read aloud is noise.
    public func speechItems(for unit: ReadingUnit) -> [SpeechItem] {
        switch unit {
        case .sentence(let index, let sentence):
            let block = blocks[index]
            guard block.sentences.count > 1 else { return [speechItem(for: block)] }
            return [SpeechItem(block: index, text: block.sentencePlainText(sentence),
                               offsetInBlock: block.sentences[sentence].lowerBound)]
        case .block(let index):
            return [speechItem(for: blocks[index])]
        case .section(let index):
            return blocks[sections[index].blocks].map(speechItem)
        }
    }

    private func speechItem(for block: Block) -> SpeechItem {
        switch block.kind {
        case .code(let language):
            let lines = block.plainText.split(separator: "\n", omittingEmptySubsequences: false).count
            let name = language.map { "\($0) " } ?? ""
            return SpeechItem(block: block.id, text: "\(name)code block, \(lines) line\(lines == 1 ? "" : "s").",
                              offsetInBlock: nil)
        case .tableRow(let header, let cells, _, _):
            let parts = cells.enumerated().map { column, cell in
                let name = column < header.count ? String(header[column].characters) + ": " : ""
                return name + String(cell.characters)
            }
            return SpeechItem(block: block.id, text: parts.joined(separator: ". ") + ".", offsetInBlock: nil)
        default:
            return SpeechItem(block: block.id, text: block.plainText, offsetInBlock: 0)
        }
    }
}
