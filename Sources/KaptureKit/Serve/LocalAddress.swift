import Darwin
import Foundation

/// The address a phone on the same Wi-Fi would use to reach this Mac.
///
/// Read when the server starts and again whenever a strip is shared, because
/// DHCP can move a laptop mid-party and a QR code carrying yesterday's address
/// fails in a way nobody can diagnose from the other side of a room.
public enum LocalAddress {
    /// Ethernet and Wi-Fi, in that order of preference. Everything else on a
    /// Mac is something a phone cannot route to: `lo0` is this machine,
    /// `awdl0` and `llw0` are AirDrop's direct links, and `utun*` are VPNs.
    private static func isUsable(_ name: String) -> Bool {
        name.hasPrefix("en")
    }

    public static func ipv4() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }

        var fallback: String?
        for interface in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let raw = interface.pointee.ifa_addr,
                  raw.pointee.sa_family == UInt8(AF_INET) else { continue }
            let flags = Int32(interface.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                raw, socklen_t(raw.pointee.sa_len),
                &host, socklen_t(host.count),
                nil, 0, NI_NUMERICHOST
            ) == 0 else { continue }

            let address = String(
                decoding: host.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self
            )
            let name = String(cString: interface.pointee.ifa_name)
            if isUsable(name) { return address }
            fallback = fallback ?? address
        }
        return fallback
    }
}
