import SwiftUI

// MARK: - DuplicateFinderView

struct DuplicateFinderView: View {
    @StateObject private var vm = DuplicateFinderViewModel()
    @State private var choosingFolder = false
    @State private var confirmingTrash = false

    private let accent = [Color(hex: "00C9A7"), Color(hex: "00BFFF")]

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            Divider().background(Theme.border)
            if vm.scanning {
                scanningView
            } else if vm.stage == .done {
                resultsView
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
        .confirmationDialog("Move \(vm.selection.count) item(s) to Trash?",
                            isPresented: $confirmingTrash, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) { vm.trashSelected() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Items go to the Trash and can be restored. Frees \(byteString(vm.selectedBytes)).")
        }
    }

    // MARK: Controls

    private var controlBar: some View {
        HStack(spacing: 10) {
            Button { vm.scanHome() } label: {
                Label("Home Folder", systemImage: "house.fill").font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(PillButtonStyle(gradient: accent)).disabled(vm.scanning)

            Button { choosingFolder = true } label: {
                Label("Choose…", systemImage: "folder").font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(GhostPillStyle()).disabled(vm.scanning)

            Spacer()

            HStack(spacing: 6) {
                Text("Min size").font(.system(size: 11)).foregroundColor(Theme.secondaryText)
                Stepper(value: $vm.minSizeMB, in: 0.1...1000, step: vm.minSizeMB < 10 ? 0.5 : 10) {
                    Text(vm.minSizeMB < 1 ? String(format: "%.1f MB", vm.minSizeMB) : String(format: "%.0f MB", vm.minSizeMB))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.primaryText)
                        .frame(width: 56)
                }
                .disabled(vm.scanning)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    // MARK: Scanning

    private var scanningView: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView().controlSize(.large)
            Text(vm.stage.rawValue).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.primaryText)
            Text("\(vm.filesSeen.formatted()) files · \(byteString(vm.bytesSeen))")
                .font(.system(size: 12)).foregroundColor(Theme.secondaryText)
            if vm.stage == .hashing {
                ProgressView(value: vm.hashProgress).frame(width: 240).tint(accent[0])
            }
            Button { vm.cancel() } label: { Text("Cancel").font(.system(size: 12, weight: .semibold)) }
                .buttonStyle(GhostPillStyle())
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Results

    private var resultsView: some View {
        VStack(spacing: 0) {
            resultsHeader
            Divider().background(Theme.border)
            ScrollView {
                LazyVStack(spacing: 10) {
                    if vm.mode == .duplicates {
                        if vm.groups.isEmpty {
                            noResults("No duplicates found", "Every file under \(vm.scanRootName) is unique.")
                        } else {
                            ForEach(vm.groups) { group in
                                DuplicateGroupCard(group: group, accent: accent,
                                                   selection: vm.selection,
                                                   onToggle: { vm.toggle($0) },
                                                   onReveal: { vm.revealInFinder($0) },
                                                   byteString: byteString)
                            }
                        }
                    } else {
                        ForEach(vm.largest) { file in
                            LargeFileRow(file: file, selected: vm.selection.contains(file.id),
                                         accent: accent,
                                         onToggle: { vm.toggle(file.id) },
                                         onReveal: { vm.revealInFinder(file) },
                                         byteString: byteString)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: 980)
                .frame(maxWidth: .infinity)
            }
            if !vm.selection.isEmpty { trashBar }
        }
    }

    private var resultsHeader: some View {
        HStack(spacing: 12) {
            Picker("", selection: $vm.mode) {
                ForEach(DuplicateFinderViewModel.Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).frame(width: 260).labelsHidden()

            Spacer()

            if vm.mode == .duplicates {
                Text("\(vm.groups.count) groups · \(byteString(vm.totalWasted)) reclaimable")
                    .font(.system(size: 11, weight: .medium)).foregroundColor(Theme.secondaryText)
                Button { vm.autoSelectDuplicates() } label: {
                    Label("Select extras", systemImage: "checklist").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(GhostPillStyle()).disabled(vm.groups.isEmpty)
            } else {
                Text("\(vm.largest.count) largest files").font(.system(size: 11, weight: .medium)).foregroundColor(Theme.secondaryText)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
    }

    private var trashBar: some View {
        HStack {
            Text("\(vm.selection.count) selected · \(byteString(vm.selectedBytes))")
                .font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.primaryText)
            Spacer()
            Button { vm.selection.removeAll() } label: { Text("Clear").font(.system(size: 12, weight: .medium)) }
                .buttonStyle(GhostPillStyle())
            Button { confirmingTrash = true } label: {
                Label("Move to Trash", systemImage: "trash.fill").font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(PillButtonStyle(gradient: [Color(hex: "E53935"), Color(hex: "FF6B35")]))
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(Theme.card)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.border), alignment: .top)
    }

    // MARK: Empty / no-result

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: accent, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 84, height: 84).shadow(color: accent[0].opacity(0.4), radius: 16, y: 8)
                Image(systemName: "doc.on.doc.fill").font(.system(size: 34, weight: .semibold)).foregroundColor(.white)
            }
            Text("Find duplicates & big files").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundColor(Theme.primaryText)
            Text("Scan a folder to find identical files and your largest space hogs.")
                .font(.system(size: 13)).foregroundColor(Theme.secondaryText).multilineTextAlignment(.center).frame(maxWidth: 360)
            Button { vm.scanHome() } label: {
                Label("Scan Home Folder", systemImage: "play.fill").font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(PillButtonStyle(gradient: accent))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func noResults(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 32)).foregroundColor(Color(hex: "3FB950"))
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.primaryText)
            Text(subtitle).font(.system(size: 12)).foregroundColor(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 60)
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Rows

struct DuplicateGroupCard: View {
    let group: DuplicateGroup
    let accent: [Color]
    let selection: Set<UUID>
    let onToggle: (UUID) -> Void
    let onReveal: (FileItem) -> Void
    let byteString: (Int64) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("\(group.files.count)×").font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: accent, startPoint: .leading, endPoint: .trailing))
                Text(byteString(group.size) + " each").font(.system(size: 11)).foregroundColor(Theme.secondaryText)
                Spacer()
                Text(byteString(group.wasted) + " reclaimable").font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.primaryText)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            Divider().background(Theme.border)
            ForEach(group.files) { file in
                FileRow(file: file, selected: selection.contains(file.id), accent: accent,
                        onToggle: { onToggle(file.id) }, onReveal: { onReveal(file) }, byteString: byteString)
                if file.id != group.files.last?.id { Divider().background(Theme.border).padding(.leading, 38) }
            }
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

struct FileRow: View {
    let file: FileItem
    let selected: Bool
    let accent: [Color]
    let onToggle: () -> Void
    let onReveal: () -> Void
    let byteString: (Int64) -> String

    var body: some View {
        HStack(spacing: 10) {
            CheckCircle(selected: selected, accent: accent, onToggle: onToggle)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.url.lastPathComponent).font(.system(size: 12, weight: .medium)).foregroundColor(Theme.primaryText).lineLimit(1)
                Text(file.url.deletingLastPathComponent().path).font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.secondaryText).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button(action: onReveal) { Image(systemName: "magnifyingglass").font(.system(size: 10, weight: .semibold)) }
                .buttonStyle(.plain).foregroundColor(Theme.secondaryText)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
    }
}

struct LargeFileRow: View {
    let file: FileItem
    let selected: Bool
    let accent: [Color]
    let onToggle: () -> Void
    let onReveal: () -> Void
    let byteString: (Int64) -> String

    var body: some View {
        HStack(spacing: 10) {
            CheckCircle(selected: selected, accent: accent, onToggle: onToggle)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.url.lastPathComponent).font(.system(size: 12, weight: .medium)).foregroundColor(Theme.primaryText).lineLimit(1)
                Text(file.url.deletingLastPathComponent().path).font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.secondaryText).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(byteString(file.size)).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(Theme.primaryText)
            Button(action: onReveal) { Image(systemName: "magnifyingglass").font(.system(size: 10, weight: .semibold)) }
                .buttonStyle(.plain).foregroundColor(Theme.secondaryText)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.border, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
    }
}

struct CheckCircle: View {
    let selected: Bool
    let accent: [Color]
    let onToggle: () -> Void
    var body: some View {
        Button(action: onToggle) {
            ZStack {
                Circle().stroke(selected ? Color.clear : Theme.border, lineWidth: 1.5).frame(width: 18, height: 18)
                if selected {
                    Circle().fill(LinearGradient(colors: accent, startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 18, height: 18)
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundColor(.white)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
