import Foundation
import CoreWLAN

struct NetSample {
    var down = 0.0
    var up = 0.0
    var totalDown = 0.0
    var totalUp = 0.0
    var interface = ""
    var kind = "Offline"
    var ip = ""
}

final class NetworkReader {
    private var last: (rx: UInt64, tx: UInt64, time: TimeInterval)?
    private var address: (name: String, ip: String) = ("", "")
    private var addressTime: TimeInterval = -100

    func read() -> NetSample {
        var s = NetSample()
        let now = ProcessInfo.processInfo.systemUptime
        let (rx, tx) = counters()
        s.totalDown = Double(rx)
        s.totalUp = Double(tx)
        if let last, now > last.time {
            s.down = Double(rx &- last.rx) / (now - last.time)
            s.up = Double(tx &- last.tx) / (now - last.time)
        }
        last = (rx, tx, now)

        if now - addressTime > 10 {
            address = primaryAddress()
            addressTime = now
        }
        s.interface = address.name
        s.ip = address.ip
        if !address.name.isEmpty {
            let wifi = CWWiFiClient.shared().interface()?.interfaceName
            s.kind = address.name == wifi ? "Wi-Fi" : "Ethernet"
        }
        return s
    }

    // 64-bit byte counters of the en* interfaces, so no wraparound at 4 GB
    private func counters() -> (UInt64, UInt64) {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len = 0
        guard sysctl(&mib, 6, nil, &len, nil, 0) == 0 else { return (0, 0) }
        var buf = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, 6, &buf, &len, nil, 0) == 0 else { return (0, 0) }

        var rx: UInt64 = 0, tx: UInt64 = 0
        buf.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= len {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                if Int32(header.ifm_type) == RTM_IFINFO2 {
                    let info = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                    if if_indextoname(UInt32(info.ifm_index), &name) != nil, cString(name).hasPrefix("en") {
                        rx += info.ifm_data.ifi_ibytes
                        tx += info.ifm_data.ifi_obytes
                    }
                }
                guard header.ifm_msglen > 0 else { break }
                offset += Int(header.ifm_msglen)
            }
        }
        return (rx, tx)
    }

    private func primaryAddress() -> (String, String) {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return ("", "") }
        defer { freeifaddrs(list) }

        var found: [(String, String)] = []
        var cursor = list
        while let item = cursor?.pointee {
            defer { cursor = item.ifa_next }
            let name = String(cString: item.ifa_name)
            let flags = Int32(item.ifa_flags)
            guard name.hasPrefix("en"), flags & IFF_UP != 0, flags & IFF_RUNNING != 0,
                  let addr = item.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                found.append((name, cString(host)))
            }
        }
        return found.sorted { $0.0 < $1.0 }.first ?? ("", "")
    }
}
