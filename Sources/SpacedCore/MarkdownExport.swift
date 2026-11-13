import Foundation

/// Turns parsed blocks back into markdown, for copying what is on screen.
public enum InlineMarkdown {
    public static func render(_ text: AttributedString) -> String {
        var result = ""
        var linked = ""
        var currentLink: URL?

        func closeLink() {
            if let link = currentLink {
                result += "[\(linked)](\(link.absoluteString))"
            }
            linked = ""
            currentLink = nil
        }

        for run in text.runs {
            let piece = styled(String(text[run.range].characters), run.inlinePresentationIntent ?? [])
            if run.link != currentLink {
                closeLink()
                currentLink = run.link
            }
            if currentLink == nil {
                result += piece
            } else {
                linked += piece
            }
        }
        closeLink()
        return result
    }

    private static func styled(_ string: String, _ intent: InlinePresentationIntent) -> String {
        if intent.contains(.code) { return "`\(string)`" }
        var wrapper = ""
        if intent.contains(.strikethrough) { wrapper += "~~" }
        if intent.contains(.stronglyEmphasized) { wrapper += "**" }
        if intent.contains(.emphasized) { wrapper += "*" }
        guard !wrapper.isEmpty else { return string }
        // Markers must hug the words, so surrounding spaces stay outside them.
        let core = string.trimmingCharacters(in: .whitespaces)
        guard !core.isEmpty else { return string }
        let leading = String(string.prefix { $0 == " " })
        let trailing = String(string.reversed().prefix { $0 == " " })
        return leading + wrapper + core + String(wrapper.reversed()) + trailing
    }
}

extension Block {
    /// This block as a line (or lines) of markdown. Table rows come out as a bare row; see `Document.markdown(of:)`.
    public var markdown: String {
        switch kind {
        case .heading(let level):
            return String(repeating: "#", count: level) + " " + InlineMarkdown.render(text)
        case .paragraph:
            return InlineMarkdown.render(text)
        case .listItem(let depth, let marker):
            let indent = String(repeating: "  ", count: depth)
            let bullet: String
            switch marker {
            case "•": bullet = "- "
            case "☐": bullet = "- [ ] "
            case "☑": bullet = "- [x] "
            case "": bullet = "  "
            default: bullet = marker + " "
            }
            return indent + bullet + InlineMarkdown.render(text)
        case .quote:
            return "> " + InlineMarkdown.render(text)
        case .code(let language):
            return "```\(language ?? "")\n\(plainText)\n```"
        case .tableRow(_, let cells, _, _):
            return Self.tableLine(cells.map(InlineMarkdown.render))
        }
    }

    fileprivate static func tableLine(_ cells: [String]) -> String {
        "| " + cells.joined(separator: " | ") + " |"
    }
}

extension Document {
    /// The markdown for what a reading unit shows. Table rows are given their header so they stand alone.
    public func markdown(of unit: ReadingUnit) -> String {
        if case .sentence(let index, let sentence) = unit, blocks[index].sentences.count > 1 {
            return InlineMarkdown.render(blocks[index].sentenceText(sentence))
        }
        var result = ""
        var previous: Block?
        for block in blocks[blockRange(of: unit)] {
            if let previous {
                let sameGroup = (previous.isTableRow && block.isTableRow) || (previous.isListItem && block.isListItem)
                result += sameGroup ? "\n" : "\n\n"
            }
            if case .tableRow(let header, _, _, _) = block.kind, previous?.isTableRow != true {
                result += Block.tableLine(header.map(InlineMarkdown.render)) + "\n"
                result += Block.tableLine(header.map { _ in "---" }) + "\n"
            }
            result += block.markdown
            previous = block
        }
        return result
    }

    /// The section a `#fragment` link points at, using GitHub's heading-anchor rules.
    public func section(forAnchor fragment: String) -> Int? {
        let wanted = (fragment.removingPercentEncoding ?? fragment).lowercased()
        var seen: [String: Int] = [:]
        for section in sections where !section.title.isEmpty {
            let base = Self.anchor(for: section.title)
            let count = seen[base, default: 0]
            seen[base] = count + 1
            if (count == 0 ? base : "\(base)-\(count)") == wanted {
                return section.id
            }
        }
        return nil
    }

    static func anchor(for title: String) -> String {
        let kept = title.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" || $0 == "_" }
        return kept.replacingOccurrences(of: " ", with: "-")
    }
}
