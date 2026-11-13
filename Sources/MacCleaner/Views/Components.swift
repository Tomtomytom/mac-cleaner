import AppKit
import SwiftUI

enum Palette {
    static let colors: [Color] = [.blue, .purple, .pink, .orange, .yellow, .green, .teal, .indigo, .mint, .cyan]
    static func color(_ i: Int) -> Color { colors[i % colors.count] }

    static func usage(_ fraction: Double) -> Color {
        fraction < 0.75 ? .green : fraction < 0.9 ? .orange : .red
    }
}

/// Rounded card used across the app.
struct Card<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(nsColor: .separatorColor).opacity(0.6)))
            .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }
}

struct CardHeader: View {
    let title: String
    var symbol: String?
    var trailing: AnyView?

    var body: some View {
        HStack {
            if let symbol { Image(systemName: symbol).foregroundStyle(.secondary) }
            Text(title).font(.headline)
            Spacer()
            trailing
        }
    }
}

struct IconTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
    }
}

struct Badge: View {
    let text: String
    var tint: Color = .secondary
    var symbol: String?

    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .foregroundStyle(tint)
        .background(tint.opacity(0.14), in: Capsule())
    }
}

struct ProportionBar: View {
    let fraction: Double
    var color: Color = .accentColor

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(color.gradient)
                    .frame(width: max(fraction > 0 ? 3 : 0, geo.size.width * min(1, fraction)))
            }
        }
        .frame(height: 6)
    }
}

/// Segmented horizontal bar.
struct StackedBar: View {
    struct Segment: Identifiable {
        let id: AnyHashable
        let value: Double
        let color: Color
        let label: String
    }
    let segments: [Segment]
    let total: Double
    var height: CGFloat = 14
    var onTap: ((AnyHashable) -> Void)?

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1.5) {
                ForEach(segments) { s in
                    let w = total > 0 ? geo.size.width * s.value / total : 0
                    if w >= 1 {
                        Rectangle()
                            .fill(s.color.gradient)
                            .frame(width: max(1, w - 1.5))
                            .help(s.label)
                            .onTapGesture { onTap?(s.id) }
                    }
                }
                Spacer(minLength: 0)
            }
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: height / 2.6, style: .continuous))
        }
        .frame(height: height)
    }
}

struct DiskRing: View {
    let info: DiskInfo
    var lineWidth: CGFloat = 14

    var body: some View {
        let used = info.usedFraction
        let purge = info.purgeableFraction
        ZStack {
            Circle().stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: used, to: min(1, used + purge))
                .stroke(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: lineWidth))
                .rotationEffect(.degrees(-90))
            Circle()
                .trim(from: 0, to: used)
                .stroke(Palette.usage(used).gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(Int((used * 100).rounded()))%")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                Text("used").font(.caption).foregroundStyle(.secondary)
            }
        }
        .animation(.smooth, value: used)
    }
}

struct NodeIcon: View {
    let node: FileNode

    var body: some View {
        if node.isAggregate {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Image(nsImage: NSWorkspace.shared.icon(forFile: node.url.path))
                .resizable()
                .interpolation(.high)
        }
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var action: (title: String, run: () -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title).font(.title3.weight(.semibold))
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if let action {
                Button(action.title, action: action.run)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 4)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ScanningView: View {
    @Environment(ExplorerStore.self) private var explorer

    var body: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text("Scanning \(FS.pretty(explorer.scanRoot.url))…").font(.title3.weight(.semibold))
            Text("\(explorer.progressFiles.formatted()) files · \(explorer.progressBytes.formattedBytes)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
            Text(FS.pretty(URL(fileURLWithPath: explorer.progressPath)))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 460)
            Button("Cancel") { explorer.cancel() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Banner shown when the app can't see protected folders.
struct FullDiskAccessBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Full Disk Access Recommended").font(.headline)
                Text("Without it, macOS hides some folders (Trash, Mail, Messages…) and sizes will be incomplete. Add Mac Cleaner in Settings › Privacy & Security, then relaunch the app.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Open Settings") { FS.openFullDiskAccessSettings() }
        }
        .padding(14)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.orange.opacity(0.3)))
    }
}

/// Floating confirmation pill.
struct Toast: View {
    let text: String
    var symbol = "checkmark.circle.fill"

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.body.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.quaternary))
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }
}
