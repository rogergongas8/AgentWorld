import AgentWorldArt
import AgentWorldKit
import Foundation
import TerminalUI

/// Everything a frame needs, captured once per render.
struct SidebarSnapshot {
    enum Connection {
        case noProjectHistory
        case waitingForSession
        case following
        /// A CLI whose sessions AgentWorld can't follow (yet): config only.
        case configOnly

        init(_ connection: SessionFeed.Connection) {
            switch connection {
            case .noProjectHistory: self = .noProjectHistory
            case .waitingForSession: self = .waitingForSession
            case .following: self = .following
            }
        }
    }

    let provider: Provider
    let store: SessionStore
    let config: AgentConfiguration
    let connection: Connection
    let projectName: String
    /// The folder being mapped.
    let cwd: String
    let now: Date
}

/// A titled block of lines. `lines(maxRows:)` must return at most `maxRows`
/// lines (header included), summarizing the rest ("+3 more") when cut.
protocol Section {
    func lines(width: Int, maxRows: Int) -> [StyledLine]
}

func sectionHeader(_ title: String, badge: String? = nil, color: RGB = Theme.muted, width: Int) -> StyledLine {
    var line = StyledLine("── ", .fg(Theme.rule))
    line.append(title, .fg(color, bold: true))
    if let badge { line.append(" \(badge)", .fg(Theme.faint)) }
    line.append(" " + String(repeating: "─", count: max(0, width - line.width - 1)), .fg(Theme.rule))
    return line
}

// MARK: - Header

struct HeaderSection: Section {
    let snapshot: SidebarSnapshot

    func lines(width: Int, maxRows: Int) -> [StyledLine] {
        let now = snapshot.now

        let provider = snapshot.provider
        var title = StyledLine(" ◆ ", .fg(provider.color, bold: true))
        title.append(provider.shortName + " ", .fg(Theme.cream, bold: true))
        title.append(snapshot.projectName, .fg(Theme.muted))
        let (pill, pillColor) = statusPill(now: now)
        var lines = [title.trailing(pill, .fg(pillColor, bold: true)), metaLine(now: now)]
        if snapshot.connection != .configOnly { lines.append(contextLine(width: width)) }
        return Array(lines.prefix(maxRows))
    }

    private func statusPill(now: Date) -> (String, RGB) {
        switch snapshot.connection {
        case .noProjectHistory, .waitingForSession:
            return ("○ WAITING ", Theme.faint)
        case .configOnly:
            return ("◇ EXPLORE ", Theme.muted)
        case .following:
            let store = snapshot.store
            if store.main.status.isBusy || !store.runningSubagents.isEmpty {
                // Gentle pulse while Claude is working.
                let pulse = (Int(now.timeIntervalSinceReferenceDate * 2) % 2) == 0
                return ("● LIVE ", pulse ? Theme.live : Theme.live.darker(0.35))
            }
            return ("● IDLE ", Theme.muted)
        }
    }

    private func metaLine(now: Date) -> StyledLine {
        let store = snapshot.store
        switch snapshot.connection {
        case .noProjectHistory:
            return StyledLine("   Start `claude` here to wake the world up", .fg(Theme.faint, italic: true))
        case .configOnly:
            var parts = [snapshot.provider.name]
            if let model = snapshot.config.model { parts.append(model) }
            return StyledLine("   " + parts.joined(separator: " · "), .fg(Theme.muted))
        case .waitingForSession:
            return StyledLine("   Waiting for the session transcript…", .fg(Theme.faint, italic: true))
        case .following:
            break
        }

        var parts: [String] = []
        if let model = store.context.model { parts.append(Format.model(model)) }
        if let branch = store.context.gitBranch { parts.append("git:\(branch)") }
        if let started = store.startedAt { parts.append(Format.duration(now.timeIntervalSince(started))) }
        if store.turns > 0 { parts.append("\(store.turns) prompt\(store.turns == 1 ? "" : "s")") }
        if let mode = store.context.permissionMode, mode != "default" { parts.append(mode) }
        return StyledLine("   " + parts.joined(separator: " · "), .fg(Theme.muted))
    }

