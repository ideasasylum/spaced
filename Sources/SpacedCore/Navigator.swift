import Foundation

public enum FocusLevel: Int, Codable, Sendable {
    case sentence, block, section
}

public struct Position: Codable, Equatable, Sendable {
    public var block: Int
    public var sentence: Int

    public init(block: Int = 0, sentence: Int = 0) {
        self.block = block
        self.sentence = sentence
    }
}

/// Moves a reading position through a document at the current focus level.
public struct Navigator {
    public let document: Document
    public private(set) var position: Position
    public private(set) var level: FocusLevel

    public init(document: Document, position: Position = Position(), level: FocusLevel = .block) {
        self.document = document
        self.level = level
        let block = min(max(position.block, 0), max(document.blocks.count - 1, 0))
        let sentenceCount = document.blocks.isEmpty ? 1 : document.blocks[block].sentences.count
        self.position = Position(block: block, sentence: min(max(position.sentence, 0), sentenceCount - 1))
    }

    public var unit: ReadingUnit? {
        guard !document.isEmpty else { return nil }
        switch level {
        case .sentence: return .sentence(block: position.block, index: position.sentence)
        case .block: return .block(position.block)
        case .section: return .section(document.blocks[position.block].section)
        }
    }

    /// Returns false when already at the end of the document.
    @discardableResult
    public mutating func next() -> Bool {
        guard !document.isEmpty else { return false }
        let lastBlock = document.blocks.count - 1
        switch level {
        case .sentence:
            if position.sentence + 1 < document.blocks[position.block].sentences.count {
                position.sentence += 1
                return true
            }
            guard position.block < lastBlock else { return false }
            position = Position(block: position.block + 1)
        case .block:
            guard position.block < lastBlock else { return false }
            position = Position(block: position.block + 1)
        case .section:
            let section = document.blocks[position.block].section
            guard section + 1 < document.sections.count else { return false }
            position = Position(block: document.sections[section + 1].blocks.lowerBound)
        }
        return true
    }

    /// Returns false when already at the start of the document.
    @discardableResult
    public mutating func previous() -> Bool {
        guard !document.isEmpty else { return false }
        switch level {
        case .sentence:
            if position.sentence > 0 {
                position.sentence -= 1
                return true
            }
            guard position.block > 0 else { return false }
            let block = position.block - 1
            position = Position(block: block, sentence: document.blocks[block].sentences.count - 1)
        case .block:
            guard position.block > 0 else { return false }
            position = Position(block: position.block - 1)
        case .section:
            let section = document.blocks[position.block].section
            guard section > 0 else { return false }
            position = Position(block: document.sections[section - 1].blocks.lowerBound)
        }
        return true
    }

    public mutating func widen() {
        level = FocusLevel(rawValue: level.rawValue + 1) ?? level
    }

    public mutating func narrow() {
        level = FocusLevel(rawValue: level.rawValue - 1) ?? level
    }

    public mutating func jump(toBlock block: Int) {
        guard document.blocks.indices.contains(block) else { return }
        position = Position(block: block)
    }

    public mutating func jump(toSection section: Int) {
        guard document.sections.indices.contains(section) else { return }
        position = Position(block: document.sections[section].blocks.lowerBound)
    }

    public mutating func nextSection() {
        guard !document.isEmpty else { return }
        jump(toSection: document.blocks[position.block].section + 1)
    }

    /// Goes to the start of the current section, or the previous one if already there.
    public mutating func previousSection() {
        guard !document.isEmpty else { return }
        let section = document.blocks[position.block].section
        let start = document.sections[section].blocks.lowerBound
        if position.block == start, position.sentence == 0 {
            jump(toSection: section - 1)
        } else {
            position = Position(block: start)
        }
    }
}
