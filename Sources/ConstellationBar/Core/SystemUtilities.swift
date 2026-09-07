import AppKit
import Foundation

struct NetworkCounters {
    var received: UInt64
    var sent: UInt64
}

enum NetworkInterfaceProvider {
    static func counters() -> NetworkCounters {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        var received: UInt64 = 0
        var sent: UInt64 = 0
        guard getifaddrs(&addresses) == 0, let first = addresses else { return NetworkCounters(received: 0, sent: 0) }
        defer { freeifaddrs(addresses) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while ptr != nil {
            guard let interface = ptr?.pointee else { break }
            let flags = Int32(interface.ifa_flags)
            let isUp = (flags & IFF_UP) == IFF_UP
            let isLoopback = (flags & IFF_LOOPBACK) == IFF_LOOPBACK
            if isUp, !isLoopback, interface.ifa_addr?.pointee.sa_family == UInt8(AF_LINK), let data = interface.ifa_data {
                let networkData = data.assumingMemoryBound(to: if_data.self).pointee
                received += UInt64(networkData.ifi_ibytes)
                sent += UInt64(networkData.ifi_obytes)
            }
            ptr = interface.ifa_next
        }
        return NetworkCounters(received: received, sent: sent)
    }

    static func interfaceNames() -> [String] {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return [] }
        defer { freeifaddrs(addresses) }
        var names: [String] = []
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while ptr != nil {
            guard let interface = ptr?.pointee else { break }
            let flags = Int32(interface.ifa_flags)
            if (flags & IFF_UP) == IFF_UP, let cName = interface.ifa_name {
                names.append(String(cString: cName))
            }
            ptr = interface.ifa_next
        }
        return Array(Set(names))
    }
}

struct CPUCounters {
    var user: UInt64
    var system: UInt64
    var idle: UInt64
    var nice: UInt64
    var total: UInt64 { user + system + idle + nice }

    static func current() -> CPUCounters {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return CPUCounters(user: 0, system: 0, idle: 0, nice: 0) }
        return CPUCounters(
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )
    }
}

enum AppIconProvider {
    static func icon(for app: AppIdentity) -> NSImage {
        if let bundleID = app.bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        if let appURL = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == app.name })?.bundleURL {
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }
        let image = NSImage(systemSymbolName: "app", accessibilityDescription: app.name) ?? NSImage(size: NSSize(width: 18, height: 18))
        image.isTemplate = true
        return image
    }
}

enum ByteFormatter {
    static func bytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(min(bytes, UInt64(Int64.max))))
    }

    static func compactSpeed(_ bytes: UInt64) -> String {
        let units = ["B", "K", "M", "G"]
        var value = Double(bytes)
        var index = 0
        while value >= 1000, index < units.count - 1 {
            value /= 1000
            index += 1
        }
        if index == 0 { return "\(Int(value))\(units[index])" }
        if value < 10 { return String(format: "%.1f%@", value, units[index]) }
        return "\(Int(value.rounded()))\(units[index])"
    }

    static func speed(_ bytes: UInt64) -> String {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = Double(bytes)
        var index = 0
        while value >= 1000, index < units.count - 1 {
            value /= 1000
            index += 1
        }
        if index == 0 { return "\(Int(value)) \(units[index])" }
        if value < 10 { return String(format: "%.1f %@", value, units[index]) }
        return String(format: "%.0f %@", value, units[index])
    }
}

enum UptimeFormatter {
    static func compact(_ interval: TimeInterval) -> String {
        let totalHours = max(0, Int(interval) / 3600)
        let days = totalHours / 24
        let hours = totalHours % 24
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h" }
        return "\(max(1, Int(interval) / 60))m"
    }
}

extension NSView {
    func addPinnedSubview(_ subview: NSView) {
        addSubview(subview)
        subview.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            subview.leadingAnchor.constraint(equalTo: leadingAnchor),
            subview.trailingAnchor.constraint(equalTo: trailingAnchor),
            subview.topAnchor.constraint(equalTo: topAnchor),
            subview.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

extension NSStackView {
    func setArrangedSubviews(_ views: [NSView]) {
        for view in arrangedSubviews {
            removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for view in views {
            addArrangedSubview(view)
        }
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        let red = CGFloat((hex >> 16) & 0xff) / 255.0
        let green = CGFloat((hex >> 8) & 0xff) / 255.0
        let blue = CGFloat(hex & 0xff) / 255.0
        self.init(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    func withAdjustedAlpha(_ delta: CGFloat) -> NSColor {
        withAlphaComponent(max(0.08, min(0.92, alphaComponent + delta)))
    }

    var prefersDarkAppearance: Bool {
        guard let color = usingColorSpace(.sRGB) else { return true }
        let luminance = 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
        return luminance < 0.5
    }
}
