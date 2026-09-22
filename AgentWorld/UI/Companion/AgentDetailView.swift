import SwiftUI

/// Detail sheet for one agent, opened by tapping its card in the roster.
/// Claude Code doesn't record which skills a given agent actually uses (that
/// association isn't part of the `.claude/agents` frontmatter), so this
/// honestly shows the project's full skill list alongside the agent rather
/// than fabricating a per-agent mapping the data doesn't support.
struct AgentDetailView: View {
    let agent: Agent
    let status: AgentStatus
    let skills: [Skill]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Spacer()
                Button("Cerrar", action: dismiss.callAsFunction)
            }

            PixelCharacterView(agentName: agent.name, status: status, pixelSize: 9)

            VStack(spacing: 4) {
                Text(agent.name)
                    .font(.title2.bold())
                Label(status.title, systemImage: "circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let description = agent.description {
                Text(description)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            if let model = agent.model {
                LabeledContent("Modelo", value: model)
                    .font(.caption)
            }

            if !skills.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Skills disponibles en el proyecto")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(skills) { skill in
                        Label(skill.name, systemImage: "sparkles")
                            .font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 320, height: 440)
    }
}
