import Foundation

public enum NotesExporter {
    public static let emptyMessage = "No notes were left on this document.\n"

    /// Each note as a blockquote of the text it was written against, followed by the response, in document order.
    public static func markdown(notes: [Note]) -> String {
        let ordered = notes.sorted { ($0.blockID, $0.created) < ($1.blockID, $1.created) }
        guard !ordered.isEmpty else { return "" }
        return ordered.map { note in
            let quote = note.quote
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.isEmpty ? ">" : "> \($0)" }
                .joined(separator: "\n")
            return quote + "\n\n" + note.response.trimmingCharacters(in: .whitespacesAndNewlines)
        }.joined(separator: "\n\n") + "\n"
    }
}