    private func contextLine(width: Int) -> StyledLine {
        let store = snapshot.store
        let used = store.lastUsage?.context ?? 0
        let isLargeWindow = (store.context.model?.contains("[1m]") ?? false) || used > 200_000
        let window = isLargeWindow ? 1_000_000 : 200_000
        let fraction = Double(used) / Double(window)
        let color = fraction > 0.8 ? Theme.error : fraction > 0.6 ? Theme.warning : Theme.live

        let stats = " \(Format.tokens(used))/\(Format.tokens(window))"
        let barWidth = max(4, min(20, width - 8 - stats.count))
        let (filled, empty) = Format.bar(fraction: fraction, width: barWidth)

        var line = StyledLine("   ctx ", .fg(Theme.faint))
        line.append(filled, Style(fg: color, bg: Theme.barEmpty))
        line.append(empty, Style(bg: Theme.barEmpty))
        line.append(stats, .fg(Theme.muted))
        if store.outputTokens > 0 {
            line.append(" · out \(Format.tokens(store.outputTokens))", .fg(Theme.faint))
        }
        return line
    }
}

// MARK: - Caption under the stage

struct CaptionSection: Section {
    let snapshot: SidebarSnapshot

    func lines(width: Int, maxRows: Int) -> [StyledLine] {
        guard maxRows > 0 else { return [] }
        let main = snapshot.store.main
        var status = main.status
        if status == .thinking, !snapshot.store.runningSubagents.isEmpty { status = .delegating }
        let color = Theme.color(for: status)

        var line = StyledLine(" \(Theme.glyph(for: status)) ", .fg(color, bold: true))
        line.append(status.title, .fg(color, bold: true))
        if let action = main.action {
            line.append("  " + action, .fg(Theme.text))
        } else if status == .waitingForUser {
            line.append("  waiting for you", .fg(Theme.muted, italic: true))
        }
        if status.isBusy {
            return [line.trailing(Format.duration(snapshot.now.timeIntervalSince(main.since)), .fg(Theme.faint))]
        }
        return [line]
    }
}

// MARK: - Tasks

struct TasksSection: Section {
    let todos: [TodoItem]

    func lines(width: Int, maxRows: Int) -> [StyledLine] {
        guard !todos.isEmpty, maxRows >= 2 else { return [] }
        let done = todos.filter { $0.state == .completed }.count
        var lines = [sectionHeader("TASKS", badge: "\(done)/\(todos.count)", color: Theme.color(for: .todo), width: width)]

        // Keep the active item in view: start just before the first unfinished one.
        let rows = maxRows - 1
        let firstOpen = todos.firstIndex { $0.state != .completed } ?? max(0, todos.count - rows)
        let start = max(0, min(firstOpen - 1, todos.count - rows))
        for todo in todos[start...].prefix(rows) {
            switch todo.state {
            case .completed:
                lines.append(StyledLine(" ✓ ", .fg(Theme.live)).appending(todo.content, .fg(Theme.faint)))
            case .inProgress:
                lines.append(StyledLine(" ▸ ", .fg(Theme.warning, bold: true)).appending(todo.activeForm ?? todo.content, .fg(Theme.cream, bold: true)))
            case .pending:
                lines.append(StyledLine(" ○ ", .fg(Theme.muted)).appending(todo.content, .fg(Theme.text)))
            }
        }
        return lines
    }
}

// MARK: - Crew (subagents)

struct CrewSection: Section {
    let snapshot: SidebarSnapshot

    func lines(width: Int, maxRows: Int) -> [StyledLine] {
        guard maxRows >= 2 else { return [] }
        let store = snapshot.store
        let running = store.runningSubagents
        let recent = store.subagents.filter { !$0.isRunning }.suffix(3).reversed()
        let defined = snapshot.config.agents

        var lines = [sectionHeader("CREW", badge: running.isEmpty ? nil : "\(running.count) working", color: Theme.color(for: .agent), width: width)]
        if running.isEmpty && recent.isEmpty {
            let names = defined.map(\.name)
            let text = names.isEmpty ? "No subagents yet" : "Ready: " + names.joined(separator: ", ")
            lines.append(StyledLine(" " + text, .fg(Theme.faint, italic: true)))
            return lines
        }

        for subagent in (running + recent).prefix(maxRows - 1) {
            let look = CharacterLook(name: subagent.type)
            let status = subagent.state.status
            if subagent.isRunning {
                var line = StyledLine(" \(Theme.glyph(for: status)) ", .fg(Theme.color(for: status), bold: true))
                line.append(subagent.type, .fg(look.body, bold: true))
                line.append("  " + (subagent.state.action ?? subagent.description ?? status.title), .fg(Theme.text))
                lines.append(line.trailing(Format.duration(snapshot.now.timeIntervalSince(subagent.startedAt)), .fg(Theme.faint)))
            } else {
                let took = (subagent.finishedAt ?? subagent.startedAt).timeIntervalSince(subagent.startedAt)
                var line = StyledLine(status == .failed ? " ✗ " : " ✓ ", .fg(status == .failed ? Theme.error : Theme.live))
                line.append(subagent.type, .fg(look.body.darker(0.25)))
                line.append("  " + (subagent.description ?? ""), .fg(Theme.faint))
                lines.append(line.trailing("\(Format.duration(took)) · \(subagent.toolCalls) tools", .fg(Theme.faint)))
            }
        }
        return lines
    }
}

