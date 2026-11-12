import Foundation

public struct Note: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var blockID: Int
    public var quote: String
    public var response: String
    public var created: Date

    public init(id: UUID = UUID(), blockID: Int, quote: String, response: String, created: Date = Date()) {
        self.id = id
        self.blockID = blockID
        self.quote = quote
        self.response = response
        self.created = created
    }
}

/// Everything needed to bring a tab back: the document text, where the reader is, and what they've written.
public struct Session: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var sourcePath: String?
    public var markdown: String
    public var asks: [String]
    public var notes: [Note]
    public var position: Position
    public var level: FocusLevel
    /// Set when a CLI invocation is blocked waiting for this session's notes.
    public var awaitedRequestID: UUID?
    public var createdAt: Date

    public init(id: UUID = UUID(), title: String = "Untitled", sourcePath: String? = nil, markdown: String = "",
                asks: [String] = [], notes: [Note] = [], position: Position = Position(),
                level: FocusLevel = .block, awaitedRequestID: UUID? = nil, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.sourcePath = sourcePath
        self.markdown = markdown
        self.asks = asks
        self.notes = notes
        self.position = position
        self.level = level
        self.awaitedRequestID = awaitedRequestID
        self.createdAt = createdAt
    }

    public static func title(for document: Document, markdown: String, sourcePath: String?) -> String {
        if let title = document.title { return title }
        if let sourcePath { return URL(fileURLWithPath: sourcePath).lastPathComponent }
        let firstLine = markdown.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return firstLine.isEmpty ? "Untitled" : String(firstLine.prefix(40))
    }
}
