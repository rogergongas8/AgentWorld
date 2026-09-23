import AgentWorldArt
import AgentWorldKit
import TerminalUI
import AppKit
import SwiftUI

/// The project as a map: every source file a dot (sized by lines, colored by
/// folder), a line for each file that uses another. Files with uncommitted
/// changes wear a ring, the ones your agents touched glow in their CLI's
/// color. Hover to see a file's neighbors, click for what it uses and what
/// uses it, and hand it to the terminal.
struct ProjectMapView: View {
    @EnvironmentObject private var model: AppModel
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var dragStart: CGSize?
    @State private var pinchStart: CGFloat?
    @State private var hovered: Int?
    @State private var selected: Int?
    @State private var search = ""
    @FocusState private var searching: Bool
    /// ⇧-click a second file: the shortest chain of links between the two.
    @State private var pathEnd: Int?
    /// Dots colored by the clusters the links form, or by folder.
    @AppStorage("mapColorBy") private var colorBy = "clusters"
    @AppStorage("mapInsights") private var showsInsights = true

    /// The guide's eight categorical hues, dark steps, in fixed order; more
    /// folders than that share gray ("other").
    static let groupColors: [Color] = [0x3987E5, 0xD95926, 0x199E70, 0xC98500, 0xD55181, 0x008300, 0x9085E9, 0xE66767]
        .map { Color(rgb: RGB(hex: $0)) }
    static let otherColor = Palette.faint

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Palette.border).frame(height: 1)
            HStack(spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    if let map = model.projectMap, map.folder == model.selectedFolder {
                        canvas(map)
                        legend(map).padding(12)
                        if showsInsights {
                            insights(map).padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                    } else {
                        VStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Reading the project…").font(.mono(11)).foregroundStyle(Palette.muted)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                if let map = model.projectMap, let selected, map.graph.nodes.indices.contains(selected) {
                    Rectangle().fill(Palette.border).frame(width: 1)
                    detail(map, selected).frame(width: 290)
                }
            }
        }
        .background(Palette.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.border))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
        .onExitCommand {
            if pathEnd != nil { pathEnd = nil } else if selected != nil { selected = nil } else { model.showsMap = false }
        }
        .onReceive(model.$mapFocus.combineLatest(model.$projectMap.map { $0?.folder })) { path, _ in
            // "A" selects A; "A>B" also shows the way from A to B.
            guard let path, let map = model.projectMap else { return }
            func find(_ name: String) -> Int? { map.graph.nodes.firstIndex { $0.path == name || $0.path.hasSuffix("/" + name) } }
            let parts = path.components(separatedBy: ">")
            guard let index = find(parts[0]) else { return }
            selected = index
            pathEnd = parts.count > 1 ? find(parts[1]) : nil
            model.mapFocus = nil
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "point.3.connected.trianglepath.dotted").foregroundStyle(Palette.claude)
            Text("Map of \(model.workspaceName(model.selectedFolder))").font(.mono(14, .bold)).foregroundStyle(Palette.cream)
            if let map = model.projectMap, map.folder == model.selectedFolder {
                Text("\(map.graph.nodes.count) \(map.symbols ? "symbols" : "files") · \(map.graph.edges.count) links")
                    .font(.mono(11)).foregroundStyle(Palette.muted)
            }
            Spacer()
            GraphSourcePicker()
            Picker("Color by", selection: $colorBy) {
                Text("Clusters").tag("clusters")
                Text("Folders").tag("folders")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 170)
            .help("Color the files by the clusters their links form, or by the folder they're in")
            ChromeButton(symbol: "lightbulb", active: showsInsights, help: "Hubs and surprising links") { showsInsights.toggle() }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Palette.muted)
                TextField("Find a file", text: $search)
                    .textFieldStyle(.plain)
                    .font(.mono(11.5))
                    .focused($searching)
                    .frame(width: 170)
                    .onSubmit { selectFirstMatch() }
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 6).fill(Palette.panel))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(searching ? Palette.claude.opacity(0.6) : Palette.border))
            ChromeButton(symbol: "minus.magnifyingglass", help: "Zoom out") { withAnimation(.easeOut(duration: 0.15)) { zoom = max(0.2, zoom / 1.4) } }
            ChromeButton(symbol: "plus.magnifyingglass", help: "Zoom in") { withAnimation(.easeOut(duration: 0.15)) { zoom = min(8, zoom * 1.4) } }
            ChromeButton(symbol: "arrow.up.left.and.down.right.magnifyingglass", help: "Fit the whole project") {
                withAnimation(.easeOut(duration: 0.2)) { zoom = 1; pan = .zero }
            }
            ChromeButton(symbol: "arrow.clockwise", help: "Read the project again") { model.buildProjectMap(model.selectedFolder) }
            ChromeButton(symbol: "xmark", help: "Close (esc)") { model.showsMap = false }
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(Palette.panel)
    }

    // MARK: - Canvas

    private func canvas(_ map: ProjectMap) -> some View {
        let changed = model.changesByWorkspacePath(map.folder)
        let touched = touchedColors(map)
        let matches = searchMatches(map)
        return GeometryReader { geometry in
            let transform = Transform(bounds: map.bounds, size: geometry.size, zoom: zoom, pan: pan)
            let focus = selected ?? hovered
            let route = routeNodes(map)
            let routeLinks = Set(zip(route, route.dropFirst()).flatMap { [[$0, $1], [$1, $0]] })
            let neighbors = route.isEmpty ? focus.map { Set(map.uses[$0] + map.usedBy[$0] + [$0]) } : Set(route)
            TimelineView(.animation(minimumInterval: 1 / 15, paused: touched.isEmpty)) { context in
                let pulse = 0.5 + 0.5 * sin(context.date.timeIntervalSinceReferenceDate * 3)
                Canvas { graphics, _ in
                    // Links first, faint; the focused file's links bright.
                    for edge in map.graph.edges {
                        let a = transform.point(map.positions[edge.from]), b = transform.point(map.positions[edge.to])
                        var path = Path()
                        path.move(to: a)
                        path.addLine(to: b)
                        if !routeLinks.isEmpty {
                            let onRoute = routeLinks.contains([edge.from, edge.to])
                            graphics.stroke(path, with: .color((onRoute ? Palette.cream : Palette.muted).opacity(onRoute ? 0.95 : 0.04)),
                                            lineWidth: onRoute ? 2.4 : 0.7)
                            continue
                        }
                        let lit = focus.map { edge.from == $0 || edge.to == $0 } ?? false
                        let color: Color = lit ? (edge.from == focus ? Palette.cream : Palette.claude) : Palette.muted
                        graphics.stroke(path, with: .color(color.opacity(lit ? 0.75 : (focus == nil ? 0.16 : 0.05))), lineWidth: lit ? 1.4 : 0.7)
                    }
                    // Files.
                    for (index, node) in map.graph.nodes.enumerated() {
                        let center = transform.point(map.positions[index])
                        let radius = Self.radius(lines: node.lines) * min(2, max(0.7, sqrt(zoom)))
                        let dimmed = (neighbors.map { !$0.contains(index) } ?? false) || (matches.map { !$0.contains(index) } ?? false)
                        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                        if let glow = touched[node.file] {
                            let halo = rect.insetBy(dx: -5 - 3 * pulse, dy: -5 - 3 * pulse)
                            graphics.fill(Path(ellipseIn: halo), with: .color(glow.opacity(0.25 + 0.2 * pulse)))
                        }
                        graphics.fill(Path(ellipseIn: rect), with: .color(color(map, index).opacity(dimmed ? 0.18 : 1)))
                        if changed[node.file] != nil {
                            graphics.stroke(Path(ellipseIn: rect.insetBy(dx: -2.5, dy: -2.5)), with: .color(Palette.warning.opacity(dimmed ? 0.3 : 1)), lineWidth: 1.6)
                        }
                        if index == selected || index == pathEnd {
                            graphics.stroke(Path(ellipseIn: rect.insetBy(dx: -4, dy: -4)), with: .color(Palette.cream), lineWidth: 1.5)
                        }
                    }
                    // Names: the focused file and its neighbors, big files when zoomed in, search hits.
                    for (index, node) in map.graph.nodes.enumerated() {
                        let isNeighbor = neighbors?.contains(index) ?? false
                        let isHit = matches?.contains(index) ?? false
                        let show = isNeighbor || isHit || (zoom >= 2.2 && node.lines > 150) || (zoom >= 3.5)
                        guard show else { continue }
                        let center = transform.point(map.positions[index])
                        let radius = Self.radius(lines: node.lines) * min(2, max(0.7, sqrt(zoom)))
                        let text = Text(node.name).font(.mono(index == focus ? 11.5 : 10, index == focus ? .semibold : .regular))
                            .foregroundColor(index == focus ? Palette.cream : Palette.text)
                        graphics.draw(text, at: CGPoint(x: center.x, y: center.y + radius + 8), anchor: .center)
                    }
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): hovered = nearest(map, to: location, transform: transform)
                case .ended: hovered = nil
                }
            }
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { value in
                        if dragStart == nil { dragStart = pan }
                        pan = CGSize(width: (dragStart?.width ?? 0) + value.translation.width, height: (dragStart?.height ?? 0) + value.translation.height)
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        if pinchStart == nil { pinchStart = zoom }
                        zoom = min(8, max(0.2, (pinchStart ?? 1) * value))
                    }
                    .onEnded { _ in pinchStart = nil }
            )
            .onTapGesture {
                // ⇧-click: the way from the selected file to this one.
                if NSEvent.modifierFlags.contains(.shift), selected != nil, let hovered, hovered != selected {
                    pathEnd = hovered
                } else {
                    selected = hovered
                    pathEnd = nil
                }
            }
            .background(ScrollZoom { delta in zoom = min(8, max(0.2, zoom * (1 + delta * 0.01))) })
            .overlay(alignment: .topLeading) {
                if let hovered, hovered != selected, map.graph.nodes.indices.contains(hovered) {
                    tooltip(map, hovered).position(x: transform.point(map.positions[hovered]).x, y: max(30, transform.point(map.positions[hovered]).y - 34))
                }
            }
        }
        .background(Palette.background)
    }

    private func tooltip(_ map: ProjectMap, _ index: Int) -> some View {
        let node = map.graph.nodes[index]
        return VStack(alignment: .leading, spacing: 2) {
            Text(map.symbols ? node.name : node.path).font(.mono(10.5, .semibold)).foregroundStyle(Palette.cream)
            Text((map.symbols ? [node.kind, node.file].compactMap { $0 }.joined(separator: " · ") + " · " : "\(node.lines) lines · ")
                 + "uses \(map.uses[index].count) · used by \(map.usedBy[index].count)")
                .font(.mono(9.5)).foregroundStyle(Palette.muted)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Palette.raised))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.border))
        .fixedSize()
        .allowsHitTesting(false)
    }

    private func legend(_ map: ProjectMap) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            let names = colorBy == "clusters" ? map.clusterNames : map.groups
            ForEach(Array(names.prefix(8).enumerated()), id: \.offset) { index, group in
                HStack(spacing: 6) {
                    Circle().fill(Self.groupColors[index]).frame(width: 8, height: 8)
                    Text(group).font(.mono(10)).foregroundStyle(Palette.text).lineLimit(1)
                }
            }
            if names.count > 8 {
                HStack(spacing: 6) {
                    Circle().fill(Self.otherColor).frame(width: 8, height: 8)
                    Text("\(names.count - 8) more \(colorBy == "clusters" ? "clusters" : "folders")").font(.mono(10)).foregroundStyle(Palette.muted)
                }
            }
            Rectangle().fill(Palette.border).frame(width: 120, height: 1).padding(.vertical, 2)
            HStack(spacing: 6) {
                Circle().stroke(Palette.warning, lineWidth: 1.6).frame(width: 9, height: 9)
                Text("uncommitted changes").font(.mono(10)).foregroundStyle(Palette.text)
            }
            HStack(spacing: 6) {
                Circle().fill(Palette.claude.opacity(0.4)).frame(width: 11, height: 11)
                Text("touched by an agent").font(.mono(10)).foregroundStyle(Palette.text)
            }
            Text("scroll or pinch to zoom · drag to move").font(.mono(9)).foregroundStyle(Palette.faint).padding(.top, 2)
        }
        .padding(10)
        .fixedSize()
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.panel.opacity(0.92)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border))
    }

    // MARK: - Detail

    private func detail(_ map: ProjectMap, _ index: Int) -> some View {
        let node = map.graph.nodes[index]
        let full = URL(fileURLWithPath: map.folder).appendingPathComponent(node.file).path
        let change = model.changesByWorkspacePath(map.folder)[node.file]
        let target = model.focusedSession ?? model.panelSession ?? model.allSessions.first { $0.folder == map.folder }
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle().fill(color(map, index)).frame(width: 9, height: 9)
                        Text(node.name).font(.mono(13.5, .bold)).foregroundStyle(Palette.cream).lineLimit(2)
                    }
                    Text(map.symbols ? [node.kind, node.file].compactMap { $0 }.joined(separator: " · ") : node.path)
                        .font(.mono(10)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        if !map.symbols { Text("\(node.lines) lines").font(.mono(10.5)).foregroundStyle(Palette.text) }
                        if let change {
                            ChangeBadge(kind: change.kind).scaleEffect(0.8)
                            LineCounts(change: change)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    if let target {
                        Button { model.reveal(target); model.mention(full, in: target) } label: {
                            Label("Mention in \(target.label)", systemImage: "text.cursor")
                        }
                        if target.provider.isAgent {
                        Button {
                            model.reveal(target)
                            target.type(map.symbols
                                ? "Explain what \(node.name) in \(node.file) does and how it connects to what it uses and what uses it. "
                                : "Explain what \(node.path) does and how it fits with the files it uses and the ones that use it. ")
                        } label: {
                            Label("Ask \(target.provider.shortName) to explain it", systemImage: "questionmark.bubble")
                        }
                        }
                    }
                    if let change {
                        Button { model.openDiff(change, in: map.folder) } label: { Label("Show the diff", systemImage: "plusminus") }
                    }
                    Button { NSWorkspace.shared.open(URL(fileURLWithPath: full)) } label: { Label("Open", systemImage: "arrow.up.forward.app") }
                    Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: full)]) } label: {
                        Label("Show in Finder", systemImage: "folder")
                    }
                }
                .buttonStyle(.borderless)
                .font(.mono(11))
                if let pathEnd, map.graph.nodes.indices.contains(pathEnd) {
                    let route = routeNodes(map)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(route.isEmpty ? "NO PATH TO \(map.graph.nodes[pathEnd].name.uppercased())" : "PATH · \(route.count - 1) STEPS")
                            .font(.mono(9.5, .semibold)).foregroundStyle(Palette.muted)
                        ForEach(Array(route.enumerated()), id: \.offset) { step, node in
                            HStack(spacing: 6) {
                                Text(step == 0 ? "●" : "↳").font(.mono(10)).foregroundStyle(Palette.faint)
                                Text(map.graph.nodes[node].name).font(.mono(10.5)).foregroundStyle(Palette.cream).lineLimit(1)
                            }
                        }
                    }
                }
                Text("Cluster: \(map.clusterNames[map.cluster[index]])").font(.mono(10)).foregroundStyle(Palette.muted)
                neighborList("Uses", map.uses[index], map)
                neighborList("Used by", map.usedBy[index], map)
            }
            .padding(14)
        }
        .background(Palette.panel)
    }

    private func neighborList(_ title: String, _ indices: [Int], _ map: ProjectMap) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(title.uppercased()) · \(indices.count)").font(.mono(9.5, .semibold)).foregroundStyle(Palette.muted)
            if indices.isEmpty {
                Text("nothing").font(.mono(10.5)).foregroundStyle(Palette.faint)
            }
            ForEach(indices.sorted { map.graph.nodes[$0].name < map.graph.nodes[$1].name }, id: \.self) { other in
                Button { selected = other } label: {
                    HStack(spacing: 6) {
                        Circle().fill(color(map, other)).frame(width: 6, height: 6)
                        Text(map.graph.nodes[other].name).font(.mono(10.5)).foregroundStyle(Palette.text).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(map.graph.nodes[other].path)
            }
        }
    }

    // MARK: - Helpers

    private func color(_ map: ProjectMap, _ index: Int) -> Color {
        let group = colorBy == "clusters" ? map.cluster[index] : map.groupOf[index]
        return group < Self.groupColors.count ? Self.groupColors[group] : Self.otherColor
    }

    /// The chain from the selected file to the ⇧-clicked one.
    private func routeNodes(_ map: ProjectMap) -> [Int] {
        guard let selected, let pathEnd else { return [] }
        return GraphAnalysis.path(from: selected, to: pathEnd, nodes: map.graph.nodes.count,
                                  edges: map.graph.edges.map { ($0.from, $0.to) }) ?? []
    }

    /// Top left: the hubs and the surprising links, each a click away.
    private func insights(_ map: ProjectMap) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("HUBS").font(.mono(9.5, .semibold)).foregroundStyle(Palette.muted)
            ForEach(map.hubs.prefix(5), id: \.node) { hub in
                Button { selected = hub.node; pathEnd = nil } label: {
                    HStack(spacing: 6) {
                        Circle().fill(color(map, hub.node)).frame(width: 7, height: 7)
                        Text(map.graph.nodes[hub.node].name).font(.mono(10.5)).foregroundStyle(Palette.text).lineLimit(1)
                        Spacer(minLength: 6)
                        Text("\(hub.degree)").font(.mono(9.5)).foregroundStyle(Palette.faint)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(map.graph.nodes[hub.node].path): \(hub.degree) links")
            }
            if !map.bridges.isEmpty {
                Text("SURPRISING LINKS").font(.mono(9.5, .semibold)).foregroundStyle(Palette.muted).padding(.top, 6)
                ForEach(Array(map.bridges.prefix(4).enumerated()), id: \.offset) { _, bridge in
                    Button { selected = bridge.0; pathEnd = bridge.1 } label: {
                        HStack(spacing: 4) {
                            Text(map.graph.nodes[bridge.0].name).foregroundStyle(Palette.text)
                            Text("→").foregroundStyle(Palette.faint)
                            Text(map.graph.nodes[bridge.1].name).foregroundStyle(Palette.text)
                        }
                        .font(.mono(10))
                        .lineLimit(1)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("A link between two clusters that rarely touch: \(map.clusterNames[map.cluster[bridge.0]]) and \(map.clusterNames[map.cluster[bridge.1]])")
                }
            }
            Text("⇧-click a second one for the way between them").font(.mono(9)).foregroundStyle(Palette.faint).padding(.top, 4)
        }
        .padding(10)
        .frame(width: 250, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.panel.opacity(0.92)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border))
    }

    /// Files the app's agents touched, in the color of the (last) one that did.
    private func touchedColors(_ map: ProjectMap) -> [String: Color] {
        guard let changes = model.changes[map.folder] else { return [:] }
        let prefix = map.folder.hasPrefix(changes.root + "/") ? String(map.folder.dropFirst(changes.root.count + 1)) + "/" : ""
        var result: [String: Color] = [:]
        for (path, ids) in changes.touchedBy where prefix.isEmpty || path.hasPrefix(prefix) {
            guard let session = model.allSessions.last(where: { ids.contains($0.id) }) else { continue }
            result[String(path.dropFirst(prefix.count))] = session.provider.swiftColor
        }
        return result
    }

    private func searchMatches(_ map: ProjectMap) -> Set<Int>? {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return nil }
        return Set(map.graph.nodes.indices.filter { map.graph.nodes[$0].path.lowercased().contains(query) })
    }

    private func selectFirstMatch() {
        guard let map = model.projectMap, let first = searchMatches(map)?.min(by: { map.graph.nodes[$0].path.count < map.graph.nodes[$1].path.count }) else { return }
        selected = first
    }

    private func nearest(_ map: ProjectMap, to location: CGPoint, transform: Transform) -> Int? {
        var best: (Int, CGFloat)?
        for (index, position) in map.positions.enumerated() {
            let point = transform.point(position)
            let distance = hypot(point.x - location.x, point.y - location.y)
            let reach = max(10, Self.radius(lines: map.graph.nodes[index].lines) * min(2, max(0.7, sqrt(zoom))) + 4)
            if distance < reach, distance < (best?.1 ?? .infinity) { best = (index, distance) }
        }
        return best?.0
    }

    /// Dot size: grows with the file, slowly.
    static func radius(lines: Int) -> CGFloat { 2.5 + CGFloat(log2(Double(max(1, lines)))) * 0.9 }

    /// Layout space to the view: fit the box, then the user's zoom and pan.
    struct Transform {
        let scale: CGFloat
        let offset: CGPoint

        init(bounds: CGRect, size: CGSize, zoom: CGFloat, pan: CGSize) {
            let fit = min(size.width / max(1, bounds.width), size.height / max(1, bounds.height))
            scale = fit * zoom
            offset = CGPoint(x: size.width / 2 - bounds.midX * scale + pan.width, y: size.height / 2 - bounds.midY * scale + pan.height)
        }

        func point(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * scale + offset.x, y: p.y * scale + offset.y) }
    }
}

