import AgentWorldArt
import AgentWorldKit
import AppKit
import SwiftUI

/// One changed file's diff over the window: added lines green, removed red,
/// who touched it, and a way to open it or hand it to the agent.
struct DiffSheet: View {
    @EnvironmentObject private var model: AppModel
    let open: OpenChange
    @State private var lines: [DiffLine] = []
    @State private var loading = true

    var body: some View {
        let change = open.change
        let root = model.changes[open.folder]?.root ?? open.folder
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ChangeBadge(kind: change.kind)
                VStack(alignment: .leading, spacing: 2) {
                    Text(change.name).font(.mono(13, .semibold)).foregroundStyle(Palette.cream)
                    Text(change.folder.isEmpty ? "repository root" : change.folder).font(.mono(10.5)).foregroundStyle(Palette.muted)
                }
                LineCounts(change: change).padding(.leading, 6)
                touchedBy
                Spacer()
                Button { model.stepDiff(-1) } label: { Image(systemName: "chevron.up") }
                    .help("Previous file (↑ or k)")
                Button { model.stepDiff(1) } label: { Image(systemName: "chevron.down") }
                    .help("Next file (↓ or j)")
                Button { model.showOnMap(change, in: open.folder) } label: { Image(systemName: "point.3.connected.trianglepath.dotted") }
                    .help("Show it on the project map: what it uses and what uses it")
                Button("Open") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: root).appendingPathComponent(change.path))
                }
                .disabled(change.kind == .deleted)
                .help("Open in its default app")
                Button { model.openChange = nil } label: { Image(systemName: "xmark") }
                    .keyboardShortcut(.cancelAction)
                    .help("Close (esc)")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 16)
            .frame(height: 56)
            Rectangle().fill(Palette.border).frame(height: 1)
            if loading {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if lines.isEmpty {
                Text(change.kind == .deleted ? "Deleted." : "No text changes (a binary file, or only its mode changed).")
                    .font(.mono(11)).foregroundStyle(Palette.faint).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geometry in
                    ScrollView([.vertical, .horizontal]) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(lines) { line in DiffLineRow(line: line) }
                        }
                        .padding(.vertical, 8)
                        // Short diffs start at the top left, not floating in the middle.
                        .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
                    }
                }
            }
        }
        .frame(width: 880, height: 600)
        .background(Palette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.border))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
        .task(id: open.change) { await load(root: root) }
        .background {
            // j/k and the arrows step through the files, like the panel.
            Group {
                Button("") { model.stepDiff(1) }.keyboardShortcut(.downArrow, modifiers: [])
                Button("") { model.stepDiff(-1) }.keyboardShortcut(.upArrow, modifiers: [])
                Button("") { model.stepDiff(1) }.keyboardShortcut("j", modifiers: [])
                Button("") { model.stepDiff(-1) }.keyboardShortcut("k", modifiers: [])
            }
            .opacity(0)
        }
    }

    @ViewBuilder private var touchedBy: some View {
        let sessions = model.sessions(touching: open.change.path, in: open.folder)
        if !sessions.isEmpty {
            HStack(spacing: 5) {
                ForEach(sessions) { session in
                    FaceView(figure: session.provider.figure, scale: 1.6).frame(width: 16, height: 10)
                }
                Text("by " + sessions.map(\.label).joined(separator: ", "))
                    .font(.mono(10.5)).foregroundStyle(Palette.muted).lineLimit(1)
            }
            .padding(.leading, 8)
        }
    }

    private func load(root: String) async {
        loading = true
        let change = open.change
        let text = await Task.detached(priority: .userInitiated) { GitChanges.diff(change, root: root) }.value
        lines = DiffLine.parse(text)
        loading = false
    }
}

struct DiffLine: Identifiable {
    enum Kind { case header, hunk, added, removed, context }
    let id: Int
    let kind: Kind
    let text: String
    let oldNumber: Int?
    let newNumber: Int?

    /// Unified diff text into lines with their numbers on each side.
    static func parse(_ diff: String) -> [DiffLine] {
        var result: [DiffLine] = []
        var old = 0, new = 0
        var inHunk = false
        for (index, raw) in diff.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = String(raw)
            if line.hasPrefix("@@") {
                inHunk = true
                // @@ -12,5 +12,7 @@ context
                let numbers = line.split(separator: " ").dropFirst().prefix(2)
                old = numbers.first.flatMap { Int($0.dropFirst().split(separator: ",").first ?? "") } ?? 0
                new = numbers.dropFirst().first.flatMap { Int($0.dropFirst().split(separator: ",").first ?? "") } ?? 0
                result.append(DiffLine(id: index, kind: .hunk, text: line, oldNumber: nil, newNumber: nil))
            } else if !inHunk {
                continue   // diff --git, index, ---/+++: the header says it better
            } else if line.hasPrefix("+") {
                result.append(DiffLine(id: index, kind: .added, text: String(line.dropFirst()), oldNumber: nil, newNumber: new))
                new += 1
            } else if line.hasPrefix("-") {
                result.append(DiffLine(id: index, kind: .removed, text: String(line.dropFirst()), oldNumber: old, newNumber: nil))
                old += 1
            } else if line.hasPrefix("\\") {
                continue   // "\ No newline at end of file"
            } else if !(line.isEmpty && index == diff.split(separator: "\n", omittingEmptySubsequences: false).count - 1) {
                result.append(DiffLine(id: index, kind: .context, text: String(line.dropFirst()), oldNumber: old, newNumber: new))
                old += 1
                new += 1
            }
        }
        return result
    }
}

struct DiffLineRow: View {
    let line: DiffLine

