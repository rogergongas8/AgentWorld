import AgentWorldArt
import AgentWorldKit
import SwiftUI
import TerminalUI

/// Your running agents as characters on a strip of ground, each acting out
/// what it's doing right now: a flask while tests run, a branch for git, a
/// book while reading, a coffee when it's been idle a while. Click one to
/// jump to its terminal.
struct CrewStage: View {
    @EnvironmentObject private var model: AppModel
    let sessions: [TerminalSession]
    var scale: CGFloat = 2.5

    /// Two rows: past that the stage would push the workspaces off the column.
    static let shown = 6

    var body: some View {
        // The ones working or waiting on you first.
        let busy = sessions.filter { $0.status.tone == .busy || $0.status.tone == .needsYou }
        let ordered = busy + sessions.filter { !busy.contains($0) }
        let visible = Array(ordered.prefix(Self.shown))
        VStack(alignment: .leading, spacing: 0) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64 * scale / 2.5), spacing: 2, alignment: .bottom)], alignment: .leading, spacing: 8) {
                ForEach(visible) { session in
                    StageActor(session: session, scale: scale)
                        .onTapGesture { model.reveal(session) }
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 4)
            if sessions.count > visible.count {
                Text("+\(sessions.count - visible.count) more")
                    .font(.mono(10)).foregroundStyle(Palette.faint)
                    .padding(.horizontal, 12).padding(.bottom, 4)
            }
            Ground()
                .frame(height: 6)
        }
    }
}

/// One character with its prop, a bubble with what it's doing, and its name.
struct StageActor: View {
    @ObservedObject var session: TerminalSession
    var scale: CGFloat = 2.5
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 2) {
            TimelineView(.periodic(from: .now, by: 0.12)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let activity = session.activity
                let pose = Animator.pose(status: activity.status, flavor: activity.flavor,
                                         elapsed: context.date.timeIntervalSince(activity.since), t: t,
                                         seed: session.label.count, recentError: false)
                PixelImage(canvas: Self.canvas(session.provider.figure, pose: pose), scale: scale)
            }
            Text(session.label)
                .font(.mono(9.5, .semibold))
                .foregroundStyle(session.provider.swiftColor)
                .lineLimit(1)
            Text(caption)
                .font(.mono(8.5))
                .foregroundStyle(session.status.tone == .idle ? Palette.faint : session.status.tone.color)
                .lineLimit(1)
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Palette.hover : .clear))
        .onHover { hovering = $0 }
        .help("\(session.label) in \(session.folderName): \(session.status.text). Click to open its terminal.")
    }

    /// Short: the flavor or status in a word or two.
    private var caption: String {
        let activity = session.activity
        switch activity.flavor {
        case .tests: return "testing"
        case .git: return "git"
        case .install: return "installing"
        case .build: return "building"
        case .newFile: return "writing"
        case .web: return "on the web"
        case .mcp: return "using a tool"
        case .delegate: return "delegating"
        case .todo: return "planning"
        case .plan: return "planning"
        case .skill, .plain: break
        }
        switch activity.status {
        case .idle: return session.status.tone == .ended ? "ended" : "idle"
        case .waitingForUser: return "your turn"
        default: return activity.status.title.lowercased()
        }
    }

    /// The figure with room above for bubbles and to the right for props.
    static func canvas(_ figure: CharacterFigure, pose: Pose) -> PixelCanvas {
        let size = figure.size
        var pixels = PixelCanvas(width: size.width + 12, height: size.height + 10)
        CharacterPainter.draw(figure, on: &pixels, x: 1, ground: pixels.height - 1, pose: pose)
        return pixels
    }
}

/// A strip of pixel grass and earth.
struct Ground: View {
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color(rgb: RGB(hex: 0x3FA34D))).frame(height: 2)
            Rectangle().fill(Color(rgb: RGB(hex: 0x6B4F3A)))
        }
    }
}

extension AppModel {
    /// Shows a session's terminal: its workspace, its tab, keyboard in it.
    func reveal(_ session: TerminalSession) {
        guard let tab = tabs.first(where: { $0.sessions.contains { $0.id == session.id } }) else { return }
        selectedFolder = tab.folder
        selectedTabID = tab.id
        showsLauncher = false
        if tab.zoomedID != nil { tab.zoomedID = session.id }
        DispatchQueue.main.async { session.focus() }
    }
}
