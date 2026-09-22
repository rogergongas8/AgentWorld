import AgentWorldKit
import Foundation

/// A way of working with several agents at once, started from the launcher:
/// Claude opens with the plan typed (it runs the others through the
/// `agentworld` skill), and you add the task and press return.
struct Workflow: Identifiable {
    let id: String
    let title: String
    let summary: String
    let symbol: String
    let prompt: String

    static let all = [
        Workflow(id: "second-opinion", title: "Second opinion",
                 summary: "Two agents answer the same question; Claude compares them.",
                 symbol: "person.2",
                 prompt: "Use the agentworld skill: open another CLI beside you (a different one if installed, else another Claude), "
                     + "give it the question below with any context it needs, answer it yourself too, then wait for its answer and "
                     + "compare both — where you agree, where you differ and which is right. Question: "),
        Workflow(id: "build-review", title: "Build & review",
                 summary: "Claude builds it, a fresh agent reviews the diff, Claude fixes.",
                 symbol: "checkmark.seal",
                 prompt: "Use the agentworld skill. Implement the task below. When done, open a reviewer beside you (a different CLI "
                     + "if installed, else another Claude) and ask it to review `git diff` for bugs and missing tests, with a short list "
                     + "of findings. Wait for it, read the review, fix what's valid and tell me what you changed. Task: "),
        Workflow(id: "divide", title: "Divide & conquer",
                 summary: "Claude splits the work across helpers and puts it together.",
                 symbol: "square.grid.2x2",
                 prompt: "Use the agentworld skill. Split the task below into 2–3 independent parts that don't touch the same files. "
                     + "Open one helper pane per part with a self-contained brief, wait for all of them, read their results, integrate "
                     + "and check everything builds. Task: "),
    ]
}
