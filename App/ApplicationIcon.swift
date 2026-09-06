import AppKit
import SwiftUI

/// Resolve installed icons only when a row first needs them. No app polling or disk scans.
@MainActor
private enum ApplicationIconCache {
    static let images: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 100
        return cache
    }()
    static var unavailable = Set<String>()

    static func image(bundleID: String?, name: String) -> NSImage? {
        let key = bundleID.flatMap { $0.isEmpty ? nil : $0 } ?? "name:\(name)"
        if let image = images.object(forKey: key as NSString) { return image }
        if unavailable.contains(key) { return nil }
        let url: URL?
        if let bundleID, !bundleID.isEmpty {
            url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        } else if name == "Quibble" {
            url = Bundle.main.bundleURL
        } else {
            // Older history has display names only. Use an exact running-app match;
            // never infer that two similarly named apps are the same destination.
            url = NSWorkspace.shared.runningApplications.first { $0.localizedName == name }?.bundleURL
        }
        guard let url else {
            if unavailable.count < 100 { unavailable.insert(key) }
            return nil
        }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        images.setObject(image, forKey: key as NSString)
        return image
    }
}

struct ApplicationIcon: View {
    let name: String
    var bundleID: String? = nil
    var size: CGFloat = 36
    private var imported: Bool { name == "Imported audio" }
    var body: some View {
        Group {
            if let icon = ApplicationIconCache.image(bundleID: bundleID, name: name) {
                Image(nsImage: icon).resizable().interpolation(.high).scaledToFit()
            } else {
                Image(systemName: imported ? "waveform" : "app.dashed")
                    .font(.system(size: size * 0.45, weight: .medium))
                    .foregroundStyle(Color.secondary)
                    .frame(width: size, height: size)
                    .background((Color.secondary).opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.25))
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct DeliveryBadge: View {
    let delivery: String
    private var tint: Color {
        switch delivery {
        case "Inserted": return .green
        case "Paste sent": return .secondary
        case "Ready to paste": return .orange
        default: return .secondary
        }
    }
    private var symbol: String {
        switch delivery {
        case "Inserted": return "checkmark.circle.fill"
        case "Paste sent": return "arrow.up.forward.circle.fill"
        case "Ready to paste": return "doc.on.clipboard"
        default: return "doc.text"
        }
    }
    var body: some View {
        Label(delivery, systemImage: symbol)
            .font(.caption.weight(.medium)).foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(tint.opacity(0.10), in: Capsule())
    }
}
