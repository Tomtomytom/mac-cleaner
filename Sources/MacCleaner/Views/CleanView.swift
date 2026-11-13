import SwiftUI

struct CleanView: View {
    @Environment(CleanerStore.self) private var cleaner
    @Environment(DiskStore.self) private var disk
    @State private var confirming = false
    @State private var toast: String?

    var body: some View {
        List {
            ForEach(CleanSection.allCases) { section in
                let items = cleaner.targets(in: section)
                if !items.isEmpty {
                    Section {
                        ForEach(items) { CleanRow(target: $0) }
                    } header: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(section.title).font(.headline).foregroundStyle(.primary)
                            Text(section.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 2)
                    }
                }
            }
        }
        .listStyle(.inset)
        .overlay {
            if cleaner.targets.isEmpty { ProgressView("Looking for things to clean up…") }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .overlay(alignment: .bottom) {
            if let toast {
                Toast(text: toast)
                    .padding(.bottom, 84)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: toast)
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Button("Select Safe Items") { cleaner.selectSafe() }
                    Button("Select All") { cleaner.selected = Set(cleaner.targets.map(\.id)) }
                        .keyboardShortcut("a")
                    Button("Deselect All") { cleaner.selected = [] }
                } label: { Label("Selection", systemImage: "checklist") }
                Button {
                    Task { await cleaner.measure() }
                } label: { Label("Recalculate", systemImage: "arrow.clockwise") }
                    .keyboardShortcut("r")
                    .help("Recalculate Sizes (⌘R)")
                    .disabled(cleaner.isMeasuring || cleaner.isCleaning)
            }
        }
        .confirmationDialog(confirmTitle, isPresented: $confirming) {
            Button("Clean Up", role: .destructive) { run() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmMessage)
        }
        .onChange(of: cleaner.lastFreed) { _, freed in
            guard let freed else { return }
            toast = freed > 0 ? "\(freed.formattedBytes) freed" : "Cleanup complete"
            Task {
                try? await Task.sleep(for: .seconds(4))
                toast = nil
            }
        }
    }

    private var chosen: [CleanTarget] { cleaner.targets.filter { cleaner.selected.contains($0.id) } }

    private var confirmTitle: String {
        chosen.count == 1 ? "Clean Up “\(chosen[0].title)”?" : "Clean Up \(chosen.count) Items?"
    }

    private var confirmMessage: String {
        var lines = ["Files are deleted permanently, without going to the Trash."]
        if chosen.contains(where: \.caution) { lines.append("Some items marked “Caution” aren’t recreated automatically.") }
        if chosen.contains(where: \.isAdmin) { lines.append("You’ll be asked for your administrator password once.") }
        return lines.joined(separator: "\n\n")
    }

    private func run() {
        Task { await cleaner.clean(disk: disk) }
    }

    private var bottomBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text(cleaner.selected.isEmpty ? "Nothing selected" :
                        cleaner.selected.count == 1 ? "1 item selected" : "\(cleaner.selected.count) items selected")
                    .font(.callout.weight(.medium))
                Text("≈ \(cleaner.selectedBytes.formattedBytes) to reclaim")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            if cleaner.isCleaning { ProgressView().controlSize(.small) }
            Button {
                confirming = true
            } label: {
                Label(cleaner.isCleaning ? "Cleaning…" : "Clean Up", systemImage: "sparkles")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(cleaner.selected.isEmpty || cleaner.isCleaning)
            .help("Clean Up Selection (⌘↩)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

struct CleanRow: View {
    let target: CleanTarget
    @Environment(CleanerStore.self) private var cleaner
    @State private var showCommand = false

    private var isOn: Binding<Bool> {
        Binding(
            get: { cleaner.selected.contains(target.id) },
            set: { on in
                if on { cleaner.selected.insert(target.id) } else { cleaner.selected.remove(target.id) }
            })
    }

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: isOn).toggleStyle(.checkbox).labelsHidden()
            IconTile(symbol: target.symbol, tint: target.section.tint)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(target.title).font(.body.weight(.medium))
                    if target.caution { Badge(text: "Caution", tint: .orange, symbol: "exclamationmark.triangle.fill") }
                    if target.isAdmin { Badge(text: "Admin", tint: .secondary, symbol: "lock.fill") }
                }
                if let s = cleaner.status[target.id] {
                    Label(s.text, systemImage: s.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .font(.callout)
                        .foregroundStyle(s.ok ? .green : .red)
                        .lineLimit(2)
                } else {
                    Text(target.detail).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 12)
            sizeLabel
            Button { showCommand.toggle() } label: {
                Image(systemName: "terminal")
            }
            .buttonStyle(.borderless)
            .help("Show Equivalent Command")
            .popover(isPresented: $showCommand, arrowEdge: .trailing) {
                CommandPopover(target: target)
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture { isOn.wrappedValue.toggle() }
    }

    @ViewBuilder private var sizeLabel: some View {
        Group {
            if cleaner.runningID == target.id {
                ProgressView().controlSize(.small)
            } else {
                switch cleaner.sizes[target.id] ?? .unknown {
                case .measuring, .unknown:
                    ProgressView().controlSize(.small)
                case .value(let v):
                    Text(v.formattedBytes)
                        .monospacedDigit()
                        .foregroundStyle(v > 1_000_000_000 ? .primary : .secondary)
                        .fontWeight(v > 1_000_000_000 ? .semibold : .regular)
                case .unreadable:
                    Image(systemName: "lock")
                        .foregroundStyle(.tertiary)
                        .help("Unknown size: give Mac Cleaner Full Disk Access")
                case .info(let s):
                    Text(s).foregroundStyle(.secondary)
                case .none:
                    Text("—").foregroundStyle(.tertiary)
                }
            }
        }
        .frame(minWidth: 80, alignment: .trailing)
    }
}

struct CommandPopover: View {
    let target: CleanTarget
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Equivalent Command").font(.headline)
            Text(target.command)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
            HStack {
                Text("Paste it into Terminal if you’d rather do it by hand.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(copied ? "Copied" : "Copy") {
                    FS.copyToPasteboard(target.command)
                    copied = true
                }
            }
        }
        .padding(16)
        .frame(width: 440)
    }
}
