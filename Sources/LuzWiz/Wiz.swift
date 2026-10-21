import Foundation
import Darwin

/// WiZ local API: one JSON datagram each way over UDP port 38899, no account or cloud involved.
enum Wiz {
    static let port: UInt16 = 38899

    static func message(_ method: String, _ params: [String: Any] = [:]) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["method": method, "params": params])) ?? Data()
    }

    /// The `result` object of a reply; nil for no reply, bad JSON or an error reply.
    static func result(_ data: Data?) -> [String: Any]? {
        guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["result"] as? [String: Any]
    }

    /// Sends `message` to one lamp and waits for its reply, retrying because UDP may drop either datagram.
    static func send(_ message: Data, to ip: String) async -> Data? {
        await Task.detached {
            for _ in 0..<3 {
                if let reply = UDP.exchange(message, to: [ip], timeout: 0.6, collectAll: false).first {
                    return reply.data
                }
            }
            return nil
        }.value
    }

    /// Broadcasts `message` on every IPv4 network and collects one reply per lamp.
    static func discover(_ message: Data) async -> [(ip: String, data: Data)] {
        await Task.detached {
            var seen: [String: Data] = [:]
            for _ in 0..<2 {
                for reply in UDP.exchange(message, to: UDP.broadcastAddresses(), timeout: 1.2, collectAll: true) {
                    seen[reply.ip] = reply.data
                }
            }
            return seen.map { (ip: $0.key, data: $0.value) }
        }.value
    }
}

/// Blocking BSD-socket helpers; always called off the main thread.
enum UDP {
    static func exchange(_ message: Data, to addresses: [String], timeout: TimeInterval,
                         collectAll: Bool) -> [(ip: String, data: Data)] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return [] }
        defer { close(fd) }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))

        for ip in addresses {
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = Wiz.port.bigEndian
            guard inet_pton(AF_INET, ip, &addr.sin_addr) == 1 else { continue }
            message.withUnsafeBytes { bytes in
                withUnsafePointer(to: &addr) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        _ = sendto(fd, bytes.baseAddress, bytes.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
        }

        var replies: [(ip: String, data: Data)] = []
        var buffer = [UInt8](repeating: 0, count: 4096)
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let remaining = deadline.timeIntervalSinceNow
            // A zero SO_RCVTIMEO means "wait forever", so stop before the remaining time gets that small.
            if remaining < 0.01 { break }
            var tv = timeval(tv_sec: Int(remaining), tv_usec: Int32((remaining - floor(remaining)) * 1_000_000))
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

            var from = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &from) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    recvfrom(fd, &buffer, buffer.count, 0, sa, &length)
                }
            }
            if count <= 0 { break }
            replies.append((ip: string(from.sin_addr), data: Data(buffer[0..<count])))
            if !collectAll { break }
        }
        return replies
    }

    /// The broadcast address of every IPv4 interface that is up, e.g. 192.168.1.255.
    static func broadcastAddresses() -> [String] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return ["255.255.255.255"] }
        defer { freeifaddrs(list) }
        var result = Set<String>()
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = pointer.pointee
            let flags = Int32(ifa.ifa_flags)
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_BROADCAST != 0, flags & IFF_LOOPBACK == 0,
                  let broadcast = ifa.ifa_dstaddr else { continue }
            let sin = broadcast.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            result.insert(string(sin.sin_addr))
        }
        return result.isEmpty ? ["255.255.255.255"] : Array(result)
    }

    private static func string(_ address: in_addr) -> String {
        var address = address
        var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &address, &text, socklen_t(INET_ADDRSTRLEN))
        return String(cString: text)
    }
}
