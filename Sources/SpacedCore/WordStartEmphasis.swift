import Foundation

/// Bolds the first part of every word, which some readers find keeps their eyes moving along a line.
public enum WordStartEmphasis {
    public static func apply(to text: AttributedString) -> AttributedString {
        var result = text
        var wordStart: AttributedString.Index?
        var wordLength = 0

        func emphasiseWord() {
            defer {
                wordStart = nil
                wordLength = 0
            }
            guard let start = wordStart else { return }
            let boldEnd = result.characters.index(start, offsetBy: (wordLength * 2 + 4) / 5)
            for run in result[start..<boldEnd].runs {
                let intent = run.inlinePresentationIntent ?? []
                if !intent.contains(.code) {
                    result[run.range].inlinePresentationIntent = intent.union(.stronglyEmphasized)
                }
            }
        }

        var index = result.startIndex
        while index < result.endIndex {
            let character = result.characters[index]
            if character.isLetter || character.isNumber {
                if wordStart == nil { wordStart = index }
                wordLength += 1
            } else {
                emphasiseWord()
            }
            index = result.characters.index(after: index)
        }
        emphasiseWord()
        return result
    }
}
