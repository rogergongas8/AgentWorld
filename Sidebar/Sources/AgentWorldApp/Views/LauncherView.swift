import AgentWorldArt
import AgentWorldKit
import AppKit
import SwiftUI

/// "Start coding in <folder>": one card per CLI, the ones you don't have
/// dozing, and a way to open several side by side.
struct LauncherView: View {
    @EnvironmentObject private var model: AppModel
    let folder: String
    @State private var picking = false
    /// Profile id → how many copies to open (several Claudes side by side is fine).
    @State private var picked: [String: Int] = [:]
    @State private var installHelp: LaunchProfile?

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 6) {
                    FaceRow()
                    (Text("Start coding in ").foregroundColor(Palette.cream) + Text(URL(fileURLWithPath: folder).lastPathComponent).foregroundColor(Palette.claude))
                        .font(.mono(22, .bold))
                    Text(picking ? "Pick up to \(AppModel.maxPanes) (the same CLI more than once is fine), then launch them tiled in one tab."
                                 : "Pick an agent. It runs in a real terminal right here, in this folder.")
                        .font(.mono(12))
                        .foregroundStyle(Palette.muted)
                }
                .padding(.top, 34)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 320), spacing: 12)], spacing: 12) {
                    ForEach(sortedProfiles, id: \.id) { profile in
                        CLICard(profile: profile, folder: folder, picking: picking, count: picked[profile.id] ?? 0,
                                canAdd: pickedCount < AppModel.maxPanes, onCount: { picked[profile.id] = $0 == 0 ? nil : $0 }) {
                            activate(profile)
                        }
                    }
                }
                .frame(maxWidth: 1000)
                .padding(.horizontal, 28)

                HStack(spacing: 12) {
                    if picking {
                        Button("Cancel") {
                            picking = false
                            picked = [:]
                        }
                        Button {
                            model.launchTogether(sortedProfiles.flatMap { Array(repeating: $0, count: picked[$0.id] ?? 0) }, in: folder)
                            picking = false
                            picked = [:]
                        } label: {
                            Label("Launch \(pickedCount) together", systemImage: "square.grid.2x2")
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(pickedCount == 0)
                    } else {
                        Button {
                            picking = true
                        } label: {
                            Label("Launch more than one… (up to \(AppModel.maxPanes), tiled)", systemImage: "square.grid.2x2")
                                .font(.mono(12))
                                .foregroundStyle(Palette.claude)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !picking, model.profiles.contains(where: { $0.provider.kind == .claude && model.executable(for: $0) != nil }) {
                    WorkflowRow(folder: folder)
                        .frame(maxWidth: 1000)
                        .padding(.horizontal, 28)
                }
                Spacer().frame(height: 30)
            }
            .frame(maxWidth: .infinity)
        }
        .sheet(item: $installHelp) { profile in InstallSheet(profile: profile) }
    }

    private var pickedCount: Int { picked.values.reduce(0, +) }

    /// Installed first; the rest after, in the usual order.
    private var sortedProfiles: [LaunchProfile] {
        let all = model.profiles
        return all.filter { model.executable(for: $0) != nil } + all.filter { model.executable(for: $0) == nil }
    }

    private func activate(_ profile: LaunchProfile) {
        guard model.executable(for: profile) != nil else {
            installHelp = profile
            return
        }
        if picking {
            if picked[profile.id] != nil { picked[profile.id] = nil } else if pickedCount < AppModel.maxPanes { picked[profile.id] = 1 }
        } else {
            model.launch(profile, in: folder)
        }
    }
}

/// Ways to work with several agents at once. Each opens Claude with the plan
/// typed; you add the task.
struct WorkflowRow: View {
    @EnvironmentObject private var model: AppModel
    let folder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Workflows · agents working together", color: Palette.agent)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 320), spacing: 12)], spacing: 12) {
                ForEach(Workflow.all) { workflow in
                    WorkflowCard(workflow: workflow) {
                        guard let claude = model.profiles.first(where: { $0.provider.kind == .claude && !$0.isCustom }) else { return }
                        model.launch(claude, in: folder, typing: workflow.prompt)
                    }
                }
            }
        }
    }
}

struct WorkflowCard: View {
    let workflow: Workflow
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: workflow.symbol)
                    .font(.system(size: 16))
                    .foregroundStyle(Palette.agent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text(workflow.title).font(.mono(13, .semibold)).foregroundStyle(Palette.cream)
                    Text(workflow.summary).font(.mono(10.5)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 10).fill(hovering ? Palette.hover : Palette.raised))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(hovering ? Palette.agent.opacity(0.6) : Palette.border))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Opens Claude with this plan typed. Add your task at the end and press return.")
    }
}

