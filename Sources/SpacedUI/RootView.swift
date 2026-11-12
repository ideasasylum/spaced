import SpacedCore
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    let model: SessionModel
    let preferences: Preferences

    var body: some View {
        HStack(spacing: 0) {
            if preferences.sidebarVisible, !model.isEmpty {
                SidebarView(model: model)
                    .frame(width: preferences.sidebarWidth)
                SidebarDivider(preferences: preferences)
            }
            VStack(spacing: 0) {
                if model.isEmpty {
                    EmptyStateView()
                } else {
                    AsksBar(model: model)
                    if model.mode == .review {
                        ReviewView(model: model, scale: preferences.fontScale)
                    } else {
                        ReaderView(model: model, preferences: preferences)
                        ProgressFooter(progress: model.progress)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.page.ignoresSafeArea())
        .onDrop(of: [.fileURL, .plainText], isTargeted: nil, perform: drop)
    }

    private func drop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { model.onOpen?(.file(url)) }
            }
        } else {
            _ = provider.loadObject(ofClass: String.self) { text, _ in
                guard let text else { return }
                DispatchQueue.main.async { model.onOpen?(.text(text)) }
            }
        }
        return true
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("Paste, drop or open a markdown document")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("⌘V  ·  ⌘O")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A hairline progress bar with a time-left estimate, so the end always feels reachable.
struct ProgressFooter: View {
    let progress: ReadingProgress

    var body: some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.accentColor.opacity(0.7))
                    .frame(width: geometry.size.width * progress.fraction)
            }
            .frame(height: 2)
            .background(Color.primary.opacity(0.06))
        }
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(progress.fraction * 100)) percent, \(label)")
    }

    private var label: String {
        switch progress.minutesLeft {
        case 0: return "last one"
        case 1: return "about a minute left"
        default: return "about \(progress.minutesLeft) min left"
        }
    }
}

/// The reason for reading, pinned above the document.
struct AsksBar: View {
    @Bindable var model: SessionModel
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if model.askDraft != nil {
                TextField("Why are you reading this?  Return to skip", text: Binding(
                    get: { model.askDraft ?? "" }, set: { if model.askDraft != nil { model.askDraft = $0 } }
                ), axis: .vertical)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .focused($focused)
                    .onSubmit { model.commitAsks() }
                    .onAppear { focused = true }
            } else if !model.session.asks.isEmpty {
                Text(model.session.asks.joined(separator: "\n"))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                    .onTapGesture { model.editAsks() }
                    .help("Click to edit")
            }
        }
        .font(.system(size: 14, weight: .medium))
        .frame(maxWidth: readingWidth)
        .padding(.horizontal, 32)
        .padding(.vertical, model.askDraft != nil || !model.session.asks.isEmpty ? 10 : 0)
        .frame(maxWidth: .infinity)
    }
}

/// A hairline with a wider grab area; dragging it resizes the sidebar.
struct SidebarDivider: View {
    let preferences: Preferences

    var body: some View {
        Divider()
            .ignoresSafeArea()
            .overlay {
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .pointerStyle(.columnResize)
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { preferences.dragSidebar(by: $0.translation.width) }
                            .onEnded { _ in preferences.endSidebarDrag() }
                    )
                    .ignoresSafeArea()
            }
    }
}

struct SidebarView: View {
    let model: SessionModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(model.document.sections) { section in
                    let isCurrent = model.currentSection == section.id
                    let isDone = section.id < (model.currentSection ?? 0)
                    Button {
                        model.jump(toSection: section.id)
                    } label: {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color.heading(section.level).opacity(isDone ? 0.35 : 1))
                                .frame(width: 3, height: 12)
                            Text(section.title.isEmpty ? "Start" : section.title)
                                .lineLimit(1)
                                .fontWeight(isCurrent ? .semibold : .regular)
                                .foregroundStyle(isCurrent ? .primary : isDone ? .tertiary : .secondary)
                            Spacer(minLength: 0)
                            if isDone {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            if !model.notes(in: section.blocks).isEmpty {
                                Circle().fill(Color.accentColor).frame(width: 5, height: 5)
                            }
                        }
                        .padding(.leading, CGFloat(max(section.level - 1, 0)) * 12)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(isCurrent ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.system(size: 13))
            .padding(10)
        }
    }
}

/// Every note in document order, ready to copy or send back.
struct ReviewView: View {
    let model: SessionModel
    let scale: CGFloat

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Notes").font(.system(size: 26 * scale, weight: .bold))
                if model.session.notes.isEmpty {
                    Text("No notes yet. Press Return on anything you want to respond to.")
                        .foregroundStyle(.secondary)
                }
                ForEach(orderedNotes) { note in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(note.quote)
                            .lineLimit(4)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 14)
                            .overlay(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 1.5).fill(.tertiary).frame(width: 3)
                            }
                        HStack(alignment: .firstTextBaseline) {
                            Text(note.response).frame(maxWidth: .infinity, alignment: .leading)
                            Button("Delete", systemImage: "trash") { model.deleteNote(note.id) }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                        }
                    }
                    .font(.system(size: 16 * scale))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        model.mode = .reading
                        model.jump(toBlock: note.blockID)
                    }
                }
                HStack(spacing: 10) {
                    if model.isAwaited {
                        Button("Send Notes & Close") { model.onFinish?() }
                            .keyboardShortcut(.defaultAction)
                    }
                    Button(model.notesCopied ? "Copied" : "Copy as Markdown") { model.copyNotes() }
                    .disabled(model.session.notes.isEmpty)
                    Button("Back to Reading") { model.mode = .reading }
                }
                .controlSize(.large)
                .padding(.top, 6)
            }
            .frame(maxWidth: readingWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.vertical, 40)
        }
    }

    private var orderedNotes: [Note] {
        model.session.notes.sorted { ($0.blockID, $0.created) < ($1.blockID, $1.created) }
    }
}

/// The sidebar button and dimming slider that sit in the title bar.
struct TitlebarControls: View {
    @Bindable var preferences: Preferences

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.lefthalf.filled")
                .foregroundStyle(.secondary)
                .help("Dimming")
            Slider(value: $preferences.dim, in: 0...1)
                .controlSize(.mini)
                .frame(width: 80)
            Button("Toggle Sidebar", systemImage: "sidebar.left") { preferences.sidebarVisible.toggle() }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .padding(.trailing, 12)
        .frame(height: 28)
    }
}
