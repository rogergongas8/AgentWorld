import AgentWorldArt
import AgentWorldKit
import AppKit
import SwiftUI

/// A skill or an agent, as the right column shows and edits it.
enum KitItem {
    case skill(SkillDefinition)
    case agent(AgentDefinition)

    var name: String {
        switch self {
        case .skill(let skill): skill.name
        case .agent(let agent): agent.name
        }
    }

    var kind: String {
        switch self {
        case .skill: "skill"
        case .agent: "agent"
        }
    }

    var description: String? {
        switch self {
        case .skill(let skill): skill.description
        case .agent(let agent): agent.description
        }
    }

    var scope: ConfigScope {
        switch self {
        case .skill(let skill): skill.scope
        case .agent(let agent): agent.scope
        }
    }

    var plugin: String? {
        switch self {
        case .skill(let skill): skill.plugin
        case .agent(let agent): agent.plugin
        }
    }

    var path: String? {
        switch self {
        case .skill(let skill): skill.path
        case .agent(let agent): agent.path
        }
    }

    /// The file itself: a skill's path can be its folder.
    var file: String? {
        guard let path else { return nil }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
            return (path as NSString).appendingPathComponent("SKILL.md")
        }
        return path
    }

    /// Yours to change in place. Plugin files are overwritten on update and
    /// built-ins have no file, so those get a customized copy instead.
    var isEditable: Bool { path != nil && [.project, .local, .user].contains(scope) }

    var whereItLives: String {
        switch scope {
        case .project, .local: "This project only"
        case .user: "All your projects"
        case .plugin: "From the \(plugin ?? "") plugin"
        case .builtin: "Built into the CLI"
        }
    }
}

// MARK: - Asking the user's own AI

/// Edits and new skills are done by the CLI you already use: AgentWorld writes
/// the request into its prompt, and you read it and press return.
enum KitRequest {
    static func edit(_ item: KitItem, change: String, provider: Provider) -> String {
        let change = change.trimmingCharacters(in: .whitespacesAndNewlines)
        if item.isEditable, let path = item.file {
            return "Update the \(item.kind) \"\(item.name)\" in \(path): \(change). "
                + "Keep its front matter valid and its description clear about what it does and when to use it."
        }
        let origin = item.file.map { "the \(item.kind) at \($0)" } ?? "the built-in \(item.name) \(item.kind)"
        return "Make a customized copy of \(origin) for this project (\(location(item.kind, provider: provider, name: item.name, personal: false))), "
            + "then change it: \(change)."
    }

    static func create(kind: String, what: String, personal: Bool, provider: Provider, hasSkillCreator: Bool) -> String {
        let what = what.trimmingCharacters(in: .whitespacesAndNewlines)
        let helper = kind == "skill" && hasSkillCreator ? "Use the skill-creator skill. " : ""
        let format = kind == "skill"
            ? "front matter with name and a description that says what it does and when to use it, then the instructions"
            : "front matter with name, a description that says what it does and when to use it, only the tools it needs, and a model if it matters; then its system prompt"
        return helper + "Create a new \(provider.name) \(kind) that \(what). Pick a short kebab-case name and put it in "
            + location(kind, provider: provider, name: "<name>", personal: personal) + " (\(format)). Tell me when it's ready and how to use it."
    }

    private static func location(_ kind: String, provider: Provider, name: String, personal: Bool) -> String {
        guard provider.kind == .claude else {
            return personal ? "\(provider.name)'s folder for your own \(kind)s" : "this project's \(provider.name) \(kind)s folder"
        }
        let root = personal ? "~/.claude" : ".claude"
        return kind == "skill" ? "\(root)/skills/\(name)/SKILL.md" : "\(root)/agents/\(name).md"
    }
}

extension AppModel {
    /// Writes `prompt` into the agent terminal you're in, or opens the CLI in a
    /// new tab with it typed. Never presses return: you read it first.
    func ask(_ prompt: String, provider: Provider, session: TerminalSession?) {
        if let session, session.provider.isAgent, session.health == .running {
            reveal(session)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { session.type(prompt) }
            return
        }
        let profile = profiles.first { $0.provider == provider && !$0.isCustom } ?? LaunchProfile(name: provider.name, provider: provider)
        launch(profile, in: selectedFolder, typing: prompt)
    }
}

// MARK: - Detail card

