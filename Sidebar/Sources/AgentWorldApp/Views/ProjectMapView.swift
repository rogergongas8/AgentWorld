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
    @State private var yaw = 0.6
    @State private var pitch = 0.35
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var dragStart: DragStart?
    @State private var dragging = false
    @State private var pinchStart: CGFloat?
    /// Set when a script asked for a view: the map stops turning by itself.
    @State private var frozen = false
    @State private var hovered: Int?
    @State private var selected: Int?
    @State private var search = ""
    @FocusState private var searching: Bool
    /// ⇧-click a second file: the shortest chain of links between the two.
    @State private var pathEnd: Int?
    /// Dots colored by the clusters the links form, or by folder.
    @AppStorage("mapColorBy") private var colorBy = "clusters"
    @AppStorage("mapInsights") private var showsInsights = true
    /// The map turns slowly by itself (until you hover, select or drag).
    @AppStorage("mapSpin") private var spins = true
    /// Files that link to nothing, on the outer shell.
    @AppStorage("mapShowLoose") private var showsLoose = true

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
        .onReceive(Timer.publish(every: 1.0 / 24, on: .main, in: .common).autoconnect()) { _ in
            if spins, !frozen, !dragging, hovered == nil, selected == nil, NSApp.isActive { yaw += 0.0045 }
        }
        .onReceive(model.$mapCamera) { request in
            guard let request, request.count >= 3 else { return }
            yaw = request[0]
            pitch = request[1]
            zoom = CGFloat(request[2])
            pan = .zero
            frozen = true
            model.mapCamera = nil
        }
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
                Text("\(map.graph.nodes.count) files · \(map.graph.edges.count) links" + (map.linked.contains(false) ? " · \(map.linked.filter { !$0 }.count) unlinked" : ""))
                    .font(.mono(11)).foregroundStyle(Palette.muted)
            }
            Spacer()
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
            ChromeButton(symbol: "rotate.3d", active: spins, help: "Turn the map slowly (it stops while you hover, select or drag)") { spins.toggle() }
            ChromeButton(symbol: "circle.dotted", active: showsLoose, help: "Files that link to nothing, on the outer shell") { showsLoose.toggle() }
            ChromeButton(symbol: "arrow.up.left.and.down.right.magnifyingglass", help: "Reset the view (or double-click the map)") { resetView() }
            ChromeButton(symbol: "arrow.clockwise", help: "Read the project again") { model.buildProjectMap(model.selectedFolder) }
            ChromeButton(symbol: "xmark", help: "Close (esc)") { model.showsMap = false }
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(Palette.panel)
    }

    // MARK: - Canvas (3D)

    /// A camera orbiting the 3D layout (a ball of radius 500). A gentle
    /// perspective makes near files bigger and brighter than far ones.
    struct Camera {
        static let radius = 500.0
        static let eye = 1700.0
        let yaw: Double
        let pitch: Double
        let size: CGSize
        let zoom: CGFloat
        let pan: CGSize

        struct Projected {
            let point: CGPoint
            /// -1 (far) … 1 (near).
            let depth: Double
            /// Perspective scale, around 1.
            let factor: CGFloat
        }

        func project(_ p: GraphLayout3D.Point) -> Projected {
            let cosY = cos(yaw), sinY = sin(yaw), cosP = cos(pitch), sinP = sin(pitch)
            let x1 = p.x * cosY + p.z * sinY
            let z1 = -p.x * sinY + p.z * cosY
            let y2 = p.y * cosP - z1 * sinP
            let z2 = p.y * sinP + z1 * cosP
            let factor = Self.eye / (Self.eye - z2)
            let fit = Double(min(size.width, size.height)) / (1.95 * Self.radius) * Double(zoom)
            return Projected(
                point: CGPoint(x: Double(size.width) / 2 + Double(pan.width) + x1 * factor * fit,
                               y: Double(size.height) / 2 + Double(pan.height) - y2 * factor * fit),
                depth: max(-1, min(1, z2 / Self.radius)), factor: CGFloat(factor))
        }
    }

    /// Everything one frame needs, worked out once.
    private struct Frame {
        let map: ProjectMap
        let camera: Camera
        let projected: [Camera.Projected]
        /// The files to draw, far to near.
        let order: [Int]
        let focus: Int?
        let neighbors: Set<Int>?
        let matches: Set<Int>?
        let routeLinks: Set<[Int]>
        let changed: [String: FileChange]
        let touched: [String: Color]
        let hubs: Set<Int>
    }

    private struct DragStart {
        let yaw: Double
        let pitch: Double
        let pan: CGSize
        /// ⌥ held: move the map instead of turning it.
        let moves: Bool
    }

    private func canvas(_ map: ProjectMap) -> some View {
        let changed = model.changesByWorkspacePath(map.folder)
        let touched = touchedColors(map)
        let matches = searchMatches(map)
        let hubs = Set(map.hubs.prefix(6).map(\.node))
        return GeometryReader { geometry in
            let camera = Camera(yaw: yaw, pitch: pitch, size: geometry.size, zoom: zoom, pan: pan)
            let projected = map.positions3D.map { camera.project($0) }
            let focus = selected ?? hovered
            let route = routeNodes(map)
            let routeLinks = Set(zip(route, route.dropFirst()).flatMap { [[$0, $1], [$1, $0]] })
            let neighbors = route.isEmpty ? focus.map { Set(map.uses[$0] + map.usedBy[$0] + [$0]) } : Set(route)
            let order = map.graph.nodes.indices
                .filter { showsLoose || map.linked[$0] || $0 == focus || (matches?.contains($0) ?? false) }
                .sorted { projected[$0].depth < projected[$1].depth }
            let frame = Frame(map: map, camera: camera, projected: projected, order: order, focus: focus, neighbors: neighbors,
                              matches: matches, routeLinks: routeLinks, changed: changed, touched: touched, hubs: hubs)
            TimelineView(.animation(minimumInterval: 1 / 20, paused: touched.isEmpty)) { context in
                let pulse = 0.5 + 0.5 * sin(context.date.timeIntervalSinceReferenceDate * 3)
                Canvas { graphics, size in
                    drawBackdrop(&graphics, size)
                    drawLinks(&graphics, frame)
                    drawFiles(&graphics, frame, pulse: pulse)
                    drawNames(&graphics, frame)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): hovered = nearest(frame, to: location)
                case .ended: hovered = nil
                }
            }
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { value in
                        if dragStart == nil {
                            dragStart = DragStart(yaw: yaw, pitch: pitch, pan: pan, moves: NSEvent.modifierFlags.contains(.option))
                            dragging = true
                        }
                        guard let start = dragStart else { return }
                        if start.moves {
                            pan = CGSize(width: start.pan.width + value.translation.width, height: start.pan.height + value.translation.height)
                        } else {
                            yaw = start.yaw + Double(value.translation.width) * 0.008
                            pitch = max(-1.45, min(1.45, start.pitch + Double(value.translation.height) * 0.008))
                        }
                    }
                    .onEnded { _ in
                        dragStart = nil
                        dragging = false
                    }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        if pinchStart == nil { pinchStart = zoom }
                        zoom = min(8, max(0.3, (pinchStart ?? 1) * value))
                    }
                    .onEnded { _ in pinchStart = nil }
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded { resetView() })
            .onTapGesture {
                // ⇧-click: the way from the selected file to this one.
                if NSEvent.modifierFlags.contains(.shift), selected != nil, let hovered, hovered != selected {
                    pathEnd = hovered
                } else {
                    selected = hovered
                    pathEnd = nil
                }
            }
            .background(ScrollZoom { delta in zoom = min(8, max(0.3, zoom * (1 + delta * 0.01))) })
            .overlay(alignment: .topLeading) {
                if let hovered, hovered != selected, map.graph.nodes.indices.contains(hovered) {
                    let at = projected[hovered].point
                    tooltip(map, hovered).position(x: at.x, y: max(30, at.y - 34))
                }
            }
        }
        .background(Palette.background)
    }

    // MARK: - Drawing

    /// A soft glow in the middle, so the map floats on dark space.
    private func drawBackdrop(_ graphics: inout GraphicsContext, _ size: CGSize) {
        graphics.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
            Gradient(colors: [Color(rgb: RGB(hex: 0x182030)), Palette.background]),
            center: CGPoint(x: size.width / 2, y: size.height * 0.46), startRadius: 0, endRadius: max(size.width, size.height) * 0.62))
    }

    /// Far things fade: 0.32 at the back, 1 at the front.
    private func fog(_ depth: Double) -> Double { 0.32 + 0.68 * (depth + 1) / 2 }

    private func nodeRadius(_ map: ProjectMap, _ index: Int, _ projected: Camera.Projected) -> CGFloat {
        var base: CGFloat = map.linked[index] ? 2.4 + CGFloat(log2(Double(max(1, map.graph.nodes[index].lines)))) * 0.7 : 1.5
        // The clusters past the first eight share gray: smaller, so the main ones stand out.
        if colorIndex(map, index) >= Self.groupColors.count { base *= 0.78 }
        return base * projected.factor * min(1.8, max(0.75, sqrt(zoom)))
    }

    /// Links first, tinted by their cluster and faded with depth; the focused
    /// file's links bright. Batched by color and depth, so thousands stay cheap.
    private func drawLinks(_ graphics: inout GraphicsContext, _ f: Frame) {
        let dimAll = f.focus != nil || !f.routeLinks.isEmpty
        var buckets: [Int: Path] = [:]
        for edge in f.map.graph.edges {
            let a = f.projected[edge.from], b = f.projected[edge.to]
            if !f.routeLinks.isEmpty {
                if f.routeLinks.contains([edge.from, edge.to]) {
                    var path = Path()
                    path.move(to: a.point)
                    path.addLine(to: b.point)
                    graphics.stroke(path, with: .color(Palette.cream.opacity(0.95)), lineWidth: 2.4)
                    continue
                }
            } else if let focus = f.focus, edge.from == focus || edge.to == focus {
                var path = Path()
                path.move(to: a.point)
                path.addLine(to: b.point)
                graphics.stroke(path, with: .color((edge.from == focus ? Palette.cream : Palette.claude).opacity(0.85)), lineWidth: 1.4)
                continue
            }
            let bucket = min(3, Int((a.depth + b.depth + 2) / 4 * 4))
            let key = colorIndex(f.map, edge.from) * 4 + bucket
            buckets[key, default: Path()].move(to: a.point)
            buckets[key, default: Path()].addLine(to: b.point)
        }
        for (key, path) in buckets {
            let alpha = (0.08 + 0.09 * Double(key % 4)) * (dimAll ? 0.3 : 1)
            graphics.stroke(path, with: .color(Self.shades[key / 4].opacity(alpha)), lineWidth: 0.6 + 0.25 * CGFloat(key % 4))
        }
    }

    private func drawFiles(_ graphics: inout GraphicsContext, _ f: Frame, pulse: Double) {
        for index in f.order {
            let p = f.projected[index]
            let node = f.map.graph.nodes[index]
            let radius = nodeRadius(f.map, index, p)
            let dimmed = (f.neighbors.map { !$0.contains(index) } ?? false) || (f.matches.map { !$0.contains(index) } ?? false)
            let alpha = fog(p.depth) * (f.map.linked[index] ? 1 : 0.55) * (dimmed ? 0.16 : 1)
            let tint = color(f.map, index)
            let rect = CGRect(x: p.point.x - radius, y: p.point.y - radius, width: radius * 2, height: radius * 2)
            // A soft glow around hubs, and a pulsing one around what an agent touched.
            if !dimmed, let glow = f.touched[node.file] ?? (f.hubs.contains(index) ? tint : nil) {
                let reach = radius * (f.touched[node.file] != nil ? 3.4 + 0.8 * pulse : 3.0)
                let area = CGRect(x: p.point.x - reach, y: p.point.y - reach, width: reach * 2, height: reach * 2)
                graphics.fill(Path(ellipseIn: area), with: .radialGradient(
                    Gradient(colors: [glow.opacity(0.42), glow.opacity(0)]), center: p.point, startRadius: radius * 0.6, endRadius: reach))
            }
            graphics.fill(Path(ellipseIn: rect), with: .color(tint.opacity(alpha)))
            // A small highlight makes the bigger files read as spheres.
            if radius >= 3.2, !dimmed {
                let spot = radius * 0.42
                let at = CGPoint(x: p.point.x - radius * 0.34, y: p.point.y - radius * 0.38)
                graphics.fill(Path(ellipseIn: CGRect(x: at.x - spot, y: at.y - spot, width: spot * 2, height: spot * 2)),
                              with: .color(Color.white.opacity(0.26 * alpha)))
            }
            if f.changed[node.file] != nil {
                graphics.stroke(Path(ellipseIn: rect.insetBy(dx: -2.5, dy: -2.5)), with: .color(Palette.warning.opacity(dimmed ? 0.3 : 1)), lineWidth: 1.6)
            }
            if index == selected || index == pathEnd {
                graphics.stroke(Path(ellipseIn: rect.insetBy(dx: -4, dy: -4)), with: .color(Palette.cream), lineWidth: 1.5)
            }
        }
    }

    /// Names: the focused file and its neighbors, search hits, the hubs, and big files when zoomed in.
    private func drawNames(_ graphics: inout GraphicsContext, _ f: Frame) {
        // Labels that would land on one already drawn are skipped (the focused file and search hits always show).
        var taken: [CGRect] = []
        let nearFirst = f.order.reversed().sorted { a, b in
            let pa = a == f.focus || (f.matches?.contains(a) ?? false), pb = b == f.focus || (f.matches?.contains(b) ?? false)
            return pa && !pb
        }
        for index in nearFirst {
            let node = f.map.graph.nodes[index]
            let isNeighbor = f.neighbors?.contains(index) ?? false
            let isHit = f.matches?.contains(index) ?? false
            let isHub = f.hubs.contains(index) && zoom >= 0.9 && f.focus == nil && f.projected[index].depth > -0.2
            let show = isNeighbor || isHit || isHub || (zoom >= 2.2 && node.lines > 150) || zoom >= 3.5
            guard show, f.map.linked[index] || isHit || index == f.focus else { continue }
            let p = f.projected[index]
            let radius = nodeRadius(f.map, index, p)
            let isFocus = index == f.focus
            let at = CGPoint(x: p.point.x, y: p.point.y + radius + 9)
            let width = CGFloat(node.name.count) * (isFocus ? 7.2 : 6.2) + 6
            let box = CGRect(x: at.x - width / 2, y: at.y - 8, width: width, height: 16)
            if !isFocus, !isHit, index != pathEnd, taken.contains(where: { $0.intersects(box) }) { continue }
            taken.append(box)
            // A dark edge under the text keeps it readable over the links.
            graphics.draw(Text(node.name).font(.mono(isFocus ? 11.5 : 10, isFocus ? .semibold : .regular)).foregroundColor(Palette.background.opacity(0.9)),
                          at: CGPoint(x: at.x + 1, y: at.y + 1), anchor: .center)
            graphics.draw(Text(node.name).font(.mono(isFocus ? 11.5 : 10, isFocus ? .semibold : .regular))
                            .foregroundColor(isFocus ? Palette.cream : Palette.text.opacity(0.5 + 0.5 * fog(p.depth))),
                          at: at, anchor: .center)
        }
    }

    /// The file under the pointer: the nearest on screen, the front one winning a tie.
    private func nearest(_ f: Frame, to location: CGPoint) -> Int? {
        var best: (index: Int, score: CGFloat)?
        for index in f.order {
            let p = f.projected[index]
            let distance = hypot(p.point.x - location.x, p.point.y - location.y)
            guard distance < max(9, nodeRadius(f.map, index, p) + 4) else { continue }
            let score = distance - CGFloat(p.depth) * 6
            if score < (best?.score ?? .infinity) { best = (index, score) }
        }
        return best?.index
    }

    private func resetView() {
        withAnimation(.easeOut(duration: 0.25)) {
            yaw = 0.6
            pitch = 0.35
            zoom = 1
            pan = .zero
        }
    }

    /// The group colors with "other" last.
    static let shades: [Color] = groupColors + [otherColor]

    private func colorIndex(_ map: ProjectMap, _ index: Int) -> Int {
        let group = colorBy == "clusters" ? map.cluster[index] : map.groupOf[index]
        return min(group, Self.groupColors.count)
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
            Text("drag to turn · ⌥-drag to move · scroll or pinch to zoom").font(.mono(9)).foregroundStyle(Palette.faint).padding(.top, 2)
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
                    Text(node.path)
                        .font(.mono(10)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
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
                        if target.provider.isAgent {
                        Button {
                            model.reveal(target)
                            target.type("Explain what \(node.path) does and how it fits with the files it uses and the ones that use it. ")
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
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopListening()
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
            stopListening()
            super.removeFromSuperview()
        }

        /// Removes the monitor exactly once. Removing the same one a second time
        /// (which this view used to do when closing the map) crashes the app.
        private func stopListening() {
            guard let monitor else { return }
            self.monitor = nil
            NSEvent.removeMonitor(monitor)
        }
    }

    func makeNSView(context: Context) -> View {
        let view = View()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: View, context: Context) { nsView.onScroll = onScroll }
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
            if model.projectMap?.folder != folder { model.buildProjectMap(folder) }
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
