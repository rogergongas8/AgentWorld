//
//  ContentView.swift
//  AgentWorld
//
//  Created by Roger Gonzalbo Gaspar on 09/09/2026.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var projectManager = ProjectManager()
    @StateObject private var claudeRuntime = ClaudeRuntime()

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            dashboard
        }
        .frame(minWidth: 900, minHeight: 600)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: projectManager.openProject) {
                    Label("Abrir proyecto", systemImage: "folder.badge.plus")
                }
            }
        }
    }

    private var sidebar: some View {
        List {
            Section("PROYECTO") {
                Label("Resumen", systemImage: "square.grid.2x2")
                    .foregroundStyle(.tint)

                if projectManager.project != nil {
                    Label("Agentes", systemImage: "person.2")
                    Label("Skills", systemImage: "sparkles")
                    Label("Herramientas", systemImage: "hammer")
                    Label("Conexiones", systemImage: "point.3.connected.trianglepath.dotted")
                }
            }

            Section("ACTIVIDAD") {
                Label("Sesiones", systemImage: "clock.arrow.circlepath")
            }
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 220)
        .safeAreaInset(edge: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Label("AgentWorld", systemImage: "globe.americas.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.tint)

                Text(projectManager.project?.name ?? "Sin proyecto abierto")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private var dashboard: some View {
        if let project = projectManager.project {
            ProjectDashboard(project: project, runtime: claudeRuntime, openProject: projectManager.openProject)
        } else {
            WelcomeView(openProject: projectManager.openProject)
        }
    }
}

private struct WelcomeView: View {
    let openProject: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Bienvenido a AgentWorld", systemImage: "globe.americas.fill")
        } description: {
            Text("Abre un proyecto para descubrir su configuración de Claude Code.")
        } actions: {
            Button("Abrir proyecto", action: openProject)
                .buttonStyle(.borderedProminent)
        }
    }
}

private struct ProjectDashboard: View {
    let project: Project
    @ObservedObject var runtime: ClaudeRuntime
    let openProject: () -> Void
    @State private var selectedItem: ConfigurationItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(project.name)
                            .font(.largeTitle.bold())
                        Text(project.path.path)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    Spacer()

                    Button("Cambiar proyecto", action: openProject)
                }

                ClaudeStatusCard(isDetected: project.hasClaudeDirectory)

                ClaudeSessionPanel(runtime: runtime, projectURL: project.path)

                if project.hasClaudeDirectory {
                    AgentWorldView(
                        agents: project.agents,
                        activeAgentName: runtime.activeAgentName,
                        activeStatus: runtime.status
                    ) { agent in
                        selectedItem = ConfigurationItem(agent: agent)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Explorador del proyecto")
                        .font(.title2.weight(.semibold))

                    HStack(spacing: 16) {
                        ExplorerCard(title: "Agentes", symbol: "person.2.fill", count: project.agents.count.formatted(), detail: explorerDetail(count: project.agents.count, noun: "agente"))
                        ExplorerCard(title: "Skills", symbol: "sparkles", count: project.skills.count.formatted(), detail: explorerDetail(count: project.skills.count, noun: "skill"))
                        ExplorerCard(title: "Actividad", symbol: "bolt.fill", count: "—", detail: "Próximamente")
                    }
                }

                if project.hasClaudeDirectory {
                    ConfigurationOverview(agents: project.agents, skills: project.skills) { item in
                        selectedItem = item
                    }
                } else {
                    NextStepCard(message: "Crea una carpeta .claude en el proyecto o abre un proyecto que ya use Claude Code.")
                }

                if let selectedItem {
                    ConfigurationInspector(item: selectedItem) {
                        self.selectedItem = nil
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 1_100, alignment: .leading)
        }
    }

    private func explorerDetail(count: Int, noun: String) -> String {
        count == 1 ? "1 \(noun) encontrado" : "\(count) \(noun)s encontrados"
    }
}

