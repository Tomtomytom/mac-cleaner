import Foundation
import Observation

struct DiskInfo: Equatable {
    var name: String
    var total: Int64
    /// Truly free right now.
    var free: Int64
    /// Free + purgeable (what Finder shows as "available").
    var available: Int64

    var purgeable: Int64 { max(0, available - free) }
    var used: Int64 { max(0, total - available) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
    var purgeableFraction: Double { total > 0 ? Double(purgeable) / Double(total) : 0 }

    static func current() -> DiskInfo? {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey, .volumeLocalizedNameKey,
        ]
        guard let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = v.volumeTotalCapacity else { return nil }
        let free = Int64(v.volumeAvailableCapacity ?? 0)
        let important = v.volumeAvailableCapacityForImportantUsage ?? free
        return DiskInfo(name: v.volumeLocalizedName ?? "Macintosh HD", total: Int64(total), free: free, available: max(important, free))
    }
}

@Observable @MainActor
final class DiskStore {
    var info: DiskInfo?
    @ObservationIgnored private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        let new = DiskInfo.current()
        if new != info { info = new }
    }
}
