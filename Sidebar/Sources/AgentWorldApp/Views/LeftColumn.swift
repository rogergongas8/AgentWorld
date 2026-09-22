import AgentWorldArt
import AgentWorldKit
import AppKit
import SwiftUI

/// Workspaces with their terminals, and the live crew below.
struct LeftColumn: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    WorkspaceList()
                }
                .padding(12)
            }
            let sessions = model.allSessions
            // One terminal already has its character, big, on the right.
            if sessions.count > 1 {
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

    var body: some View {
        SectionTitle(title: "Workspaces", trailing: AnyView(
            Button(action: pickFolder) { Image(systemName: "plus") }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.muted)
                .help("Open a folder as a workspace")
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
        Button(action: pickFolder) {
            Label("Open a folder…", systemImage: "folder.badge.plus")
                .font(.mono(11.5))
                .foregroundStyle(Palette.muted)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Workspace"
        if panel.runModal() == .OK, let url = panel.url {
            model.addFolder(url.path)
        }
    }
}

struct FolderRow: View {
    @EnvironmentObject private var model: AppModel
    let folder: String
    @State private var hovering = false

    var body: some View {
        let selected = model.selectedFolder == folder
        let count = model.tabs(in: folder).reduce(0) { $0 + $1.sessions.count }
        Button {
            model.select(folder: folder)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: selected ? "folder.fill" : "folder")
                    .foregroundStyle(selected ? Palette.claude : Palette.muted)
                Text(URL(fileURLWithPath: folder).lastPathComponent)
                    .font(.mono(12.5, selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Palette.cream : Palette.text)
                    .lineLimit(1)
                Spacer()
                if hovering {
                    Button {
                        model.removeFolder(folder)
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.faint)
                    .help("Remove from the list (closes its terminals)")
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
        .help(folder)
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
