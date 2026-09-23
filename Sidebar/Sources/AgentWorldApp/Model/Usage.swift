import AgentWorldKit
import Foundation

/// Tokens by CLI and day for the last week, from the CLIs' own files.
struct UsageSummary: Equatable {
    static let days = 7

    /// Oldest first, today last.
    var days: [Date]
    var byDay: [Date: [String: TokenTotals]]
    /// Conversation id → its tokens this week.
    var bySession: [String: TokenTotals]
    /// Codex's plan window, as it last reported it.
    var codexLimit: (percent: Double, resets: Date?)?

    var today: [String: TokenTotals] { days.last.flatMap { byDay[$0] } ?? [:] }
    var todayTotal: Int { today.values.reduce(0) { $0 + $1.total } }

    func total(on day: Date) -> Int { (byDay[day] ?? [:]).values.reduce(0) { $0 + $1.total } }

    func week(_ provider: String) -> TokenTotals {
        byDay.values.compactMap { $0[provider] }.reduce(TokenTotals(), +)
    }

    init(files: [UsageFile], now: Date = Date(), calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        days = (0..<Self.days).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        byDay = [:]
        bySession = [:]
        var latestLimit: (Double, Date?, Date)?
        for file in files {
            for (day, totals) in file.byDay {
                byDay[day, default: [:]][file.provider, default: TokenTotals()] += totals
                if let id = file.sessionID { bySession[id, default: TokenTotals()] += totals }
            }
            if let percent = file.limitUsedPercent {
                let when = file.byDay.keys.max() ?? .distantPast
                if latestLimit == nil || when >= latestLimit!.2 { latestLimit = (percent, file.limitResetsAt, when) }
            }
        }
        codexLimit = latestLimit.map { ($0.0, $0.1) }
    }

    static func == (lhs: UsageSummary, rhs: UsageSummary) -> Bool {
        lhs.days == rhs.days && lhs.byDay == rhs.byDay && lhs.bySession == rhs.bySession
            && lhs.codexLimit?.percent == rhs.codexLimit?.percent
    }
}

extension AppModel {
    func refreshUsage() {
        guard !usageInFlight else { return }
        usageInFlight = true
        let ledger = usageLedger
        Task.detached(priority: .utility) {
            let summary = UsageSummary(files: ledger.scan(days: UsageSummary.days))
            await MainActor.run {
                self.usageInFlight = false
                if self.usage != summary { self.usage = summary }
            }
        }
    }

    /// A session's tokens this week, when its CLI writes them down.
    func tokens(for session: TerminalSession) -> TokenTotals? {
        guard let id = session.resumeID else { return nil }
        return usage?.bySession[id]
    }
}

enum TokenFormat {
    /// 950, 12.3k, 1.2M.
    static func short(_ value: Int) -> String {
        switch value {
        case ..<1000: "\(value)"
        case ..<100_000: String(format: "%.1fk", Double(value) / 1000).replacingOccurrences(of: ".0k", with: "k")
        case ..<1_000_000: "\(value / 1000)k"
        default: String(format: "%.1fM", Double(value) / 1_000_000).replacingOccurrences(of: ".0M", with: "M")
        }
    }
}