private struct ClaudeSessionPanel: View {
    @ObservedObject var runtime: ClaudeRuntime
    let projectURL: URL
    @State private var prompt = "Describe brevemente la estructura de este proyecto."

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Sesión de Claude", systemImage: "bolt.horizontal.circle.fill")
                    .font(.title2.weight(.semibold))
                Spacer()
                Label(runtime.status.title, systemImage: runtime.status.symbolName)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(runtime.status == .error ? Color.red : Color.accentColor)
            }

            HStack(alignment: .top, spacing: 18) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 68))
                    .foregroundStyle(runtime.status == .completed ? Color.green : runtime.status == .error ? Color.red : Color.accentColor)
                    .frame(width: 88, height: 88)
                    .background(.background.opacity(0.7), in: Circle())

                VStack(alignment: .leading, spacing: 10) {
                    Text("Inicia una misión en este proyecto")
                        .font(.headline)
                    Text("La primera integración se ejecuta en modo de planificación. No concede edición desde Claude; los hooks ya configurados en el proyecto siguen formando parte de su configuración.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            TextField("¿Qué quieres que haga Claude?", text: $prompt, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)

            HStack {
                if runtime.isRunning {
                    Button("Cancelar", role: .destructive, action: runtime.stop)
                } else {
                    Button("Iniciar sesión") {
                        runtime.start(prompt: prompt, projectURL: projectURL)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!runtime.isAvailable || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if !runtime.isAvailable {
                    Text("Claude Code no está instalado o no está disponible.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Spacer()
            }

            if let launchError = runtime.launchError {
                Label(launchError, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            if !runtime.activities.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Actividad reciente")
                        .font(.headline)
                    ForEach(runtime.activities.prefix(5)) { activity in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(activity.title)
                                .font(.callout.weight(.medium))
                            if let detail = activity.detail, !detail.isEmpty {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .padding(24)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct ClaudeStatusCard: View {
    let isDetected: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: isDetected ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 30))
                .foregroundStyle(isDetected ? .green : .orange)

            VStack(alignment: .leading, spacing: 4) {
                Text(isDetected ? "Claude Code detectado" : "No se encontró .claude")
                    .font(.headline)
                Text(isDetected
                     ? "AgentWorld puede empezar a descubrir la configuración de este proyecto."
                     : "AgentWorld seguirá funcionando, pero aún no hay configuración de Claude Code que mostrar.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(22)
        .background(isDetected ? Color.green.opacity(0.10) : Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct ExplorerCard: View {
    let title: String
    let symbol: String
    let count: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
            Text(count)
                .font(.largeTitle.bold())
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.quaternary, lineWidth: 1)
        }
    }
}

private struct AgentWorldView: View {
    let agents: [Agent]
    let activeAgentName: String?
    let activeStatus: AgentStatus
    let selectAgent: (Agent) -> Void

    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 16)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mundo de agentes")
                        .font(.title2.weight(.semibold))
                    Text("El estado de cada personaje representa la actividad real del agente.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label("\(agents.count) \(agents.count == 1 ? "agente" : "agentes")", systemImage: "person.2.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.tint)
            }

            if agents.isEmpty {
                ContentUnavailableView(
                    "Aún no hay personajes",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("Crea un agente en .claude/agents y aparecerá aquí automáticamente.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(agents) { agent in
                        AgentCharacterCard(agent: agent, status: status(for: agent)) {
                            selectAgent(agent)
                        }
                    }
                }
            }
        }
        .padding(24)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.12), .purple.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20)
        )
    }

    private func status(for agent: Agent) -> AgentStatus {
        guard let activeAgentName, activeAgentName.caseInsensitiveCompare(agent.name) == .orderedSame else {
            return .idle
        }
        return activeStatus
    }
}

private struct AgentCharacterCard: View {
    let agent: Agent
    let status: AgentStatus
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .fill(.background.opacity(0.78))
                        .frame(width: 88, height: 88)
                        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)

                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 62))
                        .foregroundStyle(.tint)

                    Image(systemName: status.symbolName)
                        .font(.title3)
                        .foregroundStyle(.orange)
                        .background(Circle().fill(.background).padding(-3))
                }

                Text(agent.name)
                    .font(.headline)
                    .lineLimit(1)
                Label(status.title, systemImage: "circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(18)
            .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.white.opacity(0.32), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(agent.name), \(status.title)")
    }
}

private struct ConfigurationOverview: View {
    let agents: [Agent]
    let skills: [Skill]
    let selectItem: (ConfigurationItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Configuración detectada")
                .font(.title2.weight(.semibold))

            HStack(alignment: .top, spacing: 16) {
                ConfigurationList(
                    title: "Agentes",
                    symbol: "person.2.fill",
                    emptyMessage: "No se han encontrado archivos Markdown en .claude/agents.",
                    items: agents.map { ConfigurationItem(agent: $0) },
                    selectItem: selectItem
                )
                ConfigurationList(
                    title: "Skills",
                    symbol: "sparkles",
                    emptyMessage: "No se han encontrado archivos SKILL.md en .claude/skills.",
                    items: skills.map { ConfigurationItem(skill: $0) },
                    selectItem: selectItem
                )
            }
        }
    }
}

private struct ConfigurationItem: Identifiable {
    enum Kind: String {
        case agent = "Agente"
        case skill = "Skill"
    }

    let id: URL
    let kind: Kind
    let name: String
    let detail: String
    let model: String?
    let path: URL
    let source: String

    init(agent: Agent) {
        self.id = agent.id
        self.kind = .agent
        self.name = agent.name
        self.detail = agent.description ?? agent.model ?? agent.path.lastPathComponent
        self.model = agent.model
        self.path = agent.path
        self.source = agent.source
    }

    init(skill: Skill) {
        self.id = skill.id
        self.kind = .skill
        self.name = skill.name
        self.detail = skill.description ?? skill.path.deletingLastPathComponent().lastPathComponent
        self.model = nil
        self.path = skill.path
        self.source = skill.source
    }
}

private struct ConfigurationList: View {
    let title: String
    let symbol: String
    let emptyMessage: String
    let items: [ConfigurationItem]
    let selectItem: (ConfigurationItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(.tint)

            if items.isEmpty {
                Text(emptyMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            } else {
                ForEach(items) { item in
                    Button {
                        selectItem(item)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name)
                                .fontWeight(.medium)
                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 5)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct ConfigurationInspector: View {
    let item: ConfigurationItem
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                Label(item.kind.rawValue, systemImage: item.kind == .agent ? "person.2.fill" : "sparkles")
                    .font(.headline)
                    .foregroundStyle(.tint)
                Spacer()
                Button("Cerrar", action: close)
            }

            Text(item.name)
                .font(.title.bold())

            LabeledContent("Descripción", value: item.detail)
            if let model = item.model {
                LabeledContent("Modelo", value: model)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Archivo de configuración")
                    .font(.headline)
                Text(item.path.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Contenido original")
                    .font(.headline)
                ScrollView(.vertical) {
                    Text(item.source)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                .frame(maxHeight: 280)
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.quaternary, lineWidth: 1)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct NextStepCard: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Siguiente paso")
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    ContentView()
}
