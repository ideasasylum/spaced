import Foundation

public struct SpacedPaths: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// `~/Library/Application Support/Spaced`, or `$SPACED_HOME` when set.
    public static var standard: SpacedPaths {
        if let override = ProcessInfo.processInfo.environment["SPACED_HOME"], !override.isEmpty {
            return SpacedPaths(root: URL(fileURLWithPath: override))
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return SpacedPaths(root: support.appendingPathComponent("Spaced"))
    }

    public var sessions: URL { root.appendingPathComponent("sessions") }
    public var requests: URL { root.appendingPathComponent("requests") }
    public var results: URL { root.appendingPathComponent("results") }

    public func createDirectories() throws {
        for directory in [sessions, requests, results] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}

public struct SessionStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func save(_ session: Session) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(session).write(to: url(for: session.id), options: .atomic)
    }

    public func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
    }

    public func loadAll() -> [Session] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(Session.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func url(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }
}