/// Mouse-wheel and two-finger scroll over the map zoom it.
struct ScrollZoom: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

    final class View: NSView {
        var onScroll: ((CGFloat) -> Void)?
        var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point) else { return event }
                self.onScroll?(event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 8))
                return nil
            }
        }

        override func removeFromSuperview() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            super.removeFromSuperview()
        }
    }

    func makeNSView(context: Context) -> View {
        let view = View()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: View, context: Context) { nsView.onScroll = onScroll }
}

/// Files (read by the app) or Symbols (graphify's graph, when it's there);
/// without one, a way to get it.
struct GraphSourcePicker: View {
    @EnvironmentObject private var model: AppModel
    @State private var explaining = false

    var body: some View {
        let folder = model.selectedFolder
        let symbols = model.projectMap?.folder == folder && model.projectMap?.symbols == true
        let available = model.hasGraphify(folder)
        HStack(spacing: 2) {
            segment("Files", on: !symbols) { model.buildProjectMap(folder, symbols: false) }
            segment("Symbols", on: symbols) {
                if available { model.buildProjectMap(folder, symbols: true) } else { explaining = true }
            }
            .popover(isPresented: $explaining, arrowEdge: .bottom) { GraphifyHelp(folder: folder) { explaining = false } }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(Palette.background))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Palette.border))
        .help(available ? "Files, or graphify's classes and functions" : "Symbols need graphify: click to see how")
    }

    private func segment(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.mono(11, on ? .semibold : .regular))
                .foregroundStyle(on ? Palette.cream : Palette.muted)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(RoundedRectangle(cornerRadius: 5).fill(on ? Palette.selected : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// How to get a symbol map: graphify, run by your agent or by you.
struct GraphifyHelp: View {
    @EnvironmentObject private var model: AppModel
    let folder: String
    let done: () -> Void

    var body: some View {
        let agent = model.allSessions.first { $0.folder == folder && $0.provider.isAgent }
        VStack(alignment: .leading, spacing: 10) {
            Text("Symbols come from graphify").font(.mono(12.5, .bold)).foregroundStyle(Palette.cream)
            Text("graphify reads the code with real parsers (tree-sitter, 30+ languages) and maps classes and functions and how they call each other. The app shows its graph when there's a graphify-out/graph.json in the workspace.")
                .font(.mono(10.5)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            Text("pipx install graphifyy && graphify install")
                .font(.mono(11)).foregroundStyle(Palette.text)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Palette.background))
            HStack {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("pipx install graphifyy && graphify install", forType: .string)
                }
                if let agent {
                    Button("Ask \(agent.provider.shortName) to build it") {
                        done()
                        model.showsMap = false
                        model.reveal(agent)
                        agent.type("/graphify .")
                    }
                    .help("Types /graphify . into \(agent.label): press return there once graphify is installed")
                }
                Spacer()
                Link("graphify on GitHub", destination: URL(string: "https://github.com/Graphify-Labs/graphify")!)
                    .font(.mono(10.5))
            }
        }
        .padding(14)
        .frame(width: 380)
        .background(Palette.panel)
    }
}

