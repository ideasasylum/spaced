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

struct BlockView: View {
    let block: Block
    /// Replaces the block's text, used to show a single sentence.
    var text: AttributedString?
    let scale: CGFloat
    var showsTableHeader = false

    var body: some View {
        let content = text ?? block.text
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
        case .code:
            ScrollView(.horizontal, showsIndicators: false) {
                Text(block.plainText)
                    .font(.system(size: 14 * scale, design: .monospaced))
                    .lineSpacing(3 * scale)
                    .fixedSize()
            }
            .padding(14 * scale)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        case .tableRow(let header, let cells, _):
            VStack(alignment: .leading, spacing: 6 * scale) {
                if showsTableHeader {
                    row(header).fontWeight(.semibold).foregroundStyle(.secondary)
                    Divider()
                }
                row(cells)
            }
        }
    }

    private func body(_ content: AttributedString) -> Text {
        Text(content).font(.system(size: 17 * scale))
    }

    private func row(_ cells: [AttributedString]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16 * scale) {
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

private extension View {
    func wrapping() -> some View {
        lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
