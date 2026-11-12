import Foundation
import Markdown

enum MarkdownParser {
    static func parse(_ source: String) -> Document {
        var builder = Builder()
        for child in Markdown.Document(parsing: source).children {
            builder.visit(child, depth: 0, quoted: false)
        }
        return builder.finish()
    }

    private struct Builder {
        private var blocks: [Block] = []
        private var sectionStarts: [(start: Int, title: String, level: Int)] = []

        mutating func visit(_ markup: Markup, depth: Int, quoted: Bool) {
            switch markup {
            case let heading as Heading:
                let text = Builder.attributed(heading)
                sectionStarts.append((blocks.count, String(text.characters), heading.level))
                add(.heading(level: heading.level), text: text)
            case let paragraph as Paragraph:
                add(quoted ? .quote : .paragraph, text: Builder.attributed(paragraph))
            case let list as UnorderedList:
                for item in list.listItems {
                    visit(item, marker: checkboxMarker(item) ?? "•", depth: depth, quoted: quoted)
                }
            case let list as OrderedList:
                var number = Int(list.startIndex)
                for item in list.listItems {
                    visit(item, marker: checkboxMarker(item) ?? "\(number).", depth: depth, quoted: quoted)
                    number += 1
                }
            case let quote as BlockQuote:
                for child in quote.children {
                    visit(child, depth: depth, quoted: true)
                }
            case let code as CodeBlock:
                addCode(code.code, language: code.language)
            case let html as HTMLBlock:
                addCode(html.rawHTML, language: "html")
            case let table as Markdown.Table:
                let header = Array(table.head.cells.map { Builder.attributed($0) })
                let rows = table.body.rows.map { row in Array(row.cells.map { Builder.attributed($0) }) }
                let columns = Builder.columns([header] + rows)
                for (index, cells) in rows.enumerated() {
                    let plain = cells.map { String($0.characters) }.joined(separator: " | ")
                    add(.tableRow(header: header, cells: cells, row: index, columns: columns),
                        text: AttributedString(plain))
                }
            case is ThematicBreak:
                break
            default:
                for child in markup.children {
                    visit(child, depth: depth, quoted: quoted)
                }
            }
        }

        private mutating func visit(_ item: ListItem, marker: String, depth: Int, quoted: Bool) {
            var isFirst = true
            for child in item.children {
                if let paragraph = child as? Paragraph {
                    add(.listItem(depth: depth, marker: isFirst ? marker : ""), text: Builder.attributed(paragraph))
                    isFirst = false
                } else if child is UnorderedList || child is OrderedList {
                    visit(child, depth: depth + 1, quoted: quoted)
                } else {
                    visit(child, depth: depth, quoted: quoted)
                }
            }
        }

        func finish() -> Document {
            var starts = sectionStarts
            if !blocks.isEmpty, starts.first?.start != 0 {
                starts.insert((0, "", 1), at: 0)
            }
            var sections: [Section] = []
            var sectionOfBlock = [Int](repeating: 0, count: blocks.count)
            for (index, start) in starts.enumerated() {
                let end = index + 1 < starts.count ? starts[index + 1].start : blocks.count
                sections.append(Section(id: index, title: start.title, level: start.level, blocks: start.start..<end))
                for block in start.start..<end {
                    sectionOfBlock[block] = index
                }
            }
            let placed = blocks.map {
                Block(id: $0.id, kind: $0.kind, text: $0.text, plainText: $0.plainText,
                      sentences: $0.sentences, section: sectionOfBlock[$0.id])
            }
            return Document(blocks: placed, sections: sections)
        }

        private mutating func add(_ kind: Block.Kind, text: AttributedString) {
            let plain = String(text.characters)
            let sentences: [Range<Int>]
            switch kind {
            case .paragraph, .listItem, .quote:
                sentences = SentenceSplitter.split(plain)
            default:
                sentences = [0..<plain.count]
            }
            blocks.append(Block(id: blocks.count, kind: kind, text: text, plainText: plain,
                                sentences: sentences, section: 0))
        }

        private mutating func addCode(_ code: String, language: String?) {
            var trimmed = code
            while trimmed.hasSuffix("\n") {
                trimmed.removeLast()
            }
            let language = language.flatMap { $0.isEmpty ? nil : $0 }
            blocks.append(Block(id: blocks.count, kind: .code(language: language),
                                text: AttributedString(trimmed), plainText: trimmed,
                                sentences: [0..<trimmed.count], section: 0))
        }

        private static func columns(_ rows: [[AttributedString]]) -> [TableColumnSize] {
            let count = rows.map(\.count).max() ?? 0
            return (0..<count).map { column in
                let cells = rows.compactMap { $0.indices.contains(column) ? String($0[column].characters) : nil }
                let words = cells.flatMap { $0.split(whereSeparator: \.isWhitespace) }
                return TableColumnSize(longestWord: words.map(\.count).max() ?? 0,
                                   longestCell: cells.map(\.count).max() ?? 0)
            }
        }

        private func checkboxMarker(_ item: ListItem) -> String? {
            switch item.checkbox {
            case .checked: return "☑"
            case .unchecked: return "☐"
            case nil: return nil
            }
        }

        private static func attributed(_ container: Markup) -> AttributedString {
            container.children.reduce(into: AttributedString()) { result, child in
                result += inline(child, intent: [], link: nil)
            }
        }

        private static func inline(_ markup: Markup, intent: InlinePresentationIntent, link: URL?) -> AttributedString {
            func leaf(_ string: String, _ intent: InlinePresentationIntent = intent) -> AttributedString {
                var text = AttributedString(string)
                if !intent.isEmpty {
                    text.inlinePresentationIntent = intent
                }
                text.link = link
                return text
            }
            func children(_ intent: InlinePresentationIntent, link: URL? = link) -> AttributedString {
                markup.children.reduce(into: AttributedString()) { result, child in
                    result += inline(child, intent: intent, link: link)
                }
            }
            switch markup {
            case let text as Markdown.Text: return leaf(text.string)
            case is Emphasis: return children(intent.union(.emphasized))
            case is Strong: return children(intent.union(.stronglyEmphasized))
            case is Strikethrough: return children(intent.union(.strikethrough))
            case let code as InlineCode: return leaf(code.code, intent.union(.code))
            case let link as Markdown.Link: return children(intent, link: link.destination.flatMap(URL.init(string:)))
            case let image as Markdown.Image: return leaf("[image: \(image.plainText)]", intent.union(.emphasized))
            case is SoftBreak: return leaf(" ")
            case is LineBreak: return leaf("\n")
            case let html as InlineHTML: return leaf(html.rawHTML)
            default:
                if markup.childCount > 0 { return children(intent) }
                return leaf((markup as? PlainTextConvertibleMarkup)?.plainText ?? "")
            }
        }
    }
}
