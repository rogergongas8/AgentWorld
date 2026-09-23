import AgentWorldArt
import AgentWorldKit
import SwiftUI

/// "1.2M today" in the title bar; click for the week by CLI.
struct UsageButton: View {
    @EnvironmentObject private var model: AppModel
    @State private var showing = false
    @State private var hovering = false

    var body: some View {
        if let usage = model.usage, usage.byDay.values.contains(where: { !$0.isEmpty }) {
            Button { showing.toggle() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "gauge.with.dots.needle.33percent").font(.system(size: 11))
                    Text(TokenFormat.short(usage.todayTotal)).font(.mono(11, .semibold))
                    Text("today").font(.mono(10.5))
                }
                .foregroundStyle(hovering || showing ? Palette.cream : Palette.muted)
                .padding(.horizontal, 7)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(hovering || showing ? Palette.hover : .clear))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help("Tokens your CLIs used today")
            .popover(isPresented: $showing, arrowEdge: .bottom) {
                UsagePopover(usage: usage).environmentObject(model)
            }
        }
    }
}

struct UsagePopover: View {
    @EnvironmentObject private var model: AppModel
    let usage: UsageSummary
    @State private var hoveredDay: Date?

    private static let reporting: [Provider] = [.claude, .codex, .gemini]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            hero
            chart
            table
            if let limit = usage.codexLimit { codexLimit(limit) }
            sessions
            Text("Kimi, Grok, OpenCode and Cursor don't record usage on disk. Counts are tokens, not money: most plans are subscriptions.")
                .font(.mono(9.5))
                .foregroundStyle(Palette.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(width: 380)
        .background(Palette.panel)
    }

    // MARK: Today

    private var hero: some View {
        let today = usage.today.values.reduce(TokenTotals(), +)
        return VStack(alignment: .leading, spacing: 3) {
            Text("TODAY").font(.mono(9.5, .semibold)).foregroundStyle(Palette.muted)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(TokenFormat.short(today.total)).font(.mono(28, .bold)).foregroundStyle(Palette.cream)
                Text("tokens").font(.mono(12)).foregroundStyle(Palette.muted)
            }
            Text("\(TokenFormat.short(today.input)) in · \(TokenFormat.short(today.cacheRead + today.cacheWrite)) cache · \(TokenFormat.short(today.output)) out")
                .font(.mono(10.5))
                .foregroundStyle(Palette.muted)
        }
    }

    // MARK: Week

    /// One series (all CLIs together), so it never leans on the CLIs'
    /// colors to tell them apart: the tooltip and the table name them.
    private var chart: some View {
        let peak = max(1, usage.days.map(usage.total(on:)).max() ?? 1)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("LAST 7 DAYS").font(.mono(9.5, .semibold)).foregroundStyle(Palette.muted)
                Spacer()
                Text(tooltip).font(.mono(10)).foregroundStyle(Palette.text).lineLimit(1)
            }
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(usage.days, id: \.self) { day in
                    let total = usage.total(on: day)
                    let isToday = day == usage.days.last
                    VStack(spacing: 4) {
                        ZStack(alignment: .bottom) {
                            Color.clear
                            UnevenTopRounded(radius: 4)
                                .fill(Palette.claude.opacity(hoveredDay == nil || hoveredDay == day ? 1 : 0.45))
                                .frame(height: total == 0 ? 0 : max(3, 72 * CGFloat(total) / CGFloat(peak)))
                        }
                        .frame(height: 72)
                        Text(Self.weekday(day)).font(.mono(9.5, isToday ? .semibold : .regular))
                            .foregroundStyle(isToday ? Palette.cream : Palette.faint)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onHover { inside in hoveredDay = inside ? day : (hoveredDay == day ? nil : hoveredDay) }
                }
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(Palette.border).frame(height: 1).padding(.bottom, 17)
            }
        }
    }

    private var tooltip: String {
        guard let day = hoveredDay else { return "hover a day" }
        let parts = Self.reporting.compactMap { provider -> String? in
            guard let totals = usage.byDay[day]?[provider.id], !totals.isEmpty else { return nil }
            return "\(provider.shortName) \(TokenFormat.short(totals.total))"
        }
        return Self.dayName(day) + ": " + (parts.isEmpty ? "nothing" : parts.joined(separator: " · "))
    }

    private var table: some View {
        VStack(spacing: 6) {
            HStack {
                Text("BY CLI").font(.mono(9.5, .semibold)).foregroundStyle(Palette.muted)
                Spacer()
                Text("today").frame(width: 64, alignment: .trailing)
                Text("7 days").frame(width: 64, alignment: .trailing)
            }
            .font(.mono(9.5))
            .foregroundStyle(Palette.faint)
            ForEach(Self.reporting, id: \.id) { provider in
                let today = usage.today[provider.id] ?? TokenTotals()
                let week = usage.week(provider.id)
                HStack(spacing: 8) {
                    FaceView(figure: provider.figure, scale: 1.6).frame(width: 16, height: 10)
                    Text(provider.shortName).font(.mono(11.5)).foregroundStyle(week.isEmpty ? Palette.faint : Palette.cream)
                    Spacer()
                    Text(today.isEmpty ? "—" : TokenFormat.short(today.total)).frame(width: 64, alignment: .trailing)
                    Text(week.isEmpty ? "—" : TokenFormat.short(week.total)).frame(width: 64, alignment: .trailing)
                }
                .font(.mono(11.5))
                .foregroundStyle(Palette.text)
            }
        }
    }

    private func codexLimit(_ limit: (percent: Double, resets: Date?)) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("CODEX PLAN").font(.mono(9.5, .semibold)).foregroundStyle(Palette.muted)
                Spacer()
                Text(String(format: "%.0f%% used", limit.percent) + (limit.resets.map { " · resets " + Self.relative($0) } ?? ""))
                    .font(.mono(10)).foregroundStyle(Palette.text)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.raised)
                    Capsule().fill(limit.percent >= 90 ? Palette.error : limit.percent >= 70 ? Palette.warning : Palette.live)
                        .frame(width: max(4, geometry.size.width * min(1, limit.percent / 100)))
                }
            }
            .frame(height: 6)
        }
    }

    @ViewBuilder private var sessions: some View {
        let open = model.allSessions.compactMap { session in model.tokens(for: session).map { (session, $0) } }
        if !open.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("OPEN SESSIONS").font(.mono(9.5, .semibold)).foregroundStyle(Palette.muted)
                ForEach(open, id: \.0.id) { session, totals in
                    HStack(spacing: 8) {
                        FaceView(figure: session.provider.figure, scale: 1.6).frame(width: 16, height: 10)
                        Text(session.label).font(.mono(11)).foregroundStyle(Palette.cream).lineLimit(1)
                        Text(session.folderName).font(.mono(10)).foregroundStyle(Palette.faint).lineLimit(1)
                        Spacer()
                        Text(TokenFormat.short(totals.total)).font(.mono(11)).foregroundStyle(Palette.text)
                    }
                }
            }
        }
    }

    // MARK: Dates

    private static func weekday(_ day: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEE")
        return formatter.string(from: day)
    }

    private static func dayName(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE d")
        return formatter.string(from: day)
    }

    private static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// A bar with rounded top corners and a square foot on the baseline.
struct UnevenTopRounded: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.width / 2, rect.height)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
