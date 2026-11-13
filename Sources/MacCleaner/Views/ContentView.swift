import SwiftUI

enum Pane: String, CaseIterable, Identifiable {
    case overview, clean, explore, bigFiles
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .clean: "Clean Up"
        case .explore: "Explorer"
        case .bigFiles: "Large Files"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "gauge.with.dots.needle.33percent"
        case .clean: "sparkles"
        case .explore: "folder"
        case .bigFiles: "doc.badge.ellipsis"
        }
    }

    var shortcut: KeyEquivalent { KeyEquivalent(Character("\((Pane.allCases.firstIndex(of: self) ?? 0) + 1)")) }
}

struct ContentView: View {
    @Environment(DiskStore.self) private var disk
    @State private var pane: Pane? = .overview

    var body: some View {
        NavigationSplitView {
            List(selection: $pane) {
                ForEach(Pane.allCases) { p in
                    Label(p.title, systemImage: p.symbol).tag(p)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
            .safeAreaInset(edge: .bottom) { sidebarDisk }
        } detail: {
            Group {
                switch pane ?? .overview {
                case .overview: OverviewView(pane: $pane)
                case .clean: CleanView()
                case .explore: ExplorerView()
                case .bigFiles: BigFilesView(pane: $pane)
                }
            }
            .navigationTitle((pane ?? .overview).title)
        }
        .background {
            // ⌘1…⌘4 to switch panes
            ForEach(Pane.allCases) { p in
                Button("") { pane = p }.keyboardShortcut(p.shortcut, modifiers: .command)
            }
            .opacity(0)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var sidebarDisk: some View {
        if let info = disk.info {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "internaldrive").foregroundStyle(.secondary)
                    Text(info.name).font(.callout.weight(.medium))
                }
                ProportionBar(fraction: info.usedFraction, color: Palette.usage(info.usedFraction))
                Text("\(info.available.formattedBytes) available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(14)
        }
    }
}
