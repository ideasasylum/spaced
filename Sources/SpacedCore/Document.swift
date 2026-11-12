import Foundation

/// One piece of the document in reading order: a heading, paragraph, list item, table row, code block or quote.
public struct Block: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case heading(level: Int)
        case paragraph
        case listItem(depth: Int, marker: String)
        case tableRow(header: [AttributedString], cells: [AttributedString], row: Int)
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

public struct Document: Equatable, Sendable {
    public let blocks: [Block]
    public let sections: [Section]

    public init(blocks: [Block], sections: [Section]) {
        self.blocks = blocks
        self.sections = sections
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
