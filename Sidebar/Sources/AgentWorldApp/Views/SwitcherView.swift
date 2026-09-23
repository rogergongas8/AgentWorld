import AgentWorldArt
import AgentWorldKit
import SwiftUI

/// ⌃Tab: every open terminal as a card, the highlighted one where you'll land.
struct SwitcherView: View {
    @EnvironmentObject private var model: AppModel
    let state: Switcher

    var body: some View {
        let sessions = state.sessions.compactMap { id in model.allSessions.first { $0.id == id } }
        VStack(spacing: 14) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(150), spacing: 12), count: min(max(sessions.count, 1), 5)), spacing: 12) {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                    SwitcherCard(session: session, number: index + 1, selected: index == state.index)
                        .onTapGesture {
                            model.switcher?.index = index
                            model.commitSwitcher()
                        }
                }
            }
            HStack(spacing: 16) {
                hint(state.holdingControl ? "⌃ held" : "⌃Tab", state.holdingControl ? "tab to move · let go to switch" : "move")
                hint("← →", "move")
                hint("1-9", "jump")
                hint("↩", "go")
                hint("esc", "cancel")
            }
        }
        .padding(18)
        .fixedSize()
        .background(RoundedRectangle(cornerRadius: 16).fill(Palette.panel.opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.border))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key).font(.mono(10.5, .semibold)).foregroundStyle(Palette.cream)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(Palette.raised))
            Text(label).font(.mono(10.5)).foregroundStyle(Palette.muted)
        }
    }
}

struct SwitcherCard: View {
    @ObservedObject var session: TerminalSession
    let number: Int
    let selected: Bool

    var body: some View {
        VStack(spacing: 8) {
            FaceView(figure: session.provider.figure, scale: 5, waving: selected, busy: session.status.tone == .busy)
                .frame(width: 60, height: 40)
            Text(session.label).font(.mono(12.5, .semibold)).foregroundStyle(selected ? Palette.cream : Palette.text).lineLimit(1)
            Text(session.folderName).font(.mono(10.5)).foregroundStyle(Palette.muted).lineLimit(1)
            HStack(spacing: 5) {
                StatusDot(tone: session.status.tone)
                Text(session.status.text).font(.mono(10)).foregroundStyle(Palette.faint).lineLimit(1)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .frame(width: 150, height: 150)
        .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Palette.selected : Palette.raised))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? session.provider.swiftColor : Palette.border, lineWidth: selected ? 2 : 1))
        .overlay(alignment: .topLeading) {
            if number <= 9 {
                Text("\(number)").font(.mono(10, .semibold)).foregroundStyle(Palette.faint).padding(8)
            }
        }
        .contentShape(Rectangle())
        .scaleEffect(selected ? 1.04 : 1)
        .animation(.easeOut(duration: 0.1), value: selected)
    }
}
