import SpacedCore
import SwiftUI

extension Color {
    static let page = Color(nsColor: .textBackgroundColor)

    /// One colour per heading level, so the level reads at a glance in the document and the sidebar.
    static func heading(_ level: Int) -> Color {
        switch level {
        case 1: return Color(nsColor: .systemIndigo)
        case 2: return Color(nsColor: .systemTeal)
        case 3: return Color(nsColor: .systemOrange)
        default: return Color(nsColor: .systemPink)
        }
    }
}

private struct EmphasisesWordStartsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether prose should have the start of each word bolded. Only the porthole turns this on.
    var emphasisesWordStarts: Bool {
        get { self[EmphasisesWordStartsKey.self] }
        set { self[EmphasisesWordStartsKey.self] = newValue }
    }
}

struct BlockView: View {
    let block: Block
    /// Replaces the block's text, used to show a single sentence.
    var text: AttributedString?
    /// Characters of the shown text to mark as being read aloud.
    var spoken: Range<Int>?
    let scale: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.emphasisesWordStarts) private var emphasisesWordStarts
    var showsTableHeader = false

    var body: some View {
        let content = markingSpoken(text ?? block.text)
        switch block.kind {
        case .heading(let level):
            Text(content)
                .font(.system(size: headingSize(level) * scale, weight: .bold))
                .foregroundStyle(Color.heading(level))
                .padding(.top, level <= 2 ? 10 * scale : 4 * scale)
                .wrapping()
        case .paragraph:
            body(content).wrapping()
        case .listItem(let depth, let marker):
            HStack(alignment: .firstTextBaseline, spacing: 8 * scale) {
                Text(marker)
                    .font(.system(size: 17 * scale))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 20 * scale, alignment: .trailing)
                body(content).wrapping()
            }
            .padding(.leading, CGFloat(depth) * 24 * scale)
        case .quote:
            body(content)
                .italic()
                .foregroundStyle(.secondary)
                .wrapping()
                .padding(.leading, 16 * scale)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5).fill(.tertiary).frame(width: 3)
                }
        case .code(let language):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(CodeHighlighter.shared.highlight(block.plainText, language: language, dark: colorScheme == .dark))
                    .font(.system(size: 14 * scale, design: .monospaced))
                    .lineSpacing(3 * scale)
                    .fixedSize()
            }
            .padding(14 * scale)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        case .tableRow(let header, let cells, _, let columns):
            VStack(alignment: .leading, spacing: 6 * scale) {
                if showsTableHeader {
                    row(header, columns).fontWeight(.semibold).foregroundStyle(.secondary)
                    Divider()
                }
                row(cells, columns)
            }
        }
    }

    private func markingSpoken(_ content: AttributedString) -> AttributedString {
        guard let spoken, !spoken.isEmpty, spoken.lowerBound >= 0,
              spoken.upperBound <= content.characters.count else { return content }
        var content = content
        let start = content.characters.index(content.startIndex, offsetBy: spoken.lowerBound)
        let end = content.characters.index(start, offsetBy: spoken.count)
        content[start..<end].backgroundColor = Color.accentColor.opacity(0.3)
        return content
    }

    private func body(_ content: AttributedString) -> Text {
        Text(emphasisesWordStarts ? WordStartEmphasis.apply(to: content) : content).font(.system(size: 17 * scale))
    }

    private func row(_ cells: [AttributedString], _ columns: [TableColumnSize]) -> some View {
        TableColumns(columns: columns, characterWidth: 9 * scale, spacing: 20 * scale) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                Text(cell).font(.system(size: 16 * scale)).wrapping()
            }
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 30
        case 2: return 24
        case 3: return 20
        default: return 17
        }
    }
}

/// Lays a table row's cells out in columns. Each column first gets room for its longest word, then the
/// space left over is shared out towards what each column would need to avoid wrapping.
struct TableColumns: Layout {
    let columns: [TableColumnSize]
    /// A generous estimate of one character's width, used to turn character counts into points.
    let characterWidth: CGFloat
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        let heights = zip(subviews, widths(for: width, count: subviews.count)).map { subview, column in
            subview.sizeThatFits(ProposedViewSize(width: column, height: nil)).height
        }
        return CGSize(width: width, height: heights.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, column) in zip(subviews, widths(for: bounds.width, count: subviews.count)) {
            subview.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: column, height: nil))
            x += column + spacing
        }
    }

    private func widths(for total: CGFloat, count: Int) -> [CGFloat] {
        guard count > 0 else { return [] }
        let available = max(total - spacing * CGFloat(count - 1), 0)
        let hints = (0..<count).map { columns.indices.contains($0) ? columns[$0] : TableColumnSize(longestWord: 8, longestCell: 8) }
        let minimums = fitted(hints.map { CGFloat(max($0.longestWord, 3)) * characterWidth }, into: available)
        let spare = available - minimums.reduce(0, +)
        guard spare > 0 else { return minimums }
        let wants = zip(hints, minimums).map { hint, minimum in
            max(CGFloat(min(hint.longestCell, 50)) * characterWidth - minimum, 0)
        }
        let wantTotal = wants.reduce(0, +)
        guard wantTotal > 0 else {
            return minimums.map { $0 + spare / CGFloat(count) }
        }
        return zip(minimums, wants).map { minimum, want in minimum + spare * want / wantTotal }
    }

    /// When the minimums don't all fit, narrow columns keep theirs and only the widest ones give way.
    private func fitted(_ minimums: [CGFloat], into available: CGFloat) -> [CGFloat] {
        var result = minimums
        var remaining = available
        let narrowestFirst = minimums.indices.sorted { minimums[$0] < minimums[$1] }
        for (position, index) in narrowestFirst.enumerated() {
            let share = remaining / CGFloat(minimums.count - position)
            result[index] = min(minimums[index], share)
            remaining -= result[index]
        }
        return result
    }
}

private extension View {
    func wrapping() -> some View {
        lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