    var body: some View {
        HStack(spacing: 0) {
            number(line.oldNumber)
            number(line.newNumber)
            Text(marker).foregroundStyle(color).frame(width: 18)
            Text(line.text.isEmpty ? " " : line.text)
                .foregroundStyle(line.kind == .hunk ? Palette.mcp : line.kind == .context ? Palette.text : color)
                .fixedSize()
            Spacer(minLength: 0)
        }
        .font(.mono(11.5))
        .padding(.trailing, 16)
        .frame(minHeight: 17)
        .padding(.top, line.kind == .hunk ? 8 : 0)
        .background(background)
    }

    private func number(_ value: Int?) -> some View {
        Text(value.map(String.init) ?? "")
            .foregroundStyle(Palette.faint)
            .frame(width: 44, alignment: .trailing)
            .padding(.trailing, 6)
    }

    private var marker: String {
        switch line.kind {
        case .added: "+"
        case .removed: "−"
        default: ""
        }
    }

    private var color: Color {
        switch line.kind {
        case .added: Palette.live
        case .removed: Palette.error
        case .hunk: Palette.mcp
        default: Palette.text
        }
    }

    private var background: Color {
        switch line.kind {
        case .added: Palette.live.opacity(0.10)
        case .removed: Palette.error.opacity(0.10)
        default: .clear
        }
    }
}

/// "M", "A", "D"… in the file's status color.
struct ChangeBadge: View {
    let kind: FileChange.Kind

    var body: some View {
        Text(letter)
            .font(.mono(11, .bold))
            .foregroundStyle(color)
            .frame(width: 22, height: 22)
            .background(RoundedRectangle(cornerRadius: 5).fill(color.opacity(0.14)))
            .help(kind.rawValue.capitalized)
    }

    private var letter: String {
        switch kind {
        case .modified: "M"
        case .added: "A"
        case .deleted: "D"
        case .renamed: "R"
        case .untracked: "N"
        case .conflicted: "!"
        }
    }

    var color: Color {
        switch kind {
        case .modified, .renamed: Palette.warning
        case .added, .untracked: Palette.live
        case .deleted, .conflicted: Palette.error
        }
    }
}

/// "+12 −3".
struct LineCounts: View {
    let change: FileChange

    var body: some View {
        HStack(spacing: 5) {
            if let added = change.added, added > 0 { Text("+\(added)").foregroundStyle(Palette.live) }
            if let removed = change.removed, removed > 0 { Text("−\(removed)").foregroundStyle(Palette.error) }
            if change.added == nil { Text("binary").foregroundStyle(Palette.faint) }
        }
        .font(.mono(10.5, .semibold))
    }
}

/// Commit the workspace's changes: your message, or the pane's agent writes
/// one in the repository's style.
struct CommitSheet: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool
    @State private var message = ""
    @State private var push = UserDefaults.standard.bool(forKey: "commitPushes")
    @State private var working = false
    @State private var problem: String?
    @State private var branch: String?
    @FocusState private var focused: Bool

    var body: some View {
        let folder = model.selectedFolder
        let changes = model.changes[folder]
        let agent = model.panelSession?.provider.isAgent == true ? model.panelSession : nil
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "smallcircle.filled.circle").foregroundStyle(Palette.warning)
                Text("Commit \(changes?.files.count ?? 0) files").font(.mono(15, .bold)).foregroundStyle(Palette.cream)
                if let branch {
                    Text("to \(branch)").font(.mono(12)).foregroundStyle(Palette.muted)
                }
                Spacer()
                if let changes {
                    Text("+\(changes.added)").foregroundStyle(Palette.live).font(.mono(11, .semibold))
                    Text("−\(changes.removed)").foregroundStyle(Palette.error).font(.mono(11, .semibold))
                }
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $message)
                    .font(.mono(12))
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .padding(6)
                if message.isEmpty {
                    Text("What changed and why. First line: a short summary.")
                        .font(.mono(12)).foregroundStyle(Palette.faint).padding(.horizontal, 11).padding(.vertical, 6)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 120)
            .background(RoundedRectangle(cornerRadius: 8).fill(Palette.background))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(focused ? Palette.claude.opacity(0.6) : Palette.border))
            Toggle("Push after committing", isOn: $push)
                .font(.mono(11.5))
                .onChange(of: push) { UserDefaults.standard.set($0, forKey: "commitPushes") }
            if let problem {
                Text(problem).font(.mono(10.5)).foregroundStyle(Palette.error).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                if let agent {
                    Button {
                        isPresented = false
                        agent.type("Commit the uncommitted changes: write a clear message in this repository's style (see git log) that says what changed and why, then commit" + (push ? " and push." : "."))
                    } label: {
                        Label("Let \(agent.provider.shortName) write it", systemImage: "wand.and.stars")
                    }
                    .help("Types the request into \(agent.label); press return there to send it")
                }
                Spacer()
                if working { ProgressView().controlSize(.small) }
                Button("Cancel") { isPresented = false }.keyboardShortcut(.cancelAction)
                Button(push ? "Commit & Push" : "Commit") { commit(root: changes?.root ?? folder) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(working || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560)
        .background(Palette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.border))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
        .onAppear {
            focused = true
            let root = changes?.root ?? folder
            Task.detached { let name = GitChanges.branch(root: root); await MainActor.run { branch = name } }
        }
        .onExitCommand { isPresented = false }
    }

    private func commit(root: String) {
        working = true
        problem = nil
        let text = message
        let pushes = push
        let folder = model.selectedFolder
        Task.detached {
            let failure = GitChanges.commit(root: root, message: text, push: pushes)
            await MainActor.run {
                working = false
                if let failure {
                    problem = failure
                } else {
                    isPresented = false
                }
                model.refreshChanges(folder)
                model.refreshGit()
            }
        }
    }
}
