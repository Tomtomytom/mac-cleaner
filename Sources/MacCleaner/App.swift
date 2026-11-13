import AppKit
import SwiftUI

@main
struct MacCleanerApp: App {
    @State private var disk = DiskStore()
    @State private var cleaner = CleanerStore()
    @State private var explorer = ExplorerStore()

    var body: some Scene {
        Window("Mac Cleaner", id: "main") {
            ContentView()
                .environment(disk)
                .environment(cleaner)
                .environment(explorer)
                .frame(minWidth: 900, minHeight: 580)
                .task {
                    if explorer.root == nil && !explorer.isScanning { explorer.scan(.home) }
                    await cleaner.load()
                }
        }
        .defaultSize(width: 1080, height: 720)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra {
            MenuBarContent()
                .environment(disk)
                .environment(cleaner)
        } label: {
            if let info = disk.info {
                Text("\(Image(systemName: "internaldrive")) \(info.available.formattedBytes)")
            } else {
                Image(systemName: "internaldrive")
            }
        }
    }
}

struct MenuBarContent: View {
    @Environment(DiskStore.self) private var disk
    @Environment(CleanerStore.self) private var cleaner
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let info = disk.info {
            Text("\(info.available.formattedBytes) available of \(info.total.formattedBytes)")
            Text("\(Int((info.usedFraction * 100).rounded()))% used")
        }
        Divider()
        Button("Open Mac Cleaner") {
            openWindow(id: "main")
            NSApp.activate()
        }
        .keyboardShortcut("o")
        Button(cleaner.isCleaning ? "Cleaning…" : "Quick Clean (\(cleaner.safeBytes.formattedBytes))") {
            Task {
                await cleaner.load()
                await cleaner.clean(Set(cleaner.targets.filter(\.defaultSelected).map(\.id)), disk: disk)
            }
        }
        .disabled(cleaner.isCleaning)
        Divider()
        Button("Quit Mac Cleaner") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
