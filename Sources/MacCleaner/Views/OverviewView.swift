import SwiftUI

struct OverviewView: View {
    @Binding var pane: Pane?
    @Environment(DiskStore.self) private var disk
    @Environment(CleanerStore.self) private var cleaner
    @Environment(ExplorerStore.self) private var explorer
    @State private var hasFDA = FS.hasFullDiskAccess

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !hasFDA { FullDiskAccessBanner() }
                if let info = disk.info { diskCard(info) }
                HStack(alignment: .top, spacing: 16) {
                    quickClean
                    biggestFolders
                }
                biggestFiles
            }
            .padding(24)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .toolbar {
            ToolbarItem {
                Button {
                    disk.refresh()
                    hasFDA = FS.hasFullDiskAccess
                    Task { await cleaner.measure() }
                    explorer.scan()
                } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .keyboardShortcut("r")
                    .help("Refresh (⌘R)")
            }
        }
    }

    // MARK: Disk

    private func diskCard(_ info: DiskInfo) -> some View {
        Card(padding: 22) {
            HStack(spacing: 28) {
                DiskRing(info: info).frame(width: 132, height: 132)
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.name).font(.title2.weight(.semibold))
                        Text("\(info.available.formattedBytes) available of \(info.total.formattedBytes)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    StackedBar(segments: [
                        .init(id: "used", value: Double(info.used), color: Palette.usage(info.usedFraction), label: "Used"),
                        .init(id: "purge", value: Double(info.purgeable), color: .gray.opacity(0.6), label: "Purgeable"),
                    ], total: Double(info.total), height: 12)
                    HStack(spacing: 22) {
                        stat("Used", info.used, Palette.usage(info.usedFraction))
                        stat("Purgeable", info.purgeable, .gray, help: "Space macOS frees up on its own when it needs it (Time Machine snapshots, iCloud files…)")
                        stat("Free", info.free, Color(nsColor: .quaternaryLabelColor))
                    }
                }
            }
        }
    }

    private func stat(_ label: String, _ value: Int64, _ color: Color, help: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value.formattedBytes).font(.body.weight(.medium)).monospacedDigit()
            }
        }
        .help(help ?? "")
    }

    // MARK: Quick clean

    private var quickClean: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Safe to Reclaim", symbol: "sparkles")
                if cleaner.isMeasuring && cleaner.safeBytes == 0 {
                    ProgressView().controlSize(.small)
                } else {
                    Text(cleaner.safeBytes.formattedBytes)
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                Text("Caches, logs, Trash and developer caches. Everything is recreated automatically.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(topSafe, id: \.0.id) { t, bytes in
                        HStack {
                            Image(systemName: t.symbol).frame(width: 18).foregroundStyle(t.section.tint)
                            Text(t.title).lineLimit(1)
                            Spacer()
                            Text(bytes.formattedBytes).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                }
                Spacer(minLength: 0)
                HStack {
                    Button {
                        cleaner.selectSafe()
                        Task { await cleaner.clean(disk: disk) }
                    } label: {
                        Label(cleaner.isCleaning ? "Cleaning…" : "Clean Up", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(cleaner.isCleaning || cleaner.safeBytes == 0)
                    Button("Details") { pane = .clean }
                        .controlSize(.large)
                }
                if let freed = cleaner.lastFreed {
                    Label("\(freed.formattedBytes) freed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout.weight(.medium))
                }
            }
        }
        .frame(maxWidth: 360)
    }

    private var topSafe: [(CleanTarget, Int64)] {
        cleaner.targets.filter(\.defaultSelected)
            .compactMap { t in cleaner.sizes[t.id]?.bytes.map { (t, $0) } }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(4)
            .map { $0 }
    }

    // MARK: Folders

    private var biggestFolders: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "What’s Taking Up Space", symbol: "folder",
                           trailing: AnyView(Button("Explorer") { pane = .explore }.buttonStyle(.link)))
                let _ = explorer.revision
                if let root = explorer.root {
                    let kids = Array(root.children.prefix(7))
                    StackedBar(segments: kids.enumerated().map { i, n in
                        .init(id: ObjectIdentifier(n), value: Double(n.size), color: Palette.color(i), label: "\(n.name) — \(n.size.formattedBytes)")
                    }, total: Double(root.size), height: 10)
                    VStack(spacing: 7) {
                        ForEach(Array(kids.enumerated()), id: \.element.id) { i, n in
                            Button {
                                if n.canOpen { explorer.open(n) } else { explorer.current = root }
                                pane = .explore
                            } label: {
                                HStack(spacing: 8) {
                                    Circle().fill(Palette.color(i)).frame(width: 8, height: 8)
                                    NodeIcon(node: n).frame(width: 18, height: 18)
                                    Text(n.name).lineLimit(1)
                                    Spacer()
                                    Text(n.size.formattedBytes).monospacedDigit().foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text("In \(FS.pretty(root.url)) · \(root.size.formattedBytes) total")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else if explorer.isScanning {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Scanning… \(explorer.progressBytes.formattedBytes)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    Button("Scan Home Folder") { explorer.scan(.home) }
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
        }
    }

    // MARK: Files

    @ViewBuilder private var biggestFiles: some View {
        let files = Array(explorer.bigFiles.prefix(6))
        if !files.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    CardHeader(title: "Largest Files", symbol: "doc",
                               trailing: AnyView(Button("See All") { pane = .bigFiles }.buttonStyle(.link)))
                    ForEach(files) { f in
                        HStack(spacing: 10) {
                            NodeIcon(node: f).frame(width: 22, height: 22)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(f.name).lineLimit(1).truncationMode(.middle)
                                Text(FS.pretty(f.url.deletingLastPathComponent()))
                                    .font(.caption).foregroundStyle(.tertiary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            Text(f.size.formattedBytes).monospacedDigit()
                            Button { FS.reveal([f.url]) } label: { Image(systemName: "magnifyingglass") }
                                .buttonStyle(.borderless)
                                .help("Show in Finder")
                        }
                        .draggable(f.url)
                    }
                }
            }
        }
    }
}
