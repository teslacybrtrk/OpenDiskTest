import SwiftUI

// MARK: - CleanupView

struct CleanupView: View {
    @StateObject private var vm = CleanupViewModel()
    @State private var confirming = false

    private let accent = [Color(hex: "FFB300"), Color(hex: "FF6B35")]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Theme.border)
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(vm.categories) { cat in
                        CleanupRow(category: cat,
                                   size: vm.sizes[cat.id],
                                   scanning: vm.scanning && vm.sizes[cat.id] == nil,
                                   selected: vm.selection.contains(cat.id),
                                   accent: accent,
                                   onToggle: { vm.toggle(cat.id) },
                                   byteString: byteString)
                    }
                }
                .padding(16)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)

                if let cleaned = vm.lastCleaned {
                    Label("Reclaimed \(byteString(cleaned))", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "3FB950"))
                        .padding(.bottom, 10)
                }
            }
            if !vm.selection.isEmpty { actionBar }
        }
        .background(Theme.background)
        .onAppear { if vm.sizes.isEmpty { vm.scan() } }
        .onDisappear { vm.cancel() }
        .confirmationDialog(confirmTitle, isPresented: $confirming, titleVisibility: .visible) {
            Button(hasPermanent ? "Clean & Empty Trash" : "Move to Trash", role: .destructive) { vm.clean() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmMessage)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Reclaimable space")
                    .font(.system(size: 12, weight: .medium)).foregroundColor(Theme.secondaryText)
                Text(byteString(vm.totalReclaimable))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: accent, startPoint: .leading, endPoint: .trailing))
                    .contentTransition(.numericText())
            }
            Spacer()
            if vm.scanning {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("Scanning \(vm.scannedCount)/\(vm.categories.count)…")
                        .font(.system(size: 11)).foregroundColor(Theme.secondaryText)
                }
            } else {
                Button { vm.scan() } label: {
                    Label("Rescan", systemImage: "arrow.clockwise").font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(GhostPillStyle())
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .animation(.easeOut(duration: 0.25), value: vm.totalReclaimable)
    }

    private var actionBar: some View {
        HStack {
            Text("\(vm.selection.count) selected · \(byteString(vm.selectedBytes))")
                .font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.primaryText)
            Spacer()
            Button { vm.selection.removeAll() } label: { Text("Clear").font(.system(size: 12, weight: .medium)) }
                .buttonStyle(GhostPillStyle())
            Button { confirming = true } label: {
                Label(hasPermanent ? "Clean Up" : "Move to Trash",
                      systemImage: "sparkles").font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(PillButtonStyle(gradient: accent))
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(Theme.card)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.border), alignment: .top)
    }

    private var hasPermanent: Bool {
        vm.categories.contains { vm.selection.contains($0.id) && $0.permanent }
    }
    private var confirmTitle: String {
        hasPermanent ? "Clean up and empty Trash?" : "Move \(byteString(vm.selectedBytes)) to Trash?"
    }
    private var confirmMessage: String {
        hasPermanent
        ? "Selected items move to the Trash and can be restored — but emptying the Trash is permanent."
        : "Items move to the Trash and can be restored. Frees \(byteString(vm.selectedBytes)) once the Trash is emptied."
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Row

struct CleanupRow: View {
    let category: CleanupCategory
    let size: Int64?
    let scanning: Bool
    let selected: Bool
    let accent: [Color]
    let onToggle: () -> Void
    let byteString: (Int64) -> String

    var body: some View {
        HStack(spacing: 12) {
            CheckCircle(selected: selected, accent: accent, onToggle: onToggle)
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient(colors: accent, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 34, height: 34)
                    .opacity(category.permanent ? 1 : 0.9)
                Image(systemName: category.icon).font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(category.name).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.primaryText)
                    if category.permanent {
                        Text("PERMANENT").font(.system(size: 8, weight: .bold))
                            .foregroundColor(Color(hex: "F85149"))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color(hex: "F85149").opacity(0.15)).clipShape(Capsule())
                    }
                }
                Text(category.blurb).font(.system(size: 11)).foregroundColor(Theme.secondaryText).lineLimit(2)
                if let caution = category.caution {
                    Label(caution, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10)).foregroundColor(Color(hex: "D29922")).lineLimit(2)
                }
            }
            Spacer()
            if scanning {
                ProgressView().controlSize(.small)
            } else {
                Text(byteString(size ?? 0))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor((size ?? 0) > 0 ? Theme.primaryText : Theme.secondaryText)
            }
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(selected ? accent[0].opacity(0.5) : Theme.border, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
    }
}