// MARK: - MCP servers

struct MCPSection: Section {
    let snapshot: SidebarSnapshot
    static let hotFor: TimeInterval = 8

    func lines(width: Int, maxRows: Int) -> [StyledLine] {
        let entries = Self.entries(snapshot)
        guard !entries.isEmpty, maxRows >= 2 else { return [] }
        let accent = Theme.color(for: .mcp(server: "", tool: ""))
        let used = entries.filter { $0.usage != nil }.count
        var lines = [sectionHeader("MCP", badge: "\(entries.count) · \(used) used", color: accent, width: width)]

        let rows = maxRows - 1
        let shown = entries.count > rows ? rows - 1 : rows
        for entry in entries.prefix(shown) {
            lines.append(line(for: entry, accent: accent))
        }
        if entries.count > shown {
            lines.append(StyledLine("   +\(entries.count - shown) more", .fg(Theme.faint)))
        }
        return lines
    }

    struct Entry {
        let name: String
        let usage: CapabilityUsage?
        let definition: MCPServerDefinition?
    }

    /// Configured servers plus any seen in use (e.g. claude.ai connectors,
    /// plugin servers), most recently used first.
    static func entries(_ snapshot: SidebarSnapshot) -> [Entry] {
        let usage = snapshot.store.mcpUsage
        var entries = snapshot.config.mcpServers.map { definition in
            Entry(name: definition.name, usage: usage[definition.name], definition: definition)
        }
        let configured = Set(entries.map { $0.name.lowercased() })
        for (name, use) in usage where !configured.contains(name.lowercased()) {
            entries.append(Entry(name: name, usage: use, definition: nil))
        }
        return entries.sorted { lhs, rhs in
            switch (lhs.usage, rhs.usage) {
            case let (l?, r?): l.lastUsed > r.lastUsed
            case (.some, nil): true
            case (nil, .some): false
            case (nil, nil): lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
    }

    private func line(for entry: Entry, accent: RGB) -> StyledLine {
        guard let usage = entry.usage else {
            return StyledLine(" ○ ", .fg(Theme.faint)).appending(entry.name, .fg(Theme.muted))
        }
        let hot = snapshot.now.timeIntervalSince(usage.lastUsed) < Self.hotFor
        let pulse = hot && Int(snapshot.now.timeIntervalSinceReferenceDate * 4) % 2 == 0
        var line = StyledLine(hot ? " ↯ " : " ● ", .fg(pulse ? accent.lighter(0.4) : accent, bold: hot))
        line.append(entry.name, .fg(hot ? Theme.cream : Theme.text, bold: hot))
        if let detail = usage.lastDetail { line.append("  " + detail, .fg(Theme.faint)) }
        return line.trailing("×\(usage.count)", .fg(accent))
    }
}

// MARK: - Skills

struct SkillsSection: Section {
    let snapshot: SidebarSnapshot

    func lines(width: Int, maxRows: Int) -> [StyledLine] {
        let used = snapshot.store.skillUsage
        var names = snapshot.config.skills.map(\.name)
        let known = Set(names.map { $0.lowercased() })
        names += used.keys.filter { !known.contains($0.lowercased()) }
        guard !names.isEmpty, maxRows >= 2 else { return [] }

        // Used skills first (most recent first), then the rest alphabetically.
        names.sort { lhs, rhs in
            switch (used[lhs], used[rhs]) {
            case let (l?, r?): return l.lastUsed > r.lastUsed
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
        }

        let accent = Theme.color(for: .skill)
        var lines = [sectionHeader("SKILLS", badge: "\(names.count) · \(used.count) used", color: accent, width: width)]
        var current = StyledLine(" ")
        var shownCount = 0
        for name in names {
            let usage = used[name]
            let hot = usage.map { snapshot.now.timeIntervalSince($0.lastUsed) < MCPSection.hotFor } ?? false
            let chip = "✦ \(name)" + (usage.map { $0.count > 1 ? " ×\($0.count)" : "" } ?? "")
            if current.width + chip.count + 1 > width, current.width > 1 {
                if lines.count == maxRows - 1 { break }
                lines.append(current)
                current = StyledLine(" ")
            }
            let style: Style = usage == nil ? .fg(Theme.faint) : .fg(hot ? accent.lighter(0.35) : accent, bold: hot)
            current.append(chip + " ", style)
            shownCount += 1
        }
        if names.count > shownCount {
            current.append("+\(names.count - shownCount)", .fg(Theme.faint))
        }
        if current.width > 1 { lines.append(current) }
        return lines
    }
}

// MARK: - Tool usage

struct ToolsSection: Section {
    let store: SessionStore

    func lines(width: Int, maxRows: Int) -> [StyledLine] {
        let stats = store.toolStats.values.sorted { $0.count > $1.count || ($0.count == $1.count && $0.name < $1.name) }
        guard !stats.isEmpty, maxRows >= 2 else { return [] }
        var lines = [sectionHeader("TOOLS", badge: "\(store.totalToolCalls) calls", width: width)]

        let maxCount = stats.first?.count ?? 1
        let nameWidth = min(12, stats.map { displayName($0).count }.max() ?? 4)
        for stat in stats.prefix(maxRows - 1) {
            let color = Theme.color(for: stat.kind)
            let countText = stat.errors > 0 ? "\(stat.count) ✗\(stat.errors)" : "\(stat.count)"
            let barWidth = max(3, width - nameWidth - countText.count - 6)
            let (filled, _) = Format.bar(fraction: Double(stat.count) / Double(maxCount), width: barWidth)
            var line = StyledLine(" \(Theme.glyph(for: stat.kind)) ", .fg(color))
            line.append(displayName(stat).padded(to: nameWidth) + " ", .fg(Theme.text))
            line.append(filled, .fg(color.darker(0.15)))
            lines.append(line.trailing(countText, .fg(stat.errors > 0 ? Theme.error : Theme.muted)))
        }
        return lines
    }

    private func displayName(_ stat: ToolStat) -> String {
        if case .mcp(_, let tool) = stat.kind { return tool }
        return stat.name
    }
}

// MARK: - Activity log

struct LogSection: Section {
    let snapshot: SidebarSnapshot
    var scrollOffset = 0
    var showsHeader = true

    func lines(width: Int, maxRows: Int) -> [StyledLine] {
        guard maxRows >= 2 else { return [] }
        let log = snapshot.store.log
        let rows = maxRows - (showsHeader ? 1 : 0)
        let end = max(0, log.count - scrollOffset)
        let visible = log[max(0, end - rows)..<end]

        var lines: [StyledLine] = []
        if showsHeader {
            let badge = scrollOffset > 0 ? "↑\(scrollOffset)" : nil
            lines.append(sectionHeader("ACTIVITY", badge: badge, width: width))
        }
        if log.isEmpty {
            lines.append(StyledLine(" Nothing yet — say hi to Claude", .fg(Theme.faint, italic: true)))
        }
        lines += visible.map(line(for:))
        return lines
    }

    private func line(for entry: LogEntry) -> StyledLine {
        var line = StyledLine(" \(Format.clock(entry.time)) ", .fg(Theme.faint))
        let (glyph, color, textStyle) = presentation(for: entry.kind)
        line.append("\(glyph) ", .fg(color, bold: true))
        if let actor = entry.actor {
            line.append("\(actor)› ", .fg(CharacterLook(name: actor).body))
        }
        line.append(entry.text, textStyle)
        return line
    }

    private func presentation(for kind: LogEntry.Kind) -> (Character, RGB, Style) {
        switch kind {
        case .prompt: ("»", Theme.cream, .fg(Theme.cream, bold: true))
        case .reply: ("‹", Theme.claude, .fg(Theme.muted, italic: true))
        case .tool(let tool): (Theme.glyph(for: tool), Theme.color(for: tool), .fg(Theme.text))
        case .toolError: ("✗", Theme.error, .fg(Theme.error))
        case .subagentStarted: ("◆", Theme.color(for: .agent), .fg(Theme.text))
        case .subagentFinished(let failed): (failed ? "✗" : "✓", failed ? Theme.error : Theme.live, .fg(Theme.muted))
        case .turnEnded: ("▸", Theme.live, .fg(Theme.live))
        case .interrupted: ("■", Theme.warning, .fg(Theme.warning))
        case .compacted: ("⇣", Theme.muted, .fg(Theme.muted))
        }
    }
}
