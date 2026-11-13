import Foundation
import Observation
import SwiftUI

enum CleanSection: String, CaseIterable, Identifiable, Sendable {
    case user, dev, system, maintenance
    var id: String { rawValue }

    var title: String {
        switch self {
        case .user: "User Files"
        case .dev: "Developer Tools"
        case .system: "System"
        case .maintenance: "Maintenance"
        }
    }

    var subtitle: String {
        switch self {
        case .user: "Caches, logs and temporary files from your account"
        case .dev: "Build and package caches, recreated on demand"
        case .system: "Requires your administrator password"
        case .maintenance: "Doesn’t free up space, but fixes small glitches"
        }
    }

    var tint: Color {
        switch self {
        case .user: .blue
        case .dev: .purple
        case .system: .orange
        case .maintenance: .teal
        }
    }
}

enum Measure: Sendable {
    case paths([String])
    case brew
    case snapshots
    case none
}

enum CleanAction: Sendable {
    /// Delete the contents of these folders (folders are kept).
    case contents([String])
    case shell(String)
    case admin(String)
    case emptyTrash
}

enum SizeState: Equatable {
    case unknown, measuring, unreadable, none
    case value(Int64)
    case info(String)

    var bytes: Int64? { if case .value(let v) = self { v } else { nil } }
}

struct CleanTarget: Identifiable, Sendable {
    let id: String
    let section: CleanSection
    let title: String
    let detail: String
    let symbol: String
    let action: CleanAction
    var measure: Measure = .none
    /// Shell command that must succeed for this target to be shown.
    var check: String? = nil
    var caution = false

    var isAdmin: Bool { if case .admin = action { true } else { false } }
    var defaultSelected: Bool { !caution && section != .system && section != .maintenance }

    /// The equivalent Terminal command, shown to the user.
    var command: String {
        func q(_ p: String) -> String {
            "\"" + (p.hasPrefix("~") ? "$HOME" + p.dropFirst() : p) + "\""
        }
        switch action {
        case .contents(let ps): return ps.map { "rm -rf \(q($0))/*" }.joined(separator: "\n")
        case .shell(let c): return c
        case .admin(let c): return "sudo sh -c '\(c)'"
        case .emptyTrash: return "osascript -e 'tell application \"Finder\" to empty trash'"
        }
    }

    func isAvailable() async -> Bool {
        if let check { return await Shell.run(check).ok }
        if case .paths(let ps) = measure { return ps.contains { FS.exists($0) } }
        return true
    }