/// The project map in small, at the top of the panel's Changes: where in
/// the project the changes are, and what your agents are touching. Click
/// for the full map.
struct MiniMap: View {
    @EnvironmentObject private var model: AppModel
    @State private var hovering = false

    var body: some View {
        let folder = model.selectedFolder
        Group {
            if let map = model.projectMap, map.folder == folder, !map.graph.nodes.isEmpty {
                let changed = model.changesByWorkspacePath(folder)
                let touched = touchedFiles(map)
                TimelineView(.animation(minimumInterval: 1 / 12, paused: touched.isEmpty)) { context in
                    let pulse = 0.5 + 0.5 * sin(context.date.timeIntervalSinceReferenceDate * 3)
                    Canvas { graphics, size in
                        let transform = ProjectMapView.Transform(bounds: map.bounds, size: size, zoom: 1, pan: .zero)
                        for edge in map.graph.edges {
                            var path = Path()
                            path.move(to: transform.point(map.positions[edge.from]))
                            path.addLine(to: transform.point(map.positions[edge.to]))
                            graphics.stroke(path, with: .color(Palette.muted.opacity(0.12)), lineWidth: 0.5)
                        }
                        for (index, node) in map.graph.nodes.enumerated() {
                            let center = transform.point(map.positions[index])
                            let lit = changed[node.file] != nil
                            let radius: CGFloat = lit ? 3 : 1.6
                            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                            if let glow = touched[node.file] {
                                graphics.fill(Path(ellipseIn: rect.insetBy(dx: -3 - 2 * pulse, dy: -3 - 2 * pulse)), with: .color(glow.opacity(0.35 + 0.25 * pulse)))
                            }
                            graphics.fill(Path(ellipseIn: rect), with: .color(lit ? Palette.warning : Palette.muted.opacity(0.55)))
                        }
                    }
                }
            } else {
                Text(model.mapBuilding ? "Reading the project…" : "Map of the project")
                    .font(.mono(10)).foregroundStyle(Palette.faint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: 110)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.background))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(hovering ? Palette.claude.opacity(0.5) : Palette.border))
        .overlay(alignment: .topTrailing) {
            Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 9, weight: .semibold))
                .foregroundStyle(hovering ? Palette.cream : Palette.faint).padding(6)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { model.openProjectMap() }
        .help("Where the changes are in the project (ringed) and what agents touch (glowing). Click for the full map (⌘⇧M).")
        .onAppear {
            if model.projectMap?.folder != folder { model.buildProjectMap(folder, symbols: false) }
        }
    }

    private func touchedFiles(_ map: ProjectMap) -> [String: Color] {
        guard let changes = model.changes[map.folder] else { return [:] }
        let prefix = map.folder.hasPrefix(changes.root + "/") ? String(map.folder.dropFirst(changes.root.count + 1)) + "/" : ""
        var result: [String: Color] = [:]
        for (path, ids) in changes.touchedBy where prefix.isEmpty || path.hasPrefix(prefix) {
            guard let session = model.allSessions.last(where: { ids.contains($0.id) }) else { continue }
            result[String(path.dropFirst(prefix.count))] = session.provider.swiftColor
        }
        return result
    }
}

extension AppModel {
    /// Opens the map on `path` (relative to the repository root that git reports).
    func showOnMap(_ change: FileChange, in folder: String) {
        let root = changes[folder]?.root ?? folder
        let prefix = folder.hasPrefix(root + "/") ? String(folder.dropFirst(root.count + 1)) + "/" : ""
        let relative = change.path.hasPrefix(prefix) ? String(change.path.dropFirst(prefix.count)) : change.path
        openChange = nil
        openProjectMap()
        mapFocus = relative
    }
}
