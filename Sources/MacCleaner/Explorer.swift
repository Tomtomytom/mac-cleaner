import AppKit
import Foundation
import Observation

/// One item of the scanned tree. Small files are folded into an "aggregate" node per folder.
final class FileNode: Identifiable, @unchecked Sendable {
    let url: URL
    let name: String
    let isDirectory: Bool
    var size: Int64 = 0
    var itemCount = 0
    var modified: Date?
    var children: [FileNode] = []
    weak var parent: FileNode?
    var isAggregate = false
    /// Children dropped to save memory (tiny folder) — rescanned when opened.
    var isPruned = false
    var unreadable = false

    init(url: URL, name: String, isDirectory: Bool) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
    }

    var canOpen: Bool { isDirectory && !isAggregate }
}

final class ScanProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var files = 0
    private var bytes: Int64 = 0
    private var path = ""
    private var cancelled = false
    private var big: [FileNode] = []

    func add(files f: Int, bytes b: Int64, path p: String) {
        lock.lock(); files += f; bytes += b; path = p; lock.unlock()
    }
    func addBig(_ n: FileNode) { lock.lock(); big.append(n); lock.unlock() }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func snapshot() -> (files: Int, bytes: Int64, path: String) {
        lock.lock(); defer { lock.unlock() }; return (files, bytes, path)
    }
    func bigFiles() -> [FileNode] { lock.lock(); defer { lock.unlock() }; return big }
}

enum Scanner {
    static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey, .contentModificationDateKey,
    ]
    /// Other volumes and firmlink mirrors, to avoid counting things twice when scanning "/".
    static let excluded: Set<String> = ["/System/Volumes", "/Volumes", "/dev", "/net", "/home", "/Network"]
    static let keepFile: Int64 = 1 << 20          // files ≥ 1 MB get their own row
    static let keepSubtree: Int64 = 1 << 20       // folders < 1 MB drop their subtree
    static let bigFile: Int64 = 50 * (1 << 20)    // "largest files" list
    static let maxChildren = 250

    final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var nodes: [FileNode?]
        init(_ n: Int) { nodes = .init(repeating: nil, count: n) }
        func set(_ i: Int, _ n: FileNode) { lock.lock(); nodes[i] = n; lock.unlock() }
    }

    static func scan(root: URL, progress: ScanProgress) -> (FileNode, [FileNode]) {
        let node = scanDirectory(root, progress: progress, depth: 0)
        node.parent = nil
        let big = progress.bigFiles().sorted { $0.size > $1.size }.prefix(500)
        return (node, Array(big))
    }

    static func scanDirectory(_ url: URL, progress: ScanProgress, depth: Int, minFile: Int64 = keepFile) -> FileNode {
        let node = FileNode(url: url, name: depth == 0 ? FileManager.default.displayName(atPath: url.path) : url.lastPathComponent, isDirectory: true)
        guard !progress.isCancelled else { return node }
        var children: [FileNode] = []
        var looseSize: Int64 = 0, looseCount = 0, fileCount = 0, fileBytes: Int64 = 0
        var subdirs: [URL] = []
        let keySet = Set(keys)

        // Drain the autoreleased NSURLs + cached resource values of each folder right away.
        let readable: Bool = autoreleasepool {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: []) else {
            return false
        }
        for e in entries {
            guard let v = try? e.resourceValues(forKeys: keySet), v.isSymbolicLink != true else { continue }
            if v.isDirectory == true {
                if !excluded.contains(e.path) { subdirs.append(URL(fileURLWithPath: e.path, isDirectory: true)) }
                continue
            }
            let s = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            fileCount += 1
            fileBytes += s
            if s >= minFile {
                let f = FileNode(url: e, name: e.lastPathComponent, isDirectory: false)
                f.size = s
                f.itemCount = 1
                f.modified = v.contentModificationDate
                children.append(f)
                if s >= bigFile { progress.addBig(f) }
            } else {
                looseSize += s
                looseCount += 1
            }
        }
        return true
        }
        guard readable else {
            node.unreadable = true
            return node
        }
        progress.add(files: fileCount, bytes: fileBytes, path: url.path)

        if depth < 2 && subdirs.count > 1 {
            let box = Box(subdirs.count)
            DispatchQueue.concurrentPerform(iterations: subdirs.count) { i in
                let r = scanDirectory(subdirs[i], progress: progress, depth: depth + 1)
                box.set(i, r)
            }
            children.append(contentsOf: box.nodes.compactMap { $0 })
        } else {
            for d in subdirs { children.append(scanDirectory(d, progress: progress, depth: depth + 1)) }
        }

        finalize(node, children: children, looseSize: looseSize, looseCount: looseCount)
        return node
    }

    static func finalize(_ node: FileNode, children: [FileNode], looseSize: Int64, looseCount: Int) {
        var kids = children.sorted { $0.size > $1.size }
        var loose = looseSize, lc = looseCount
        if kids.count > maxChildren {
            for k in kids[maxChildren...] { loose += k.size; lc += k.itemCount }
            kids.removeSubrange(maxChildren...)
        }
        for k in kids where k.isDirectory && k.size < keepSubtree && !k.children.isEmpty {
            k.children = []
            k.isPruned = true
        }
        if loose > 0 || lc > 0 {
            let agg = FileNode(url: node.url, name: lc == 1 ? "1 small file" : "\(lc) small files", isDirectory: false)
            agg.isAggregate = true
            agg.size = loose
            agg.itemCount = lc
            kids.append(agg)
            kids.sort { $0.size > $1.size }
        }
        node.size = kids.reduce(0) { $0 + $1.size }
        node.itemCount = kids.reduce(0) { $0 + $1.itemCount }
        for k in kids { k.parent = node }
        node.children = kids
    }
}