/// A little crowd of the CLIs' faces above the title.
struct FaceRow: View {
    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(Provider.all.filter(\.isAgent).prefix(5).enumerated()), id: \.offset) { index, provider in
                FaceView(figure: provider.figure, scale: 3, seed: index)
            }
        }
        .padding(.bottom, 8)
    }
}

struct CLICard: View {
    @EnvironmentObject private var model: AppModel
    let profile: LaunchProfile
    let folder: String
    let picking: Bool
    let count: Int
    let canAdd: Bool
    let onCount: (Int) -> Void
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let provider = profile.provider
        let ready = model.executable(for: profile) != nil
        let config = ready && provider.isAgent ? model.config(provider, in: folder) : nil
        let picked = count > 0
        Button(action: action) {
            HStack(spacing: 14) {
                FaceView(figure: provider.figure, scale: 3.6, waving: hovering && ready, sleeping: !ready, seed: provider.id.count)
                    .frame(width: 36, height: 22)
                    .opacity(ready ? 1 : 0.55)
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.isCustom ? profile.name : provider.name)
                        .font(.mono(13.5, .semibold))
                        .foregroundStyle(ready ? provider.swiftColor : Palette.muted)
                        .lineLimit(1)
                    Text(subtitle(ready: ready, config: config))
                        .font(.mono(10.5))
                        .foregroundStyle(ready ? Palette.muted : Palette.faint)
                        .lineLimit(1)
                    if ready, let config {
                        Text("\(config.skills.count) skills · \(config.mcpServers.count) MCP" + (config.customAgents.isEmpty ? "" : " · \(config.customAgents.count) agents"))
                            .font(.mono(10))
                            .foregroundStyle(Palette.faint)
                    }
                }
                Spacer(minLength: 0)
                if picking, ready {
                    if count > 0 {
                        HStack(spacing: 6) {
                            CountButton(symbol: "minus") { onCount(count - 1) }
                            Text("×\(count)").font(.mono(12, .bold)).foregroundStyle(Palette.live).frame(minWidth: 22)
                            CountButton(symbol: "plus") { onCount(count + 1) }.disabled(!canAdd).opacity(canAdd ? 1 : 0.3)
                        }
                    } else {
                        Image(systemName: "circle").foregroundStyle(Palette.faint).font(.system(size: 16))
                    }
                } else if !ready {
                    Text("install").font(.mono(10)).foregroundStyle(Palette.faint)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .overlay(Capsule().stroke(Palette.border))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 84, maxHeight: 84, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(picked ? Palette.selected : hovering ? Palette.hover : Palette.raised))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(picked || hovering ? provider.swiftColor.opacity(ready ? 0.8 : 0.3) : Palette.border))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(ready ? "\(provider.tagline). Opens in a new tab in \(URL(fileURLWithPath: folder).lastPathComponent)." : "\(provider.name) isn't installed. Click to see how.")
    }

    private func subtitle(ready: Bool, config: AgentConfiguration?) -> String {
        if profile.isCustom { return ([profile.executable] + profile.args).joined(separator: " ") }
        guard ready else { return "not installed" }
        return config?.model.map(Format.model) ?? profile.provider.tagline
    }
}


struct CountButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Palette.cream)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Palette.hover))
        }
        .buttonStyle(.plain)
    }
}

struct InstallSheet: View {
    @Environment(\.dismiss) private var dismiss
    let profile: LaunchProfile

    var body: some View {
        let provider = profile.provider
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                FaceView(figure: provider.figure, scale: 4, sleeping: true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(provider.name) isn't installed").font(.mono(15, .bold)).foregroundStyle(Palette.cream)
                    Text(provider.tagline).font(.mono(11.5)).foregroundStyle(Palette.muted)
                }
            }
            if let hint = provider.installHint {
                Text("Install it from a terminal:").font(.mono(11.5)).foregroundStyle(Palette.muted)
                HStack {
                    Text(hint).font(.mono(12)).foregroundStyle(Palette.cream).textSelection(.enabled)
                    Spacer()
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(hint, forType: .string)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 6).fill(Palette.terminalBackground))
            } else {
                Text("Install it following its official docs; AgentWorld looks for the `\(profile.executable)` command.")
                    .font(.mono(11.5)).foregroundStyle(Palette.muted)
            }
            Text("Once installed, it shows up ready here (reopen the app if it doesn't).")
                .font(.mono(10.5)).foregroundStyle(Palette.faint)
            HStack {
                Spacer()
                Button("OK") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 480)
        .background(Palette.panel)
    }
}
