import Foundation

/// A document handed to the app by the CLI. The CLI writes it into `requests/`; the app picks it up and deletes it.
/// When `wait` is set, the app later writes the notes to `results/<id>.md`, which the CLI is watching for.
public struct ReviewRequest: Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String?
    public var sourcePath: String?
    public var markdown: String
    public var asks: [String]
    public var wait: Bool

    public init(id: UUID = UUID(), title: String? = nil, sourcePath: String? = nil, markdown: String,
                asks: [String] = [], wait: Bool = false) {
        self.id = id
        self.title = title
        self.sourcePath = sourcePath
        self.markdown = markdown
        self.asks = asks
        self.wait = wait
    }

    public func write(to paths: SpacedPaths) throws {
        try paths.createDirectories()
        let url = paths.requests.appendingPathComponent("\(id.uuidString).json")
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    /// Reads and removes every pending request, oldest first.
    public static func takePending(from paths: SpacedPaths) -> [ReviewRequest] {
        let keys: [URLResourceKey] = [.creationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: paths.requests, includingPropertiesForKeys: keys)) ?? []
        let dated = files.filter { $0.pathExtension == "json" }.map { url in
            (url, (try? url.resourceValues(forKeys: Set(keys)).creationDate) ?? .distantPast)
        }
        return dated.sorted { $0.1 < $1.1 }.compactMap { url, _ in
            defer { try? FileManager.default.removeItem(at: url) }
            return try? JSONDecoder().decode(ReviewRequest.self, from: Data(contentsOf: url))
        }
    }

    public static func resultURL(for id: UUID, in paths: SpacedPaths) -> URL {
        paths.results.appendingPathComponent("\(id.uuidString).md")
    }

    public static func writeResult(_ text: String, for id: UUID, in paths: SpacedPaths) throws {
        try paths.createDirectories()
        try Data(text.utf8).write(to: resultURL(for: id, in: paths), options: .atomic)
    }

    /// Returns the result and removes it, or nil if the review isn't finished yet.
    public static func takeResult(for id: UUID, in paths: SpacedPaths) -> String? {
        let url = resultURL(for: id, in: paths)
        guard let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.removeItem(at: url)
        return String(decoding: data, as: UTF8.self)
    }
}