/// What a skill or agent is, how to use it, where it lives, and a box to
/// change it by asking your CLI.
struct KitDetailCard: View {
    @EnvironmentObject private var model: AppModel
    let item: KitItem
    let session: TerminalSession?
    let provider: Provider
    let use: (() -> Void)?
    @Binding var isPresented: Bool
    /// Opened with `e`: the cursor goes straight to the edit box.
    var startEditing = false
    @State private var change = ""
    @FocusState private var editFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let description = item.description {
                Text(description)
                    .font(.mono(11))
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            facts
            howToUse
            Rectangle().fill(Palette.border).frame(height: 1)
            editBox
        }
        .padding(16)
        .frame(width: 380)
        .background(Palette.panel)
        .onAppear { if startEditing { DispatchQueue.main.async { editFocused = true } } }
        .onExitCommand { isPresented = false }
    }

    private var header: some View {
        HStack(spacing: 10) {
            switch item {
            case .agent(let agent):
                FaceView(figure: .crew(CharacterLook(name: agent.name)), scale: 3, waving: true).frame(width: 30, height: 18)
            case .skill(let skill):
                RoundedRectangle(cornerRadius: 2).fill(Color(rgb: Icon.color(for: skill.name))).frame(width: 7, height: 18)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.mono(14, .bold)).foregroundStyle(Palette.cream)
                Text("\(item.kind) · \(item.whereItLives)").font(.mono(10)).foregroundStyle(Palette.muted)
            }
            Spacer()
            if let use {
                Button {
                    isPresented = false
                    use()
                } label: {
                    Label(session == nil ? "Chat" : "Use it", systemImage: "arrow.turn.down.left").font(.mono(11, .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.agent.opacity(0.85))
            }
        }
    }

    @ViewBuilder private var facts: some View {
        if case .agent(let agent) = item {
            VStack(alignment: .leading, spacing: 4) {
                if let model = agent.model { fact("Model", model) }
                fact("Tools", agent.tools.isEmpty ? "all of them" : agent.tools.joined(separator: ", "))
                if !agent.skills.isEmpty { fact("Carries", agent.skills.joined(separator: ", ")) }
            }
        }
        if let path = item.file {
            HStack(spacing: 8) {
                Text(shortPath(path))
                    .font(.mono(9.5)).foregroundStyle(Palette.faint).lineLimit(1).truncationMode(.head)
                Spacer(minLength: 0)
                Button("Open") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
                Button("Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
            }
            .buttonStyle(.link)
            .font(.mono(10))
        }
    }

    /// Relative to the workspace when it's inside it, else with ~.
    private func shortPath(_ path: String) -> String {
        let folder = model.selectedFolder.hasSuffix("/") ? model.selectedFolder : model.selectedFolder + "/"
        return path.hasPrefix(folder) ? String(path.dropFirst(folder.count)) : (path as NSString).abbreviatingWithTildeInPath
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label).font(.mono(10, .semibold)).foregroundStyle(Palette.muted).frame(width: 56, alignment: .leading)
            Text(value).font(.mono(10)).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var howToUse: some View {
        let text: String = switch item {
        case .skill(let skill) where provider.kind == .claude:
            "\(provider.shortName) uses it on its own when what you ask matches. To force it, type /\(skill.qualifiedName)."
        case .skill:
            "\(provider.shortName) uses it when what you ask matches, or ask for it by name."
        case .agent(let agent):
            "\(provider.shortName) hands it work when a task matches, or say \"use the \(agent.name) agent to…\"."
        }
        return Label(text, systemImage: "lightbulb")
            .font(.mono(10.5))
            .foregroundStyle(Palette.warning)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var editBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.isEditable ? "What should change?" : "Customize a copy — what should be different?")
                .font(.mono(10.5, .semibold)).foregroundStyle(Palette.cream)
            TextField("e.g. also run the linter before finishing", text: $change, axis: .vertical)
                .focused($editFocused)
                .textFieldStyle(.roundedBorder)
                .font(.mono(11))
                .lineLimit(2...4)
                .onSubmit(send)
            HStack {
                Text(target).font(.mono(9.5)).foregroundStyle(Palette.faint)
                Spacer()
                Button("Ask \(provider.shortName)", action: send)
                    .disabled(change.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var target: String {
        session?.provider.isAgent == true ? "Typed into \(session!.label) — you press ↩" : "Opens \(provider.shortName) with it typed — you press ↩"
    }

    private func send() {
        guard !change.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isPresented = false
        model.ask(KitRequest.edit(item, change: change, provider: provider), provider: provider, session: session)
    }
}

// MARK: - New skill or agent

/// "+" next to Agents and Skills: describe it, your CLI writes it.
struct NewKitItemButton: View {
    let kind: String
    let session: TerminalSession?
    let provider: Provider
    let config: AgentConfiguration
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 5).fill(Palette.raised))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.muted)
        .help("Describe a new \(kind) and \(provider.shortName) writes it for you")
        .popover(isPresented: $isPresented, arrowEdge: .leading) {
            NewKitItemCard(kind: kind, session: session, provider: provider,
                           hasSkillCreator: config.skills.contains { $0.name == "skill-creator" }, isPresented: $isPresented)
        }
    }
}

struct NewKitItemCard: View {
    @EnvironmentObject private var model: AppModel
    let kind: String
    let session: TerminalSession?
    let provider: Provider
    let hasSkillCreator: Bool
    @Binding var isPresented: Bool
    @State private var what = ""
    @State private var personal = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New \(kind)").font(.mono(14, .bold)).foregroundStyle(Palette.cream)
            Text(kind == "skill"
                 ? "A skill is know-how \(provider.shortName) loads when a task needs it: a checklist, a house style, how to deploy."
                 : "An agent is a helper with its own instructions and tools that \(provider.shortName) sends work to: a reviewer, a tester, a researcher.")
                .font(.mono(10.5)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            Text("What should it do?").font(.mono(10.5, .semibold)).foregroundStyle(Palette.cream)
            TextField(kind == "skill" ? "e.g. write release notes from the git log" : "e.g. review my SwiftUI views for accessibility",
                      text: $what, axis: .vertical)
                .focused($fieldFocused)
                .textFieldStyle(.roundedBorder)
                .font(.mono(11))
                .lineLimit(2...4)
                .onSubmit(send)
            Picker("", selection: $personal) {
                Text("This project").tag(false)
                Text("All my projects").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            HStack {
                Text(session?.provider.isAgent == true ? "Typed into \(session!.label) — you press ↩" : "Opens \(provider.shortName) with it typed — you press ↩")
                    .font(.mono(9.5)).foregroundStyle(Palette.faint)
                Spacer()
                Button("Ask \(provider.shortName)", action: send)
                    .disabled(what.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 380)
        .background(Palette.panel)
        .onAppear { DispatchQueue.main.async { fieldFocused = true } }
        .onExitCommand { isPresented = false }
    }

    private func send() {
        guard !what.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isPresented = false
        model.ask(KitRequest.create(kind: kind, what: what, personal: personal, provider: provider, hasSkillCreator: hasSkillCreator),
                  provider: provider, session: session)
    }
}
