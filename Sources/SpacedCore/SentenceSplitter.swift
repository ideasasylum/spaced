import Foundation
import NaturalLanguage

enum SentenceSplitter {
    /// Character-offset ranges of each sentence, with surrounding whitespace trimmed. Never empty.
    static func split(_ text: String) -> [Range<Int>] {
        let whole = 0..<text.count
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var ranges: [Range<Int>] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            var lower = range.lowerBound
            var upper = range.upperBound
            while lower < upper, text[lower].isWhitespace {
                lower = text.index(after: lower)
            }
            while lower < upper, text[text.index(before: upper)].isWhitespace {
                upper = text.index(before: upper)
            }
            if lower < upper {
                let start = text.distance(from: text.startIndex, to: lower)
                ranges.append(start..<(start + text.distance(from: lower, to: upper)))
            }
            return true
        }
        return ranges.isEmpty ? [whole] : ranges
    }
}
