import SwiftUI

struct ExplorerView: View {
    @Environment(ExplorerStore.self) private var explorer
    @Environment(DiskStore.self) private var disk
    @State private var selection = Set<FileNode.ID>()
    @State private var search = ""
    @State private var pendingTrash: [FileNode] = []
    @State private var toast: String?

    var body: some View {
        let _ = explorer.revision
        Group {
            if explorer.isScanning {
                ScanningView()
            } else if let current = explorer.current {
                content(current)
            } else {
                EmptyState(symbol: "folder.badge.gearshape", title: "Find What’s Taking Up Space",
                           message: "Scan a folder to see what’s using your disk, from largest to smallest.",
                           action: ("Scan Home Folder", { explorer.scan(.home) }))
            }
        }
        .toolbar { ScanToolbar() }
        .searchable(text: $search, placement: .toolbar, prompt: "Filter This Folder")
        .overlay(alignment: .bottom) {
            if let toast { Toast(text: toast, symbol: "trash").padding(.bottom, 20).transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        .animation(.spring(duration: 0.35), value: toast)
        .trashConfirmation($pendingTrash) { nodes in
            let errors = explorer.moveToTrash(nodes)
            selection = []
            disk.refresh()
            let total = nodes.reduce(Int64(0)) { $0 + $1.size }
            show(errors.isEmpty ? "\(total.formattedBytes) moved to the Trash" : errors.joined(separator: "\n"))
        }
    }

    private func show(_ text: String) {
        toast = text
        Task { try? await Task.sleep(for: .seconds(3)); toast = nil }
    }

    private func nodes(_ ids: Set<FileNode.ID>) -> [FileNode] {
        (explorer.current?.children ?? []).filter { ids.contains($0.id) && !$0.isAggregate }
    }

    @ViewBuilder private func content(_ current: FileNode) -> some View {
        let children = search.isEmpty ? current.children
            : current.children.filter { $0.name.localizedCaseInsensitiveContains(search) }
        VStack(spacing: 0) {
            header(current)
            Divider()
            if current.unreadable {
                EmptyState(symbol: "lock", title: "Protected Folder",
                           message: "macOS doesn’t let Mac Cleaner read this folder. Give it Full Disk Access in Settings.",
                           action: ("Open Settings", FS.openFullDiskAccessSettings))
            } else if children.isEmpty {
                EmptyState(symbol: "tray", title: search.isEmpty ? "Empty Folder" : "No Results", message: "")
            } else {
                List(selection: $selection) {
                    ForEach(Array(children.enumerated()), id: \.element.id) { i, node in
                        NodeRow(node: node, total: current.size, color: Palette.color(i))
                            .tag(node.id)
                            .draggable(node.url)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .contextMenu(forSelectionType: FileNode.ID.self) { ids in
                    contextMenu(nodes(ids))
                } primaryAction: { ids in
                    if let n = nodes(ids).first {
                        if n.canOpen { explorer.open(n); selection = [] } else { NSWorkspace.shared.open(n.url) }
                    }
                }
                .onDeleteCommand { pendingTrash = nodes(selection) }
            }
        }
    }

    @ViewBuilder private func contextMenu(_ items: [FileNode]) -> some View {
        if !items.isEmpty {
            if items.count == 1, items[0].canOpen {
                Button("Open") { explorer.open(items[0]); selection = [] }
            }
            Button("Show in Finder") { FS.reveal(items.map(\.url)) }
            Button("Copy Path") { FS.copyToPasteboard(items.map(\.url.path).joined(separator: "\n")) }
            Divider()
            Button("Move to Trash", role: .destructive) { pendingTrash = items }
        }
    }

    private func header(_ current: FileNode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Button { explorer.goUp(); selection = [] } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                    .disabled(current.parent == nil)
                    .keyboardShortcut(.upArrow, modifiers: .command)
                    .help("Enclosing Folder (⌘↑)")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(Array(explorer.path.enumerated()), id: \.element.id) { i, n in
                            if i > 0 { Image(systemName: "chevron.compact.right").foregroundStyle(.tertiary) }
                            Button(n.name) {
                                explorer.current = n
                                explorer.revision += 1
                                selection = []
                            }
                            .buttonStyle(.plain)
                            .fontWeight(n === current ? .semibold : .regular)
                            .foregroundStyle(n === current ? .primary : .secondary)
                            .padding(.horizontal, 4)
                        }
                    }
                }
                Spacer()
                Text(current.size.formattedBytes)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
            StackedBar(
                segments: current.children.prefix(10).enumerated().map { i, n in
                    .init(id: ObjectIdentifier(n), value: Double(n.size), color: Palette.color(i), label: "\(n.name) — \(n.size.formattedBytes)")
                },
                total: Double(current.size), height: 14
            ) { id in
                if let n = current.children.first(where: { AnyHashable(ObjectIdentifier($0)) == id }), n.canOpen {
                    explorer.open(n)
                    selection = []
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

struct NodeRow: View {
    let node: FileNode
    let total: Int64
    let color: Color

    var body: some View {
        let fraction = total > 0 ? Double(node.size) / Double(total) : 0
        HStack(spacing: 10) {
            NodeIcon(node: node).frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(node.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(node.isAggregate ? .secondary : .primary)
                if node.isDirectory {
                    Text(node.unreadable ? "Access denied" : node.itemCount == 1 ? "1 file" : "\(node.itemCount.formatted()) files")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 16)
            ProportionBar(fraction: fraction, color: color).frame(width: 130)
            Text(fraction < 0.001 ? "<0.1%" : fraction.formatted(.percent.precision(.fractionLength(fraction < 0.1 ? 1 : 0))))
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 52, alignment: .trailing)
            Text(node.size.formattedBytes)
                .monospacedDigit()
                .frame(width: 84, alignment: .trailing)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .opacity(node.canOpen ? 1 : 0)
        }
        .padding(.vertical, 3)
    }
}

/// Toolbar shared by Explorer and Big files: what to scan + rescan.
struct ScanToolbar: ToolbarContent {
    @Environment(ExplorerStore.self) private var explorer

    var body: some ToolbarContent {
        ToolbarItemGroup {
            Menu {
                Button { explorer.scan(.home) } label: { Label("Home Folder", systemImage: "house") }
                Button { explorer.scan(.disk) } label: { Label("Entire Disk", systemImage: "internaldrive") }
                Divider()
                Button { explorer.chooseFolder() } label: { Label("Choose Folder…", systemImage: "folder") }
                    .keyboardShortcut("o")
            } label: {
                Label(rootTitle, systemImage: "scope")
            }
            .help("Choose What to Scan")
            Button { explorer.scan() } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                .keyboardShortcut("r")
                .help("Rescan (⌘R)")
                .disabled(explorer.isScanning)
        }
    }

    private var rootTitle: String {
        switch explorer.scanRoot {
        case .home: "Home Folder"
        case .disk: "Entire Disk"
        case .custom(let u): u.lastPathComponent
        }
    }
}

extension View {
    /// Confirmation before moving items to the Trash.
    func trashConfirmation(_ pending: Binding<[FileNode]>, perform: @escaping ([FileNode]) -> Void) -> some View {
        let items = pending.wrappedValue
        let total = items.reduce(Int64(0)) { $0 + $1.size }
        let title = items.count == 1 ? "Move “\(items[0].name)” to the Trash?" : "Move \(items.count) Items to the Trash?"
        return confirmationDialog(title, isPresented: Binding(get: { !pending.wrappedValue.isEmpty }, set: { if !$0 { pending.wrappedValue = [] } })) {
            Button("Move to Trash", role: .destructive) { perform(items) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(total.formattedBytes). You can still recover them from the Trash; empty the Trash to free up the space.")
        }
    }
}
