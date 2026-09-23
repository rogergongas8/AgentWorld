import AgentWorldArt
import AgentWorldKit
import SwiftUI

/// A tab's terminals: a slim toolbar (layout, add a pane, send to all) over
/// up to six panes, each with a title bar you can zoom or close from.
struct TileGrid: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var tab: TerminalTab

    var body: some View {
        VStack(spacing: 0) {
            panes
                .background(Palette.border)
            if tab.sessions.count > 1 {
                Rectangle().fill(Palette.border).frame(height: 1)
                BroadcastBar(tab: tab)
            }
        }
    }

    @ViewBuilder private var panes: some View {
        let sessions = tab.sessions
        if let zoomed = sessions.first(where: { $0.id == tab.zoomedID }) {
            TilePane(tab: tab, session: zoomed, showsHeader: sessions.count > 1)
        } else if sessions.count == 1, let only = sessions.first {
            TilePane(tab: tab, session: only, showsHeader: false)
        } else if tab.layout == .main {
            let lead = model.focusedSession.flatMap { focused in sessions.first { $0.id == focused.id } } ?? sessions[0]
            let rest = sessions.filter { $0.id != lead.id }
            GeometryReader { geometry in
                HStack(spacing: 1) {
                    TilePane(tab: tab, session: lead, showsHeader: true)
                        .frame(width: geometry.size.width * 0.62)
                    VStack(spacing: 1) {
                        ForEach(rest) { session in TilePane(tab: tab, session: session, showsHeader: true) }
                    }
                }
            }
        } else {
            VStack(spacing: 1) {
                ForEach(Array(tab.layout.rows(for: sessions.count).enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 1) {
                        ForEach(row, id: \.self) { index in
                            TilePane(tab: tab, session: sessions[index], showsHeader: true)
                        }
                    }
                }
            }
        }
    }
}

/// The composer under the panes: one prompt, typed into every one of them.
struct BroadcastBar: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var tab: TerminalTab
    @State private var message = ""
    @State private var submit = true
    @FocusState private var typing: Bool

    var body: some View {
        let running = tab.sessions.filter { $0.health == .running }
        HStack(spacing: 10) {
            HStack(spacing: -3) {
                ForEach(running.prefix(AppModel.maxPanes)) { session in
                    FaceView(figure: session.provider.figure, scale: 1.8, busy: session.status.tone == .busy, seed: session.label.count)
                        .frame(width: 20, height: 12)
                }
            }
            TextField("Ask all \(running.count) at once…", text: $message, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.mono(12))
                .foregroundStyle(Palette.cream)
                .lineLimit(1...4)
                .focused($typing)
                .onSubmit(send)
            Toggle(isOn: $submit) { Text("send ⏎").font(.mono(10)) }
                .toggleStyle(.checkbox)
                .foregroundStyle(Palette.muted)
                .help("On: each pane gets the prompt and runs it. Off: it's only typed, so you can tweak it pane by pane.")
            Button(action: send) {
                Label("All \(running.count)", systemImage: "dot.radiowaves.left.and.right").font(.mono(11, .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.claude)
            .controlSize(.small)
            .keyboardShortcut(.return, modifiers: [.command, .shift])
            .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || running.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Palette.panel)
        .overlay(alignment: .top) {
            Rectangle().fill(typing ? Palette.claude.opacity(0.8) : .clear).frame(height: 1)
        }
        .help("Broadcast: the same prompt to every agent in this tab (⇧⌘⏎). Compare how each one does it.")
    }

    private func send() {
        model.broadcast(message, to: tab, submit: submit)
        message = ""
    }
}

struct LayoutPicker: View {
    @ObservedObject var tab: TerminalTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(TileLayout.allCases) { layout in
                let selected = tab.layout == layout && tab.zoomedID == nil
                Button {
                    tab.layout = layout
                    tab.zoomedID = nil
                } label: {
                    Image(systemName: layout.symbol)
                        .font(.system(size: 11.5))
                        .foregroundStyle(selected ? Palette.cream : Palette.muted)
                        .frame(width: 26, height: 22)
                        .background(RoundedRectangle(cornerRadius: 5).fill(selected ? Palette.selected : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(layout.title)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(Palette.background))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Palette.border))
    }
}

struct AddPaneMenu: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var tab: TerminalTab

    var body: some View {
        let full = tab.sessions.count >= AppModel.maxPanes
        Menu {
            ForEach(model.profiles.filter { model.executable(for: $0) != nil }, id: \.id) { profile in
                Button(profile.isCustom ? profile.name : profile.provider.name) { model.addPane(profile, to: tab) }
            }
        } label: {
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: 13))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .foregroundStyle(Palette.muted)
        .disabled(full)
        .help(full ? "\(AppModel.maxPanes) panes at most" : "Split: open another CLI in this tab, next to these (⌘D)")
    }
}

// MARK: - Pane

struct TilePane: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var tab: TerminalTab
    @ObservedObject var session: TerminalSession
    let showsHeader: Bool

    var body: some View {
        let focused = showsHeader && session.hasFocus
        let accent = session.provider.swiftColor
        VStack(spacing: 0) {
            if showsHeader {
                HStack(spacing: 8) {
                    FaceView(figure: session.provider.figure, scale: 1.6, busy: session.status.tone == .busy)
                        .frame(width: 16, height: 10)
                    Text(session.label).font(.mono(11, .semibold)).foregroundStyle(focused ? accent : Palette.text)
                        .lineLimit(1).layoutPriority(1)
                    StatusDot(tone: session.status.tone)
                    Text(session.status.text)
                        .font(.mono(10))
                        .foregroundStyle(session.status.tone == .idle ? Palette.faint : session.status.tone.color)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    PaneButton(symbol: tab.zoomedID == session.id ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                               help: tab.zoomedID == session.id ? "Back to all panes (⇧⌘⏎)" : "Zoom this pane (⇧⌘⏎)") {
                        tab.zoomedID = tab.zoomedID == session.id ? nil : session.id
                        DispatchQueue.main.async { session.focus() }
                    }
                    PaneButton(symbol: "xmark", help: "Close this pane: ends its session") { model.requestClose(session) }
                }
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(focused ? Palette.raised : Palette.panel)
                .overlay(alignment: .top) {
                    Rectangle().fill(focused ? accent : .clear).frame(height: 2)
                }
                .contentShape(Rectangle())
                .onTapGesture { session.focus() }
                .onTapGesture(count: 2) {
                    tab.zoomedID = tab.zoomedID == session.id ? nil : session.id
                }
            }
            ZStack {
                Palette.terminalBackground
                TerminalHost(view: session.terminal)
                    .padding(.leading, 8)
                    .padding(.top, 4)
                if case .exited = session.health {
                    EndedOverlay(session: session)
                }
            }
        }
        .background(Palette.terminalBackground)
    }
}

struct PaneButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(hovering ? Palette.cream : Palette.faint)
                .frame(width: 18, height: 18)
                .background(RoundedRectangle(cornerRadius: 4).fill(hovering ? Palette.hover : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
