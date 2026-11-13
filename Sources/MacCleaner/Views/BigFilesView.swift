import SwiftUI

enum FileKind: String, CaseIterable, Identifiable {
    case all, video, archive, image, audio, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .video: "Videos"
        case .archive: "Archives & Installers"
        case .image: "Images"
        case .audio: "Audio"
        case .other: "Other"
        }
    }

    private static let map: [FileKind: Set<String>] = [
        .video: ["mp4", "mov", "m4v", "mkv", "avi", "webm", "mts", "prores", "braw"],
        .archive: ["zip", "dmg", "pkg", "iso", "tar", "gz", "tgz", "bz2", "xz", "rar", "7z", "xip", "ipsw", "img", "dump", "sql", "bak"],
        .image: ["jpg", "jpeg", "png", "heic", "tif", "tiff", "psd", "psb", "raw", "cr2", "cr3", "nef", "arw", "dng", "ai", "sketch", "fig"],
        .audio: ["mp3", "wav", "aif", "aiff", "flac", "m4a", "aac", "logicx"],
    ]

    func matches(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        switch self {
        case .all: return true
        case .other: return !Self.map.values.contains { $0.contains(ext) }
        default: return Self.map[self]?.contains(ext) ?? false
        }
    }
}

struct BigFilesView: View {
    @Binding var pane: Pane?
    @Environment(ExplorerStore.self) private var explorer
    @Environment(DiskStore.self) private var disk
    @State private var selection = Set<FileNode.ID>()
    @State private var kind: FileKind = .all
    @State private var search = ""
    @State private var pendingTrash: [FileNode] = []
    @State private var sortOrder = [KeyPathComparator(\FileNode.size, order: .reverse)]

    private var rows: [FileNode] {
        let _ = explorer.revision
        return explorer.bigFiles
            .filter { kind.matches($0.url) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
            .sorted(using: sortOrder)
    }

    var body: some View {
        Group {
            if explorer.isScanning {
                ScanningView()
            } else if explorer.root == nil {
                EmptyState(symbol: "doc.badge.ellipsis", title: "Largest Files",
                           message: "Run a scan to list every file larger than 50 MB.",
                           action: ("Scan Home Folder", { explorer.scan(.home) }))
            } else {
                VStack(spacing: 0) {
                    filterBar
                    Divider()
                    table
                }
            }
        }
        .toolbar { ScanToolbar() }
        .searchable(text: $search, placement: .toolbar, prompt: "Search Files")
        .trashConfirmation($pendingTrash) { nodes in
            explorer.moveToTrash(nodes)
            selection = []
            disk.refresh()
        }
    }

    private var filterBar: some View {
        let list = rows
        let total = list.reduce(Int64(0)) { $0 + $1.size }
        return HStack {
            Picker("Type", selection: $kind) {
                ForEach(FileKind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer()
            Text("\(list.count) files · \(total.formattedBytes)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var table: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { f in
                HStack(spacing: 8) {
                    NodeIcon(node: f).frame(width: 18, height: 18)
                    Text(f.name).lineLimit(1).truncationMode(.middle)
                }
                .draggable(f.url)
            }
            .width(min: 180, ideal: 300)
            TableColumn("Location") { f in
                Text(FS.pretty(f.url.deletingLastPathComponent()))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .width(min: 140, ideal: 280)
            TableColumn("Modified", value: \.modifiedSortKey) { f in
                Text(f.modified?.formatted(date: .abbreviated, time: .omitted) ?? "—")
                    .foregroundStyle(.secondary)
            }
            .width(100)
            TableColumn("Size", value: \.size) { f in
                Text(f.size.formattedBytes).monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(90)
        }
        .contextMenu(forSelectionType: FileNode.ID.self) { ids in
            let items = explorer.bigFiles.filter { ids.contains($0.id) }
            if !items.isEmpty {
                Button("Open") { items.forEach { NSWorkspace.shared.open($0.url) } }
                Button("Show in Finder") { FS.reveal(items.map(\.url)) }
                Button("Show in Explorer") {
                    if let parent = explorer.node(for: items[0].url.deletingLastPathComponent()) {
                        explorer.open(parent)
                        pane = .explore
                    }
                }
                Button("Copy Path") { FS.copyToPasteboard(items.map(\.url.path).joined(separator: "\n")) }
                Divider()
                Button("Move to Trash", role: .destructive) { pendingTrash = items }
            }
        } primaryAction: { ids in
            FS.reveal(explorer.bigFiles.filter { ids.contains($0.id) }.map(\.url))
        }
        .onDeleteCommand { pendingTrash = explorer.bigFiles.filter { selection.contains($0.id) } }
    }
}

extension FileNode {
    var modifiedSortKey: Date { modified ?? .distantPast }
}