enum ScanRoot: Hashable {
    case home, disk, custom(URL)
    var url: URL {
        switch self {
        case .home: FS.home
        case .disk: URL(fileURLWithPath: "/")
        case .custom(let u): u
        }
    }
}

@Observable @MainActor
final class ExplorerStore {
    var root: FileNode?
    var current: FileNode?
    var bigFiles: [FileNode] = []
    var scanRoot: ScanRoot = .home
    var isScanning = false
    var progressFiles = 0
    var progressBytes: Int64 = 0
    var progressPath = ""
    var lastScan: Date?
    /// Bumped whenever the (non-observable) tree changes.
    var revision = 0

    @ObservationIgnored private var progress: ScanProgress?
    @ObservationIgnored private var poll: Timer?

    func scan(_ target: ScanRoot? = nil) {
        if let target { scanRoot = target }
        progress?.cancel()
        let p = ScanProgress()
        progress = p
        isScanning = true
        progressFiles = 0
        progressBytes = 0
        progressPath = ""
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let p = self.progress else { return }
                let s = p.snapshot()
                self.progressFiles = s.files
                self.progressBytes = s.bytes
                self.progressPath = s.path
            }
        }
        let url = scanRoot.url
        Task.detached(priority: .userInitiated) { [weak self] in
            let (node, big) = Scanner.scan(root: url, progress: p)
            await self?.finish(p, node, big)
        }
    }

    private func finish(_ p: ScanProgress, _ node: FileNode, _ big: [FileNode]) {
        guard progress === p else { return }
        poll?.invalidate()
        isScanning = false
        guard !p.isCancelled else { return }
        root = node
        current = node
        bigFiles = big
        lastScan = Date()
        revision += 1
    }

    func cancel() {
        progress?.cancel()
        poll?.invalidate()
        isScanning = false
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Scan"
        panel.message = "Choose a folder to scan"
        if panel.runModal() == .OK, let u = panel.url { scan(.custom(u)) }
    }

    func open(_ node: FileNode) {
        guard node.canOpen else { return }
        if node.isPruned {
            let fresh = Scanner.scanDirectory(node.url, progress: ScanProgress(), depth: 1, minFile: 0)
            for k in fresh.children { k.parent = node }
            node.children = fresh.children
            node.isPruned = false
        }
        current = node
        revision += 1
    }

    func goUp() {
        if let p = current?.parent { current = p; revision += 1 }
    }

    /// Chain from root to current, for the breadcrumb.
    var path: [FileNode] {
        var chain: [FileNode] = []
        var n = current
        while let x = n { chain.insert(x, at: 0); n = x.parent }
        return chain
    }

    /// Finds the node for a URL in the tree (used for items coming from the big-files list).
    func node(for url: URL) -> FileNode? {
        guard let root else { return nil }
        var n = root
        let target = url.path
        while n.url.path != target {
            guard let next = n.children.first(where: { !$0.isAggregate && (target == $0.url.path || target.hasPrefix($0.url.path + "/")) }) else { return nil }
            n = next
        }
        return n
    }

    @discardableResult
    func moveToTrash(_ nodes: [FileNode]) -> [String] {
        var errors: [String] = []
        var trashed: [String] = []
        for n in nodes where !n.isAggregate {
            do {
                try FileManager.default.trashItem(at: n.url, resultingItemURL: nil)
                trashed.append(n.url.path)
                detach(node(for: n.url) ?? n)
            } catch {
                errors.append("\(n.name): \(error.localizedDescription)")
            }
        }
        bigFiles.removeAll { b in trashed.contains { b.url.path == $0 || b.url.path.hasPrefix($0 + "/") } }
        revision += 1
        return errors
    }

    private func detach(_ n: FileNode) {
        guard let p = n.parent else { return }
        if let c = current, c === n || c.url.path.hasPrefix(n.url.path + "/") { current = p }
        p.children.removeAll { $0 === n }
        var a: FileNode? = p
        while let x = a {
            x.size -= n.size
            x.itemCount -= n.itemCount
            a = x.parent
        }
        n.parent = nil
    }
}
