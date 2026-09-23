import AgentWorldArt
import AgentWorldKit
import AppKit
import SwiftUI

/// Workspaces with their terminals, and the live crew below.
struct LeftColumn: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var preferences = Preferences.shared

    var body: some View {
        VStack(spacing: 0) {
            // The traffic lights sit here; the rest of the strip moves the window.
            HStack(spacing: 0) {
                WindowDragArea().frame(maxWidth: .infinity, maxHeight: .infinity)
                ChromeButton(symbol: "gearshape", help: "Settings (⌘,)") { model.openSettings() }
                SidebarToggle()
            }
            .padding(.horizontal, 8)
            .frame(height: 44)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    WorkspaceList()
                }
                .padding(12)
            }
            let sessions = model.allSessions
            // One terminal already has its character, big, on the right.
            if sessions.count > 1, preferences.showsLiveCrew {
                VStack(alignment: .leading, spacing: 6) {
                    SectionTitle(title: "Crew · live", color: Palette.live)
                        .padding(.horizontal, 12)
                    CrewStage(sessions: sessions)
                }
                .padding(.top, 10)
                .background(Palette.background.opacity(0.6))
                .overlay(alignment: .top) { Rectangle().fill(Palette.border).frame(height: 1) }
            }
        }
    }
}

// MARK: - Workspaces

struct WorkspaceList: View {
    @EnvironmentObject private var model: AppModel
    @State private var dropTargeted = false

    var body: some View {
        SectionTitle(title: "Workspaces", trailing: AnyView(
            Menu {
                Button("Add a Folder…  ⌘O") { model.chooseFolder() }
                Button("New Project or Clone…  ⌘⇧N") { model.showsNewProject = true }
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(Palette.muted)
            .help("Add a workspace: a folder, a new project or a clone")
        ))
        VStack(alignment: .leading, spacing: 4) {
            ForEach(model.folders, id: \.self) { folder in
                FolderRow(folder: folder)
                ForEach(model.tabs(in: folder)) { tab in
                    ForEach(tab.sessions) { session in
                        SessionRow(session: session, tab: tab)
                    }
                }
            }
        }
        if model.folders.isEmpty {
            Text("No workspaces yet. Add a project folder — or drop one here.")
                .font(.mono(10.5))
                .foregroundStyle(Palette.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
        Button(action: model.chooseFolder) {
            Label("Add a folder…", systemImage: "folder.badge.plus")
                .font(.mono(11.5))
                .foregroundStyle(dropTargeted ? Palette.live : Palette.muted)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
        .help("Or drag project folders from Finder onto this column")
    }
}

/// Folders dropped on the left column become workspaces.
struct FolderDrop: ViewModifier {
    @EnvironmentObject private var model: AppModel
    @State private var targeted = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if targeted {
                    RoundedRectangle(cornerRadius: 8).stroke(Palette.live, style: StrokeStyle(lineWidth: 2, dash: [6, 4])).padding(6)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        var isDirectory: ObjCBool = false
                        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return }
                        Task { @MainActor in model.addFolder(url.path) }
                    }
                }
                return true
            }
    }
}

struct FolderRow: View {
    @EnvironmentObject private var model: AppModel
    let folder: String
    @State private var hovering = false
    @State private var renaming = false
    @State private var newName = ""

    var body: some View {
        let selected = model.selectedFolder == folder
        let count = model.tabs(in: folder).reduce(0) { $0 + $1.sessions.count }
        let git = model.git[folder]
        let pinned = model.workspaceInfo[folder]?.pinned == true
        Button {
            model.select(folder: folder)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: selected ? "folder.fill" : "folder")
                    .foregroundStyle(selected ? Palette.claude : Palette.muted)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(model.workspaceName(folder))
                            .font(.mono(12.5, selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Palette.cream : Palette.text)
                            .lineLimit(1)
                        if pinned { Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(Palette.faint) }
                    }
                    if let branch = git?.branch {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.branch").font(.system(size: 8))
                            Text(branch).lineLimit(1)
                            if let changes = model.changes[folder], !changes.files.isEmpty {
                                // What's uncommitted, once the Changes reader has looked.
                                Text("· \(changes.files.count) changed").foregroundStyle(Palette.warning.opacity(0.85))
                            } else if git?.dirty == true {
                                Circle().fill(Palette.warning).frame(width: 5, height: 5)
                            }
                        }
                        .font(.mono(9.5))
                        .foregroundStyle(Palette.faint)
                    }
                }
                Spacer()
                if hovering {
                    Button {
                        model.removeFolder(folder)
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.faint)
                    .help("Remove from the list (closes its terminals; the folder stays on disk)")
                } else if count > 0 {
                    Text("\(count)").font(.mono(10.5)).foregroundStyle(Palette.muted)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Palette.selected : hovering ? Palette.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(folder + (git?.dirty == true ? "\nHas uncommitted changes" : ""))
        .contextMenu {
            Button("Rename…") {
                newName = model.workspaceName(folder)
                renaming = true
            }
            Button(pinned ? "Unpin" : "Pin to Top") { model.togglePin(folder) }
            Divider()
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder)]) }
            if let editor = Editor.installed {
                Button("Open in \(editor.name)") { editor.open(folder) }
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(folder, forType: .string)
            }
            Divider()
            Button("Remove from AgentWorld") { model.removeFolder(folder) }
        }
        .alert("Rename workspace", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Rename") { model.rename(workspace: folder, to: newName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only in AgentWorld; the folder keeps its name. Leave it empty to use the folder's name.")
        }
    }
}

/// A code editor to open a workspace in, if one is installed.
struct Editor {
    let name: String
    let bundleID: String

    static let known = [
        Editor(name: "Cursor", bundleID: "com.todesktop.230313mzl4w4u92"),
        Editor(name: "VS Code", bundleID: "com.microsoft.VSCode"),
        Editor(name: "Zed", bundleID: "dev.zed.Zed"),
        Editor(name: "Xcode", bundleID: "com.apple.dt.Xcode"),
    ]

    static var installed: Editor? {
        known.first { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
    }

    func open(_ folder: String) {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.open([URL(fileURLWithPath: folder)], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
}

struct SessionRow: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var session: TerminalSession
    let tab: TerminalTab
    @State private var hovering = false

    var body: some View {
        let selected = model.selectedTabID == tab.id && !model.showsLauncher
        Button {
            model.selectedFolder = tab.folder
            model.selectedTabID = tab.id
            model.showsLauncher = false
            DispatchQueue.main.async { session.focus() }
        } label: {
            HStack(spacing: 8) {
                FaceView(figure: session.provider.figure, scale: 1.6, busy: session.status.tone == .busy)
                    .frame(width: 16, height: 10)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.label)
                        .font(.mono(11.5, .medium))
                        .foregroundStyle(selected ? Palette.cream : session.provider.swiftColor)
                    HStack(spacing: 5) {
                        StatusDot(tone: session.status.tone)
                        Text(session.status.text)
                            .font(.mono(10))
                            .foregroundStyle(session.status.tone == .idle ? Palette.faint : session.status.tone.color)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 22)
            .padding(.trailing, 6)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Palette.selected : hovering ? Palette.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("\(session.label) in \(session.folderName): \(session.status.text)")
    }
}
