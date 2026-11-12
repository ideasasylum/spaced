import SpacedCore
import SwiftUI

let readingWidth: CGFloat = 680

/// The dimmed document with the porthole floating over it, or the plain document in whole-document mode.
struct ReaderView: View {
    let model: SessionModel
    let preferences: Preferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var scale: CGFloat { preferences.fontScale }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                backdrop(height: geometry.size.height)
                    .blur(radius: model.mode == .reading && preferences.blursBackground ? 5 : 0)
                if model.mode == .reading {
                    Color.page.opacity(preferences.dim).allowsHitTesting(false)
                    PortholeView(model: model, scale: scale)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 24)
                        .frame(maxHeight: geometry.size.height)
                }
                if model.parkDraft != nil {
                    ParkField(model: model)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 18)
                }
            }
        }
    }

    private func backdrop(height: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12 * scale) {
                    ForEach(model.document.blocks) { block in
                        let isCurrent = model.mode == .whole && model.currentBlocks.contains(block.id)
                        BlockView(block: block, scale: scale, showsTableHeader: block.isFirstTableRow)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 10)
                            .background(isCurrent ? Color.accentColor.opacity(0.12) : .clear,
                                        in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                            .onTapGesture { model.jump(toBlock: block.id) }
                            .frame(maxWidth: block.isTableRow ? .infinity : readingWidth + 20)
                            .id(block.id)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 32)
                .padding(.vertical, height / 2)
            }
            .scrollDisabled(model.mode == .reading)
            .allowsHitTesting(model.mode == .whole)
            .onAppear { proxy.scrollTo(scrollTarget, anchor: .center) }
            .onChange(of: model.currentBlocks) {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    proxy.scrollTo(scrollTarget, anchor: .center)
                }
            }
            .onChange(of: model.mode) {
                proxy.scrollTo(scrollTarget, anchor: .center)
            }
        }
    }

    /// The middle block of the current unit, so the porthole sits over the text it is showing.
    private var scrollTarget: Int {
        let blocks = model.currentBlocks
        return model.mode == .whole ? blocks.lowerBound : (blocks.lowerBound + blocks.upperBound) / 2
    }

}

/// The bordered card showing the current sentence, block or section, with its notes underneath.
struct PortholeView: View {
    let model: SessionModel
    let scale: CGFloat

    var body: some View {
        VStack(spacing: 14) {
            ViewThatFits(in: .vertical) {
                card
                ScrollView { card }
            }
            .background(Color.page, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.22), lineWidth: 1))
            .shadow(color: .black.opacity(0.06), radius: 14, y: 4)

            if model.noteDraft != nil {
                NoteEditor(model: model, scale: scale)
            } else {
                ForEach(model.notes(in: model.currentBlocks)) { note in
                    Text(note.response)
                        .font(.system(size: 14 * scale))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1.5).fill(Color.accentColor.opacity(0.6)).frame(width: 3)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color.page, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .frame(maxWidth: showsTable ? .infinity : readingWidth + 72)
    }

    /// Tables get the full window width; prose stays at a comfortable reading width.
    private var showsTable: Bool {
        model.document.blocks[model.currentBlocks].contains(where: \.isTableRow)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12 * scale) {
            switch model.unit {
            case .sentence(let index, let sentence):
                let block = model.document.blocks[index]
                let offset = block.sentences.count > 1 ? block.sentences[sentence].lowerBound : 0
                let spoken = model.spokenRange(in: index).map { ($0.lowerBound - offset)..<($0.upperBound - offset) }
                BlockView(block: block, text: block.sentenceText(sentence), spoken: spoken, scale: scale,
                          showsTableHeader: true)
            case .block(let index):
                BlockView(block: model.document.blocks[index], spoken: model.spokenRange(in: index), scale: scale,
                          showsTableHeader: true)
            case .section(let index):
                ForEach(model.document.blocks[model.document.sections[index].blocks]) { block in
                    BlockView(block: block, spoken: model.spokenRange(in: block.id), scale: scale,
                              showsTableHeader: block.isFirstTableRow)
                }
            case nil:
                EmptyView()
            }
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}

private struct NoteEditor: View {
    @Bindable var model: SessionModel
    let scale: CGFloat
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            TextEditor(text: Binding(get: { model.noteDraft ?? "" }, set: { if model.noteDraft != nil { model.noteDraft = $0 } }))
                .font(.system(size: 15 * scale))
                .scrollContentBackground(.hidden)
                .focused($focused)
                .frame(minHeight: 64, maxHeight: 160)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .background(Color.page, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1))
            Text("⌘↩ save  ·  esc cancel")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .onAppear { focused = true }
    }
}

/// A one-line field for getting an unrelated thought out of your head without leaving the page.
private struct ParkField: View {
    @Bindable var model: SessionModel
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down").foregroundStyle(.secondary)
            TextField("Park a thought for later.  Return to save", text: Binding(
                get: { model.parkDraft ?? "" }, set: { if model.parkDraft != nil { model.parkDraft = $0 } }
            ))
            .textFieldStyle(.plain)
            .focused($focused)
            .onSubmit { model.commitParking() }
        }
        .font(.system(size: 14))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 460)
        .background(Color.page, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.22), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 3)
        .onAppear { focused = true }
    }
}
