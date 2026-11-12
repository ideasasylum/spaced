import AppKit
import Highlightr
import SwiftUI

/// Colours code with highlight.js (via Highlightr). Results are cached, since the same blocks are drawn
/// in both the backdrop and the porthole.
@MainActor
final class CodeHighlighter {
    static let shared = CodeHighlighter()

    private let light = CodeHighlighter.engine(theme: "atom-one-light")
    private let dark = CodeHighlighter.engine(theme: "atom-one-dark")
    private var cache: [Key: AttributedString] = [:]

    private struct Key: Hashable {
        let code: String
        let language: String
        let dark: Bool
    }

    /// Returns the code with colours applied, or plain when the language is missing or unknown.
    func highlight(_ code: String, language: String?, dark isDark: Bool) -> AttributedString {
        guard let language = language?.lowercased(), !language.isEmpty else { return AttributedString(code) }
        let key = Key(code: code, language: language, dark: isDark)
        if let cached = cache[key] { return cached }
        let result = (isDark ? dark : light)?
            .highlight(code, as: language)
            .map(Self.coloured) ?? AttributedString(code)
        cache[key] = result
        return result
    }

    private static func engine(theme: String) -> Highlightr? {
        let engine = Highlightr()
        engine?.setTheme(to: theme)
        return engine
    }

    /// Keeps only colour and bold/italic, so the view decides the font and size.
    private static func coloured(_ source: NSAttributedString) -> AttributedString {
        var result = AttributedString()
        source.enumerateAttributes(in: NSRange(location: 0, length: source.length)) { attributes, range, _ in
            var piece = AttributedString(source.attributedSubstring(from: range).string)
            if let colour = attributes[.foregroundColor] as? NSColor {
                piece.foregroundColor = Color(nsColor: colour)
            }
            if let font = attributes[.font] as? NSFont {
                let traits = font.fontDescriptor.symbolicTraits
                var intent: InlinePresentationIntent = []
                if traits.contains(.bold) { intent.insert(.stronglyEmphasized) }
                if traits.contains(.italic) { intent.insert(.emphasized) }
                if !intent.isEmpty { piece.inlinePresentationIntent = intent }
            }
            result += piece
        }
        return result
    }
}
