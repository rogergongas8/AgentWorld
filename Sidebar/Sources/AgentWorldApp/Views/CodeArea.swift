import AgentWorldArt
import AgentWorldKit
import SwiftTerm
import SwiftUI

/// Code mode: tabs of terminals for the selected workspace, the launcher
/// behind "+", and the tips & kit inspector on the right.
struct CodeArea: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            TabStrip(tabs: model.tabs(in: model.selectedFolder))
            Rectangle().fill(Palette.border).frame(height: 1)
            HStack(spacing: 0) {
                Group {
                    if model.showsLauncher || model.selectedTab == nil || model.selectedTab?.folder != model.selectedFolder {
                        LauncherView(folder: model.selectedFolder)
                    } else if let tab = model.selectedTab {
                        TabContent(tab: tab)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if model.showsInspector {
                    Rectangle().fill(Palette.border).frame(width: 1)
                    InspectorView(session: model.showsLauncher ? nil : model.selectedTab?.sessions.first, folder: model.selectedFolder)
                        .frame(width: 340)
                        .background(Palette.panel)
                }
            }
        }
    }
}

// MARK: - Tabs

struct TabStrip: View {
    @EnvironmentObject private var model: AppModel
    let tabs: [TerminalTab]

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill").foregroundStyle(Palette.claude)
                Text(URL(fileURLWithPath: model.selectedFolder).lastPathComponent).foregroundStyle(Palette.cream)
            }
            .font(.mono(12, .semibold))
            .padding(.trailing, 6)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(tabs) { tab in TabChip(tab: tab) }
                    Button {
                        model.showsLauncher = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(model.showsLauncher ? Palette.cream : Palette.muted)
                            .frame(width: 28, height: 26)
                            .background(RoundedRectangle(cornerRadius: 6).fill(model.showsLauncher ? Palette.selected : Palette.raised))
                    }
                    .buttonStyle(.plain)
                    .help("Open another agent or terminal here (⌘T)")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(Palette.panel)
    }
}

struct TabChip: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var tab: TerminalTab
    @State private var hovering = false

    var body: some View {
        let selected = model.selectedTabID == tab.id && !model.showsLauncher
        HStack(spacing: 7) {
            ForEach(tab.sessions) { session in TabStatusDot(session: session) }
            Text(tab.title)
                .font(.mono(11.5, selected ? .semibold : .regular))
                .foregroundStyle(selected ? Palette.cream : Palette.text)
                .lineLimit(1)
            Button {
                model.close(tab)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(hovering || selected ? Palette.muted : Palette.faint)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(hovering ? Palette.hover : .clear))
            }
            .buttonStyle(.plain)
            .help("Close (⌘W): ends this session")
        }
        .padding(.leading, 10)
        .padding(.trailing, 5)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Palette.selected : hovering ? Palette.hover : Palette.raised))
        .overlay(alignment: .bottom) {
            if selected { Rectangle().fill(tab.sessions.first?.provider.swiftColor ?? Palette.claude).frame(height: 2).padding(.horizontal, 6) }
        }
        .onHover { hovering = $0 }
        .onTapGesture {
            model.selectedTabID = tab.id
            model.showsLauncher = false
            DispatchQueue.main.async { tab.sessions.first?.focus() }
        }
    }
}

struct TabStatusDot: View {
    @ObservedObject var session: TerminalSession
    var body: some View { StatusDot(tone: session.status.tone).help(session.status.text) }
}

// MARK: - Terminals

/// One terminal, or up to six tiled, each with a small title bar.
struct TabContent: View {
    @ObservedObject var tab: TerminalTab

    var body: some View { TileGrid(tab: tab) }
}

struct SessionPane: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var session: TerminalSession
    let showsHeader: Bool

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                HStack(spacing: 8) {
                    FaceView(figure: session.provider.figure, scale: 1.4, busy: session.status.tone == .busy)
                        .frame(width: 14, height: 9)
                    Text(session.label).font(.mono(11, .semibold)).foregroundStyle(session.provider.swiftColor)
                    StatusDot(tone: session.status.tone)
                    Text(session.status.text).font(.mono(10)).foregroundStyle(Palette.faint).lineLimit(1)
                    Spacer()
                    Button { model.close(session) } label: {
                        Image(systemName: "xmark").font(.system(size: 8.5, weight: .bold)).foregroundStyle(Palette.faint)
                    }
                    .buttonStyle(.plain)
                    .help("Close this one")
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Palette.panel)
            }
            ZStack {
                Palette.terminalBackground
                TerminalHost(view: session.terminal)
                    .padding(.leading, 10)
                    .padding(.top, 6)
                if case .exited = session.health {
                    EndedOverlay(session: session)
                }
            }
        }
    }
}

/// Hosts the long-lived terminal view (created once per session).
struct TerminalHost: NSViewRepresentable {
    let view: LocalProcessTerminalView

    func makeNSView(context: Context) -> LocalProcessTerminalView { view }
    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}
}

struct EndedOverlay: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var session: TerminalSession

    var body: some View {
        VStack(spacing: 10) {
            Text("\(session.label) \(session.status.text)").font(.mono(13, .semibold)).foregroundStyle(Palette.cream)
            HStack(spacing: 10) {
                Button("Close") { model.close(session) }
                Button("Start again") {
                    model.close(session)
                    model.launch(session.profile, in: session.folder)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.raised))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.border))
    }
}