    func measureSize() async -> SizeState {
        switch measure {
        case .none:
            return .none
        case .paths(let ps):
            var total: Int64 = 0
            var readable = false, blocked = false
            for p in ps {
                if let s = FS.size(of: FS.url(p)) { total += s; readable = true }
                else if FS.exists(p) { blocked = true }
            }
            return (!readable && blocked) ? .unreadable : .value(total)
        case .brew:
            let r = await Shell.run("brew cleanup -n --prune=all 2>/dev/null | tail -n 5")
            return .value(Self.parseBrew(r.output))
        case .snapshots:
            let r = await Shell.run("tmutil listlocalsnapshots / 2>/dev/null | grep -c com.apple")
            let n = Int(r.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            return .info(n == 0 ? "None" : n == 1 ? "1 snapshot" : "\(n) snapshots")
        }
    }

    func perform() async -> Shell.Result {
        switch action {
        case .contents(let ps):
            let paths = ps
            let r = await Task.detached(priority: .userInitiated) { FS.deleteContents(of: paths) }.value
            var msg = r.removed == 1 ? "1 item deleted" : "\(r.removed) items deleted"
            if r.failed > 0 { msg += " · \(r.failed) protected or in use" }
            return Shell.Result(status: 0, output: msg)
        case .shell(let c):
            return await Shell.run(c)
        case .admin(let c):
            return await Shell.runAsAdmin(c)
        case .emptyTrash:
            return await Shell.osascript("tell application \"Finder\" to empty trash")
        }
    }

    /// "==> This operation would free approximately 1.2GB of disk space."
    static func parseBrew(_ s: String) -> Int64 {
        guard let m = s.firstMatch(of: #/approximately ([0-9.]+)\s*([KMGT]?B)/#) else { return 0 }
        let n = Double(m.1) ?? 0
        let mult: Double = switch m.2 {
        case "KB": 1e3
        case "MB": 1e6
        case "GB": 1e9
        case "TB": 1e12
        default: 1
        }
        return Int64(n * mult)
    }
}

extension CleanTarget {
    static let all: [CleanTarget] = [
        // MARK: User
        CleanTarget(id: "caches", section: .user, title: "App Caches",
                    detail: "Recreated automatically. Quit your apps first for best results.",
                    symbol: "shippingbox", action: .contents(["~/Library/Caches"]),
                    measure: .paths(["~/Library/Caches"])),
        CleanTarget(id: "logs", section: .user, title: "App Logs",
                    detail: "Log files and crash reports.",
                    symbol: "doc.text", action: .contents(["~/Library/Logs"]),
                    measure: .paths(["~/Library/Logs"])),
        CleanTarget(id: "trash", section: .user, title: "Trash",
                    detail: "Empties the Finder Trash.",
                    symbol: "trash", action: .emptyTrash, measure: .paths(["~/.Trash"])),
        CleanTarget(id: "mailDownloads", section: .user, title: "Opened Mail Attachments",
                    detail: "Copies of attachments you opened from Mail.",
                    symbol: "paperclip",
                    action: .contents(["~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"]),
                    measure: .paths(["~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"])),
        CleanTarget(id: "iosUpdates", section: .user, title: "iPhone / iPad Updates",
                    detail: ".ipsw files downloaded by the Finder.",
                    symbol: "iphone.and.arrow.forward",
                    action: .contents(["~/Library/iTunes/iPhone Software Updates", "~/Library/iTunes/iPad Software Updates"]),
                    measure: .paths(["~/Library/iTunes/iPhone Software Updates", "~/Library/iTunes/iPad Software Updates"])),
        CleanTarget(id: "iosBackups", section: .user, title: "iPhone / iPad Backups",
                    detail: "Local backups of your devices. Only delete them if you use iCloud Backup.",
                    symbol: "externaldrive.badge.timemachine",
                    action: .contents(["~/Library/Application Support/MobileSync/Backup"]),
                    measure: .paths(["~/Library/Application Support/MobileSync/Backup"]), caution: true),

        // MARK: Dev
        CleanTarget(id: "derivedData", section: .dev, title: "Xcode · DerivedData",
                    detail: "Xcode intermediate builds and indexes.",
                    symbol: "hammer", action: .contents(["~/Library/Developer/Xcode/DerivedData"]),
                    measure: .paths(["~/Library/Developer/Xcode/DerivedData"])),
        CleanTarget(id: "deviceSupport", section: .dev, title: "Xcode · Device Support",
                    detail: "Symbols for older iOS / watchOS versions, downloaded again when needed.",
                    symbol: "iphone.gen3",
                    action: .contents(["~/Library/Developer/Xcode/iOS DeviceSupport", "~/Library/Developer/Xcode/watchOS DeviceSupport"]),
                    measure: .paths(["~/Library/Developer/Xcode/iOS DeviceSupport", "~/Library/Developer/Xcode/watchOS DeviceSupport"])),
        CleanTarget(id: "xcodeArchives", section: .dev, title: "Xcode · Archives",
                    detail: "Old archives of published apps.",
                    symbol: "archivebox", action: .contents(["~/Library/Developer/Xcode/Archives"]),
                    measure: .paths(["~/Library/Developer/Xcode/Archives"]), caution: true),
        CleanTarget(id: "simCaches", section: .dev, title: "Simulators · Caches",
                    detail: "iOS Simulator caches.",
                    symbol: "ipad.and.iphone", action: .contents(["~/Library/Developer/CoreSimulator/Caches"]),
                    measure: .paths(["~/Library/Developer/CoreSimulator/Caches"])),
        CleanTarget(id: "simulators", section: .dev, title: "Unavailable Simulators",
                    detail: "Deletes simulators for iOS versions that are no longer installed.",
                    symbol: "xmark.app", action: .shell("xcrun simctl delete unavailable"),
                    check: "xcrun --find simctl"),
        CleanTarget(id: "homebrew", section: .dev, title: "Homebrew",
                    detail: "Old package versions and downloads.",
                    symbol: "mug", action: .shell("brew cleanup --prune=all -s"),
                    measure: .brew, check: "command -v brew"),
        CleanTarget(id: "npm", section: .dev, title: "npm · Cache",
                    detail: "Packages downloaded by npm.",
                    symbol: "cube", action: .contents(["~/.npm/_cacache"]),
                    measure: .paths(["~/.npm/_cacache"])),
        CleanTarget(id: "pnpm", section: .dev, title: "pnpm · Store",
                    detail: "Removes packages not used by any of your projects.",
                    symbol: "cube.box", action: .shell("pnpm store prune"),
                    measure: .paths(["~/Library/pnpm/store"]), check: "command -v pnpm"),
        CleanTarget(id: "gradle", section: .dev, title: "Gradle · Caches",
                    detail: "Gradle / Android dependencies and builds.",
                    symbol: "gearshape.2", action: .contents(["~/.gradle/caches"]),
                    measure: .paths(["~/.gradle/caches"])),
        CleanTarget(id: "cargo", section: .dev, title: "Cargo · Registry",
                    detail: "Downloaded Rust crates.",
                    symbol: "shippingbox.circle", action: .contents(["~/.cargo/registry/cache"]),
                    measure: .paths(["~/.cargo/registry/cache"])),
        CleanTarget(id: "go", section: .dev, title: "Go · Modules",
                    detail: "Go module cache.",
                    symbol: "chevron.left.forwardslash.chevron.right", action: .shell("go clean -modcache"),
                    measure: .paths(["~/go/pkg/mod"]), check: "command -v go"),
        CleanTarget(id: "docker", section: .dev, title: "Docker",
                    detail: "Stopped containers, unused networks and untagged images. Docker must be running.",
                    symbol: "shippingbox.and.arrow.backward", action: .shell("docker system prune -f"),
                    check: "command -v docker", caution: true),

        // MARK: System
        CleanTarget(id: "systemCaches", section: .system, title: "System Caches",
                    detail: "Shared caches in /Library/Caches.",
                    symbol: "internaldrive", action: .admin("rm -rf /Library/Caches/*"),
                    measure: .paths(["/Library/Caches"]), caution: true),
        CleanTarget(id: "systemLogs", section: .system, title: "System Logs",
                    detail: "Diagnostic reports and old compressed logs.",
                    symbol: "list.bullet.rectangle",
                    action: .admin("rm -rf /Library/Logs/DiagnosticReports/* /private/var/log/*.gz /private/var/log/asl/*.asl"),
                    measure: .paths(["/Library/Logs/DiagnosticReports"])),
        CleanTarget(id: "snapshots", section: .system, title: "Local Time Machine Snapshots",
                    detail: "Local copies macOS keeps until your backup disk is available (“purgeable” space).",
                    symbol: "clock.arrow.circlepath",
                    action: .admin("for d in $(tmutil listlocalsnapshotdates / | grep -E '^[0-9]{4}'); do tmutil deletelocalsnapshots $d; done"),
                    measure: .snapshots),

        // MARK: Maintenance
        CleanTarget(id: "dns", section: .maintenance, title: "Flush DNS Cache",
                    detail: "Useful when a website no longer loads properly.",
                    symbol: "network", action: .admin("dscacheutil -flushcache; killall -HUP mDNSResponder")),
        CleanTarget(id: "quicklook", section: .maintenance, title: "Reset Quick Look",
                    detail: "Regenerates Quick Look thumbnails and previews.",
                    symbol: "eye", action: .shell("qlmanage -r cache && qlmanage -r")),
        CleanTarget(id: "ram", section: .maintenance, title: "Free Up RAM",
                    detail: "Clears inactive memory (purge command).",
                    symbol: "memorychip", action: .admin("purge")),
    ]
}

@Observable @MainActor
final class CleanerStore {
    var targets: [CleanTarget] = []
    var sizes: [String: SizeState] = [:]
    var status: [String: (ok: Bool, text: String)] = [:]
    var selected: Set<String> = []
    var runningID: String?
    var isCleaning = false
    var isMeasuring = false
    var lastFreed: Int64?
    var loaded = false

    func load() async {
        guard !loaded else { return }
        loaded = true
        var available: [CleanTarget] = []
        await withTaskGroup(of: (Int, Bool).self) { g in
            for (i, t) in CleanTarget.all.enumerated() { g.addTask { (i, await t.isAvailable()) } }
            var ok = [Int: Bool]()
            for await (i, a) in g { ok[i] = a }
            available = CleanTarget.all.enumerated().filter { ok[$0.offset] == true }.map(\.element)
        }
        targets = available
        selected = Set(available.filter(\.defaultSelected).map(\.id))
        await measure(available.map(\.id))
    }

    func measure(_ ids: [String]? = nil) async {
        let list = ids.map { set in targets.filter { set.contains($0.id) } } ?? targets
        isMeasuring = true
        for t in list {
            if case .none = t.measure { sizes[t.id] = SizeState.none } else { sizes[t.id] = .measuring }
        }
        await withTaskGroup(of: (String, SizeState).self) { g in
            for t in list { g.addTask { (t.id, await t.measureSize()) } }
            for await (id, s) in g { sizes[id] = s }
        }
        isMeasuring = false
    }

    func targets(in section: CleanSection) -> [CleanTarget] { targets.filter { $0.section == section } }

    var selectedBytes: Int64 { selected.reduce(0) { $0 + (sizes[$1]?.bytes ?? 0) } }

    var safeBytes: Int64 {
        targets.filter(\.defaultSelected).reduce(0) { $0 + (sizes[$1.id]?.bytes ?? 0) }
    }

    func selectSafe() { selected = Set(targets.filter(\.defaultSelected).map(\.id)) }

    func clean(_ ids: Set<String>? = nil, disk: DiskStore) async {
        guard !isCleaning else { return }
        let chosen = targets.filter { (ids ?? selected).contains($0.id) }
        guard !chosen.isEmpty else { return }
        isCleaning = true
        lastFreed = nil
        let before = Dictionary(uniqueKeysWithValues: chosen.map { ($0.id, sizes[$0.id]?.bytes ?? 0) })
        let diskBefore = DiskInfo.current()?.free ?? 0

        for t in chosen where !t.isAdmin {
            runningID = t.id
            let r = await t.perform()
            status[t.id] = (r.ok, r.ok ? (r.output.isEmpty || t.id == "trash" ? "Done" : Self.lastLine(r.output)) : Self.lastLine(r.output))
        }

        // All admin commands in one go → a single password prompt.
        let admin = chosen.filter(\.isAdmin)
        if !admin.isEmpty {
            runningID = admin.first?.id
            let script = admin.compactMap { if case .admin(let c) = $0.action { "{ \(c); } 2>/dev/null; true" } else { nil } }
                .joined(separator: "; ")
            let r = await Shell.runAsAdmin(script)
            let msg = r.ok ? "Done" : (r.output.contains("-128") ? "Canceled" : Self.lastLine(r.output))
            for t in admin { status[t.id] = (r.ok, msg) }
        }

        runningID = nil
        await measure(chosen.map(\.id))
        disk.refresh()
        let measured = chosen.reduce(Int64(0)) { acc, t in
            acc + max(0, (before[t.id] ?? 0) - (sizes[t.id]?.bytes ?? 0))
        }
        let diskDelta = max(0, (DiskInfo.current()?.free ?? 0) - diskBefore)
        lastFreed = max(measured, diskDelta)
        isCleaning = false
    }

    private static func lastLine(_ s: String) -> String {
        s.split(separator: "\n").last.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
    }
}
