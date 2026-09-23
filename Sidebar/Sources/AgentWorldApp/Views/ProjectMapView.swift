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
            if selected != nil { selected = nil } else { model.showsMap = false }
        }
        .onReceive(model.$mapFocus.combineLatest(model.$projectMap.map { $0?.folder })) { path, _ in
            guard let path, let map = model.projectMap,
                  let index = map.graph.nodes.firstIndex(where: { $0.path == path || $0.path.hasSuffix("/" + path) }) else { return }
            selected = index
            model.mapFocus = nil
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "point.3.connected.trianglepath.dotted").foregroundStyle(Palette.claude)
            Text("Map of \(model.workspaceName(model.selectedFolder))").font(.mono(14, .bold)).foregroundStyle(Palette.cream)
            if let map = model.projectMap, map.folder == model.selectedFolder {
                Text("\(map.graph.nodes.count) files · \(map.graph.edges.count) links")
                    .font(.mono(11)).foregroundStyle(Palette.muted)
            }
            Spacer()
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
            let neighbors = focus.map { Set(map.uses[$0] + map.usedBy[$0] + [$0]) }
            TimelineView(.animation(minimumInterval: 1 / 15, paused: touched.isEmpty)) { context in
                let pulse = 0.5 + 0.5 * sin(context.date.timeIntervalSinceReferenceDate * 3)
                Canvas { graphics, _ in
                    // Links first, faint; the focused file's links bright.
                    for edge in map.graph.edges {
                        let a = transform.point(map.positions[edge.from]), b = transform.point(map.positions[edge.to])
                        var path = Path()
                        path.move(to: a)
                        path.addLine(to: b)
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
                        if let glow = touched[node.path] {
                            let halo = rect.insetBy(dx: -5 - 3 * pulse, dy: -5 - 3 * pulse)
                            graphics.fill(Path(ellipseIn: halo), with: .color(glow.opacity(0.25 + 0.2 * pulse)))
                        }
                        graphics.fill(Path(ellipseIn: rect), with: .color(color(map, index).opacity(dimmed ? 0.18 : 1)))
                        if changed[node.path] != nil {
                            graphics.stroke(Path(ellipseIn: rect.insetBy(dx: -2.5, dy: -2.5)), with: .color(Palette.warning.opacity(dimmed ? 0.3 : 1)), lineWidth: 1.6)
                        }
                        if index == selected {
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
                selected = hovered
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
            Text(node.path).font(.mono(10.5, .semibold)).foregroundStyle(Palette.cream)
            Text("\(node.lines) lines · uses \(map.uses[index].count) · used by \(map.usedBy[index].count)")
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
            ForEach(Array(map.groups.prefix(8).enumerated()), id: \.offset) { index, group in
                HStack(spacing: 6) {
                    Circle().fill(Self.groupColors[index]).frame(width: 8, height: 8)
                    Text(group).font(.mono(10)).foregroundStyle(Palette.text).lineLimit(1)
                }
            }
            if map.groups.count > 8 {
                HStack(spacing: 6) {
                    Circle().fill(Self.otherColor).frame(width: 8, height: 8)
                    Text("\(map.groups.count - 8) more folders").font(.mono(10)).foregroundStyle(Palette.muted)
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
        let full = URL(fileURLWithPath: map.folder).appendingPathComponent(node.path).path
        let change = model.changesByWorkspacePath(map.folder)[node.path]
        let target = model.focusedSession ?? model.panelSession ?? model.allSessions.first { $0.folder == map.folder }
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle().fill(color(map, index)).frame(width: 9, height: 9)
                        Text(node.name).font(.mono(13.5, .bold)).foregroundStyle(Palette.cream).lineLimit(2)
                    }
                    Text(node.path).font(.mono(10)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Text("\(node.lines) lines").font(.mono(10.5)).foregroundStyle(Palette.text)
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
                        Button {
                            model.reveal(target)
                            target.type("Explain what \(node.path) does and how it fits with the files it uses and the ones that use it. ")
                        } label: {
                            Label("Ask \(target.provider.shortName) to explain it", systemImage: "questionmark.bubble")
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
        let group = map.groupOf[index]
        return group < Self.groupColors.count ? Self.groupColors[group] : Self.otherColor
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
