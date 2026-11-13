import AppKit
import Foundation

extension Int64 {
    var formattedBytes: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}

/// File-system helpers.
enum FS {
    static let fm = FileManager.default
    static var home: URL { fm.homeDirectoryForCurrentUser }

    static func url(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    static func exists(_ path: String) -> Bool { fm.fileExists(atPath: url(path).path) }

    /// `/Users/x/Library` → `~/Library`
    static func pretty(_ url: URL) -> String {
        let p = url.path
        let h = home.path
        return p.hasPrefix(h) ? "~" + p.dropFirst(h.count) : p
    }

    /// Allocated size on disk, recursively. `nil` if the item does not exist or cannot be read.
    static func size(of url: URL) -> Int64? {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return nil }
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        if !isDir.boolValue {
            let v = try? url.resourceValues(forKeys: Set(keys))
            return Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
        }
        guard (try? fm.contentsOfDirectory(atPath: url.path)) != nil else { return nil }
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in e {
            if let v = try? f.resourceValues(forKeys: Set(keys)), v.isRegularFile == true {
                total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            }
        }
        return total
    }

    /// Deletes everything inside the given folders (keeps the folders themselves).
    static func deleteContents(of paths: [String]) -> (removed: Int, failed: Int) {
        var removed = 0, failed = 0
        let own = Bundle.main.bundleIdentifier
        for p in paths {
            guard let items = try? fm.contentsOfDirectory(at: url(p), includingPropertiesForKeys: nil, options: []) else { continue }
            for item in items where item.lastPathComponent != own {
                do { try fm.removeItem(at: item); removed += 1 } catch { failed += 1 }
            }
        }
        return (removed, failed)
    }

    /// Without Full Disk Access, macOS hides some folders (Mail, Safari, Trash…).
    static var hasFullDiskAccess: Bool {
        for p in ["~/Library/Safari", "~/Library/Mail", "~/Library/Messages"] where exists(p) {
            return (try? fm.contentsOfDirectory(atPath: url(p).path)) != nil
        }
        return true
    }

    static func openFullDiskAccessSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }

    static func reveal(_ urls: [URL]) { NSWorkspace.shared.activateFileViewerSelecting(urls) }

    static func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// Runs shell commands off the main thread.
enum Shell {
    struct Result: Sendable {
        var status: Int32
        var output: String
        var ok: Bool { status == 0 }
    }

    static func exec(_ launchPath: String, _ args: [String]) async -> Result {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: launchPath)
                p.arguments = args
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = pipe
                p.standardInput = FileHandle.nullDevice
                do { try p.run() } catch {
                    cont.resume(returning: Result(status: -1, output: error.localizedDescription))
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                cont.resume(returning: Result(status: p.terminationStatus, output: String(decoding: data, as: UTF8.self)))
            }
        }
    }

    /// Runs through a login zsh so Homebrew & co. are on the PATH.
    static func run(_ command: String) async -> Result {
        await exec("/bin/zsh", ["-lc", "export PATH=\"/opt/homebrew/bin:/usr/local/bin:$PATH\"; " + command])
    }

    static func osascript(_ script: String) async -> Result {
        await exec("/usr/bin/osascript", ["-e", script])
    }

    /// Asks for the admin password once (native macOS prompt) and runs the command as root.
    static func runAsAdmin(_ command: String) async -> Result {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return await osascript("do shell script \"\(escaped)\" with administrator privileges")
    }
}
