import SwiftUI
import UniformTypeIdentifiers

// MARK: - SpaceAnalyzerView

struct SpaceAnalyzerView: View {
    @StateObject private var vm = SpaceAnalyzerViewModel()
    @State private var choosingFolder = false

    private let accent = [Color(hex: "FF6B35"), Color(hex: "FF2D78")]

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            Divider().background(Theme.border)

            if vm.scanning {
                scanningView
            } else if let result = vm.result, let node = vm.currentNode {
                analyzerView(result: result, node: node)
            } else {
                emptyState
            }
        }
        .background(Theme.background)
        .onDisappear { vm.cancel() }
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                _ = url.startAccessingSecurityScopedResource()
                vm.scan(url)
            }
        }
    }

    // MARK: Controls

    private var controlBar: some View {
        HStack(spacing: 10) {
            Button { vm.scanHome() } label: {
                Label("Home Folder", systemImage: "house.fill")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(PillButtonStyle(gradient: accent))
            .disabled(vm.scanning)

            Button { vm.scanWholeDisk() } label: {
                Label("Whole Disk", systemImage: "internaldrive")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(GhostPillStyle())
            .disabled(vm.scanning)
            .help("Scanning the whole disk may require Full Disk Access in System Settings › Privacy & Security.")

            Button { choosingFolder = true } label: {
                Label("Choose…", systemImage: "folder")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(GhostPillStyle())
            .disabled(vm.scanning)

            Spacer()

            Toggle(isOn: $vm.includeHidden) {
                Text("Hidden files").font(.system(size: 11))
            }
            .toggleStyle(.checkbox)
            .disabled(vm.scanning)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: Scanning

    private var scanningView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView().controlSize(.large)
            Text("Scanning \(vm.scanRootName)…")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.primaryText)
            VStack(spacing: 4) {
                Text("\(vm.progress.filesScanned.formatted()) files · \(byteString(vm.progress.bytesScanned))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.secondaryText)
                Text(vm.progress.currentPath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: 460)
                if vm.progress.skippedCount > 0 {
                    Text("\(vm.progress.skippedCount) items skipped (permission)")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "D29922"))
                }
            }
            Button { vm.cancel() } label: {
                Text("Cancel").font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(GhostPillStyle())
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Result

    private func analyzerView(result: ScanResult, node: ScanNode) -> some View {
        VStack(spacing: 0) {
            breadcrumbBar(result: result)
            Divider().background(Theme.border)
            GeometryReader { geo in
                TreemapCanvas(node: node, accent: accent, selected: vm.selected) { tapped in
                    if tapped.isDirectory && !tapped.isBundle && !tapped.children.isEmpty {
                        vm.drillInto(tapped)
                    } else {
                        vm.selected = (vm.selected === tapped) ? nil : tapped
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .padding(12)
            if let sel = vm.selected {
                detailBar(sel)
            }
        }
    }

    private func breadcrumbBar(result: ScanResult) -> some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(vm.breadcrumbs.enumerated()), id: \.element.id) { index, crumb in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(Theme.secondaryText)
                        }
                        Button { vm.goTo(breadcrumbIndex: index) } label: {
                            Text(crumb.name)
                                .font(.system(size: 11, weight: index == vm.breadcrumbs.count - 1 ? .semibold : .medium))
                                .foregroundColor(index == vm.breadcrumbs.count - 1 ? Theme.primaryText : Theme.secondaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer()
            if result.skipped.count > 0 {
                Label("\(result.skipped.count) skipped", systemImage: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "D29922"))
                    .help("Some folders couldn't be read. Grant Full Disk Access for complete coverage.")
            }
            Text(byteString((vm.currentNode ?? result.root).size))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(LinearGradient(colors: accent, startPoint: .leading, endPoint: .trailing))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private func detailBar(_ node: ScanNode) -> some View {
        HStack(spacing: 12) {
            Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                .foregroundColor(accent[0])
            VStack(alignment: .leading, spacing: 1) {
                Text(node.name).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.primaryText).lineLimit(1)
                Text(node.url.path).font(.system(size: 10, design: .monospaced)).foregroundColor(Theme.secondaryText)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(byteString(node.size)).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(Theme.primaryText)
            Button { vm.revealInFinder(node) } label: {
                Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(GhostPillStyle())
            .help("Reveal in Finder")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Theme.card)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.border), alignment: .top)
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: accent, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 84, height: 84)
                    .shadow(color: accent[0].opacity(0.4), radius: 16, y: 8)
                Image(systemName: "chart.pie.fill").font(.system(size: 36, weight: .semibold)).foregroundColor(.white)
            }
            Text("Analyze your storage")
                .font(.system(size: 18, weight: .bold, design: .rounded)).foregroundColor(Theme.primaryText)
            Text("Scan a folder to see what's using space in an interactive treemap.")
                .font(.system(size: 13)).foregroundColor(Theme.secondaryText)
                .multilineTextAlignment(.center).frame(maxWidth: 360)
            Button { vm.scanHome() } label: {
                Label("Scan Home Folder", systemImage: "play.fill").font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(PillButtonStyle(gradient: accent))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Treemap Canvas

struct TreemapCanvas: View {
    let node: ScanNode
    let accent: [Color]
    let selected: ScanNode?
    let onTap: (ScanNode) -> Void

    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)
            let tiles = Treemap.layout(node.sortedChildren, in: rect)
            Canvas { ctx, _ in
                for (i, tile) in tiles.enumerated() {
                    drawTile(ctx: ctx, tile: tile, index: i, total: tiles.count)
                }
            }
            .gesture(SpatialTapGesture().onEnded { value in
                if let hit = tiles.first(where: { $0.rect.contains(value.location) }) {
                    onTap(hit.node)
                }
            })
        }
    }

    private func drawTile(ctx: GraphicsContext, tile: TreemapTile, index: Int, total: Int) {
        let inset = tile.rect.insetBy(dx: 1, dy: 1)
        guard inset.width > 0, inset.height > 0 else { return }
        let path = Path(roundedRect: inset, cornerRadius: 3)
        let base = color(index: index, total: total)
        let isSelected = selected === tile.node

        ctx.fill(path, with: .linearGradient(
            Gradient(colors: [base.opacity(0.95), base.opacity(0.7)]),
            startPoint: inset.origin,
            endPoint: CGPoint(x: inset.maxX, y: inset.maxY)))
        if isSelected {
            ctx.stroke(path, with: .color(.white), lineWidth: 2)
        }

        // Label if the tile is large enough.
        if inset.width > 54, inset.height > 26 {
            let name = tile.node.name
            let sizeStr = ByteCountFormatter.string(fromByteCount: tile.node.size, countStyle: .file)
            let title = ctx.resolve(Text(name).font(.system(size: 11, weight: .semibold)).foregroundColor(.white))
            let sub = ctx.resolve(Text(sizeStr).font(.system(size: 9)).foregroundColor(.white.opacity(0.85)))
            ctx.drawLayer { layer in
                layer.addFilter(.shadow(color: .black.opacity(0.45), radius: 1, x: 0, y: 0.5))
                layer.draw(title, at: CGPoint(x: inset.minX + 6, y: inset.minY + 12), anchor: .leading)
                if inset.height > 40 {
                    layer.draw(sub, at: CGPoint(x: inset.minX + 6, y: inset.minY + 26), anchor: .leading)
                }
            }
        }
    }

    /// Distinct vibrant color per tile using golden-angle hue rotation.
    private func color(index: Int, total: Int) -> Color {
        let hue = (Double(index) * 0.61803398875).truncatingRemainder(dividingBy: 1.0)
        return Color(hue: hue, saturation: 0.62, brightness: 0.92)
    }
}

// MARK: - Button styles

struct PillButtonStyle: ButtonStyle {
    let gradient: [Color]
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing))
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct GhostPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(Theme.primaryText)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.07))
            .clipShape(Capsule())
    }
}
