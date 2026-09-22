import SwiftUI

/// The compact companion window: a roster of every agent/skill in the
/// project — like a character-select screen — rather than a single big
/// "now playing" character. Clicking an agent or skill opens its detail.
/// Driven by `LiveSessionObserver` (tails the real session's transcript; it
/// doesn't launch anything itself), so whichever agent is currently active
/// shows its live status right there in the roster.
struct CompanionWindowView: View {
    @StateObject private var projectManager = ProjectManager()
    @StateObject private var observer = LiveSessionObserver()
    @EnvironmentObject private var launchCoordinator: LaunchCoordinator

    @State private var selectedAgent: Agent?
    @State private var selectedSkill: Skill?

    private let columns = [GridItem(.adaptive(minimum: 84, maximum: 104), spacing: 12)]

    var body: some View {
        Group {
            if let project = projectManager.project {
                roster(project: project)
            } else {
                unconnected
            }
        }
        .padding(16)
        .frame(minWidth: 320, idealWidth: 360, minHeight: 420, idealHeight: 520)
        .onChange(of: projectManager.project) { _, project in
            if let project {
                observer.start(projectURL: project.path)
            } else {
                observer.stop()
            }
        }
        .onAppear { loadPendingProjectIfNeeded() }
        .onChange(of: launchCoordinator.pendingProjectPath) { _, _ in loadPendingProjectIfNeeded() }
        .sheet(item: $selectedAgent) { agent in
            AgentDetailView(agent: agent, status: status(for: agent), skills: projectManager.project?.skills ?? [])
        }
        .sheet(item: $selectedSkill) { skill in
            SkillDetailView(skill: skill)
        }
    }

    /// Auto-loads the project the `claude` shell wrapper asked to show,
    /// instead of making the user pick it manually via "Abrir proyecto"
    /// every time — that's the whole point of the launch integration.
    private func loadPendingProjectIfNeeded() {
        guard let path = launchCoordinator.pendingProjectPath else { return }
        projectManager.loadProject(at: path)
    }

    private func status(for agent: Agent) -> AgentStatus {
        guard let activeAgentName = observer.activeAgentName,
              activeAgentName.caseInsensitiveCompare(agent.name) == .orderedSame else {
            return .idle
        }
        return observer.status
    }

    private var unconnected: some View {
        ContentUnavailableView {
            Label("Sin proyecto", systemImage: "person.3")
        } description: {
            Text("Abre un proyecto para ver a sus agentes en vivo mientras trabajas en tu terminal.")
        } actions: {
            Button("Abrir proyecto", action: projectManager.openProject)
                .buttonStyle(.borderedProminent)
        }
    }

    private func roster(project: Project) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(project: project)

                sectionLabel("AGENTES (\(project.agents.count))")
                if project.agents.isEmpty {
                    Text("Ninguno en .claude/agents.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(project.agents) { agent in
                            Button {
                                selectedAgent = agent
                            } label: {
                                AgentRosterCard(agent: agent, status: status(for: agent))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !project.skills.isEmpty {
                    sectionLabel("SKILLS (\(project.skills.count))")
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(project.skills) { skill in
                            Button {
                                selectedSkill = skill
                            } label: {
                                Label(skill.name, systemImage: "sparkles")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 3)
                        }
                    }
                }
            }
        }
    }

    private func header(project: Project) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.headline)
                if let message = observer.connectionMessage {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Button(action: projectManager.openProject) {
                Image(systemName: "folder.badge.plus")
            }
            .buttonStyle(.borderless)
            .help("Cambiar proyecto")
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct AgentRosterCard: View {
    let agent: Agent
    let status: AgentStatus

    var body: some View {
        VStack(spacing: 6) {
            PixelCharacterView(agentName: agent.name, status: status, pixelSize: 5)
            Text(agent.name)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
            if status != .idle {
                Text(status.title)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(.quaternary.opacity(status == .idle ? 0.3 : 0.6), in: RoundedRectangle(cornerRadius: 10))
    }
}
