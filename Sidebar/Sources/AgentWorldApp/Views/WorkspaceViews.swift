import AgentWorldArt
import AgentWorldKit
import AppKit
import SwiftUI

/// "Pick up where you left off": last time's panes in this workspace, one
/// click (or ↩ on the card) to reopen them, conversations resumed by each CLI.
struct ResumeCard: View {
    @EnvironmentObject private var model: AppModel
    let folder: String
    let panes: [SavedPane]
    @State private var hovering = false

    var body: some View {
        Button {
            model.resume(in: folder)
        } label: {
            HStack(spacing: 14) {
                HStack(spacing: 4) {
                    ForEach(Array(panes.prefix(4).enumerated()), id: \.offset) { index, pane in
                        FaceView(figure: figure(pane), scale: 2.6, waving: hovering, seed: index).frame(width: 26, height: 16)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Pick up where you left off").font(.mono(13, .semibold)).foregroundStyle(Palette.cream)
                    Text(summary).font(.mono(10.5)).foregroundStyle(Palette.muted).lineLimit(1)
                }
                Spacer()
                Label("Resume", systemImage: "arrow.uturn.forward").font(.mono(11, .semibold)).foregroundStyle(Palette.live)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(hovering ? Palette.hover : Palette.raised))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.live.opacity(hovering ? 0.7 : 0.35)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Reopens them tiled in one tab. CLIs that can (Claude Code, Codex) continue the same conversation.")
    }

    private func figure(_ pane: SavedPane) -> CharacterFigure {
        model.profiles.first { $0.name == pane.profile }?.provider.figure ?? Provider.terminal.figure
    }

    private var summary: String {
        let names = panes.map { pane -> String in
            let name = pane.agentName ?? model.profiles.first { $0.name == pane.profile }.map { $0.isCustom ? $0.name : $0.provider.shortName } ?? pane.profile
            return pane.resumeID == nil ? name : name + " (conversation)"
        }
        return "Last time: " + names.joined(separator: ", ")
    }
}

/// No workspaces yet: what a workspace is, ways to add one, and folders
/// your CLIs have already worked in.
struct WelcomeWorkspaces: View {
    @EnvironmentObject private var model: AppModel
    @State private var suggestions: [CLIHistory.Folder] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "Your workspaces", color: Palette.claude)
            Text("A workspace is a project folder. Its CLIs, tabs and conversations stay with it, and come back next time you open the app.")
                .font(.mono(11))
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button { model.chooseFolder() } label: { Label("Add a folder…", systemImage: "folder.badge.plus") }
                    .keyboardShortcut("o")
                Button { model.showsNewProject = true } label: { Label("New project or clone…", systemImage: "plus.square.on.square") }
            }
            .controlSize(.large)
            if !suggestions.isEmpty {
                Text("Where your CLIs have worked before")
                    .font(.mono(10.5, .semibold))
                    .foregroundStyle(Palette.cream)
                    .padding(.top, 6)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 320), spacing: 10)], spacing: 10) {
                    ForEach(suggestions) { folder in
                        SuggestionCard(folder: folder)
                    }
                }
            }
        }
        .task {
            let found = await Task.detached(priority: .utility) { CLIHistory.recentFolders() }.value
            suggestions = found.filter { !model.folders.contains($0.path) }
        }
    }
}

struct SuggestionCard: View {
    @EnvironmentObject private var model: AppModel
    let folder: CLIHistory.Folder
    @State private var hovering = false

    var body: some View {
        Button {
            model.addFolder(folder.path)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "folder").foregroundStyle(Palette.claude)
                VStack(alignment: .leading, spacing: 2) {
                    Text(URL(fileURLWithPath: folder.path).lastPathComponent).font(.mono(12, .semibold)).foregroundStyle(Palette.cream)
                    Text(folder.clis.joined(separator: " · ")).font(.mono(9.5)).foregroundStyle(Palette.faint).lineLimit(1)
                }
                Spacer()
                Image(systemName: "plus").foregroundStyle(hovering ? Palette.live : Palette.faint)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? Palette.hover : Palette.raised))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help((folder.path as NSString).abbreviatingWithTildeInPath + "\nAdd as a workspace")
    }
}

/// ⌘⇧N: a new folder (with git init) or a clone, added as a workspace.
struct NewProjectSheet: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool
    @State private var cloning = false
    @State private var name = ""
    @State private var cloneURL = ""
    @State private var parent = NewProjectSheet.defaultParent
    @State private var gitInit = true
    @State private var working = false
    @State private var problem: String?
    @FocusState private var firstField: Bool

    static var defaultParent: String {
        let developer = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Developer").path
        return FileManager.default.fileExists(atPath: developer) ? developer : FileManager.default.homeDirectoryForCurrentUser.path
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New workspace").font(.mono(15, .bold)).foregroundStyle(Palette.cream)
            Picker("", selection: $cloning) {
                Text("New project").tag(false)
                Text("Clone a repository").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if cloning {
                field("Repository URL") {
                    TextField("https://github.com/you/project.git", text: $cloneURL).focused($firstField)
                }
                field("Folder name (optional)") { TextField("from the URL", text: $name) }
            } else {
                field("Name") { TextField("my-project", text: $name).focused($firstField) }
                Toggle("Start a git repository", isOn: $gitInit).font(.mono(11))
            }
            field("In") {
                HStack {
                    Text((parent as NSString).abbreviatingWithTildeInPath).font(.mono(11)).foregroundStyle(Palette.text).lineLimit(1)
                    Spacer()
                    Button("Change…", action: pickParent)
                }
            }
            if let problem {
                Text(problem).font(.mono(10.5)).foregroundStyle(Palette.error).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if working { ProgressView().controlSize(.small); Text(cloning ? "Cloning…" : "Creating…").font(.mono(10.5)).foregroundStyle(Palette.muted) }
                Spacer()
                Button("Cancel") { isPresented = false }.keyboardShortcut(.cancelAction)
                Button(cloning ? "Clone" : "Create", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(working || (cloning ? cloneURL.isEmpty : name.isEmpty))
            }
        }
        .padding(22)
        .frame(width: 480)
        .background(Palette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.border))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
        .onAppear { DispatchQueue.main.async { firstField = true } }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.mono(10.5, .semibold)).foregroundStyle(Palette.muted)
            content().textFieldStyle(.roundedBorder).font(.mono(12))
        }
    }

    private func pickParent() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = URL(fileURLWithPath: parent)
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { parent = url.path }
    }

    private func create() {
        working = true
        problem = nil
        Task {
            let failure = await model.createProject(name: name, in: parent, cloneURL: cloning ? cloneURL : nil, gitInit: gitInit)
            working = false
            if let failure { problem = failure } else { isPresented = false }
        }
    }
}
