// SPDX-License-Identifier: Apache-2.0
import Foundation

/// RFC 1035 DNS mesajlarının asgari kodlayıcısı/çözücüsü.
/// Uygulama içi DoH/DoT testleri için yeterli: tek soru, A/AAAA/CNAME/TXT cevapları.
enum DNSRecordType: UInt16, CaseIterable, Identifiable {
    case a = 1
    case cname = 5
    case txt = 16
    case aaaa = 28

    var id: UInt16 { rawValue }
    var label: String {
        switch self {
        case .a: return "A"
        case .cname: return "CNAME"
        case .txt: return "TXT"
        case .aaaa: return "AAAA"
        }
    }
}

struct DNSAnswer: Equatable, Hashable {
    var name: String
    var type: UInt16
    var ttl: UInt32
    var value: String
}

struct DNSResponse: Equatable {
    var id: UInt16
    var rcode: UInt8
    var answers: [DNSAnswer]

    var rcodeDescription: String {
        switch rcode {
        case 0: return "NOERROR"
        case 1: return "FORMERR"
        case 2: return "SERVFAIL"
        case 3: return "NXDOMAIN"
        case 4: return "NOTIMP"
        case 5: return "REFUSED"
        default: return "RCODE \(rcode)"
        }
    }
}

enum DNSMessageError: Error, LocalizedError, Equatable {
    case invalidName(String)
    case truncated
    case badPointer
    case idMismatch

    var errorDescription: String? {
        switch self {
        case .invalidName(let n): return "Geçersiz alan adı: \(n)"
        case .truncated: return "DNS cevabı eksik/bozuk."
        case .badPointer: return "DNS sıkıştırma işaretçisi hatalı."
        case .idMismatch: return "Cevap kimliği sorguyla eşleşmiyor (olası enjeksiyon)."
        }
    }
}

enum DNSMessage {
    /// Tek sorulu, özyineleme istenen (RD=1) bir sorgu üretir.
    /// RFC 8484 önerisine uygun olarak DoH için `id` 0 kullanılabilir (önbellek dostu).
    static func makeQuery(name: String, type: DNSRecordType, id: UInt16) throws -> Data {
        var data = Data()
        data.appendUInt16(id)
        data.appendUInt16(0x0100)  // RD
        data.appendUInt16(1)       // QDCOUNT
        data.appendUInt16(0)       // ANCOUNT
        data.appendUInt16(0)       // NSCOUNT
        data.appendUInt16(0)       // ARCOUNT
        data.append(try encodeName(name))
        data.appendUInt16(type.rawValue)
        data.appendUInt16(1)       // IN
        return data
    }

    static func emptyReply(to query: Data, flags: UInt8, rcode: UInt8) -> Data {
        var b = [UInt8](query)
        b[2] |= flags
        b[3] = (b[3] & 0xF0) | rcode
        return Data(b)
    }

    static func encodeName(_ name: String) throws -> Data {
        let trimmed = name.hasSuffix(".") ? String(name.dropLast()) : name
        var out = Data()
        if !trimmed.isEmpty {
            for label in trimmed.split(separator: ".", omittingEmptySubsequences: false) {
                let bytes = Array(label.utf8)
                guard !bytes.isEmpty, bytes.count <= 63 else { throw DNSMessageError.invalidName(name) }
                out.append(UInt8(bytes.count))
                out.append(contentsOf: bytes)
            }
        }
        out.append(0)
        guard out.count <= 255 else { throw DNSMessageError.invalidName(name) }
        return out
    }

    static func parseResponse(_ data: Data, expectedID: UInt16? = nil) throws -> DNSResponse {
        let bytes = [UInt8](data)
        var r = Reader(bytes: bytes)
        let id = try r.u16()
        if let expectedID, expectedID != id { throw DNSMessageError.idMismatch }
        let flags = try r.u16()
        let qd = try r.u16()
        let an = try r.u16()
        _ = try r.u16()  // NSCOUNT
        _ = try r.u16()  // ARCOUNT

        for _ in 0..<qd {
            _ = try r.name()
            try r.skip(4)
        }

        var answers: [DNSAnswer] = []
        for _ in 0..<an {
            let name = try r.name()
            let type = try r.u16()
            _ = try r.u16()  // class
            let ttl = try r.u32()
            let rdlen = Int(try r.u16())
            let start = r.offset
            guard start + rdlen <= bytes.count else { throw DNSMessageError.truncated }
            let rdata = Array(bytes[start..<start + rdlen])
            let value: String
            switch type {
            case DNSRecordType.a.rawValue where rdlen == 4:
                value = rdata.map(String.init).joined(separator: ".")
            case DNSRecordType.aaaa.rawValue where rdlen == 16:
                value = formatIPv6(rdata)
            case DNSRecordType.cname.rawValue:
                var sub = Reader(bytes: bytes, offset: start)
                value = try sub.name()
            case DNSRecordType.txt.rawValue:
                value = parseTXT(rdata)
            default:
                value = rdata.map { String(format: "%02x", $0) }.joined()
            }
            try r.skip(rdlen)
            answers.append(DNSAnswer(name: name, type: type, ttl: ttl, value: value))
        }
        return DNSResponse(id: id, rcode: UInt8(flags & 0x000F), answers: answers)
    }

    private static func formatIPv6(_ b: [UInt8]) -> String {
        var addr = in6_addr()
        withUnsafeMutableBytes(of: &addr) { $0.copyBytes(from: b) }
        var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        guard inet_ntop(AF_INET6, &addr, &buf, socklen_t(buf.count)) != nil else { return "?" }
        return String(cString: buf)
    }

    private static func parseTXT(_ b: [UInt8]) -> String {
        var parts: [String] = []
        var i = 0
        while i < b.count {
            let len = Int(b[i]); i += 1
            let end = min(i + len, b.count)
            parts.append(String(decoding: b[i..<end], as: UTF8.self))
            i = end
        }
        return parts.joined()
    }

    private struct Reader {
        let bytes: [UInt8]
        var offset: Int = 0

        mutating func u8() throws -> UInt8 {
            guard offset < bytes.count else { throw DNSMessageError.truncated }
            defer { offset += 1 }
            return bytes[offset]
        }

        mutating func u16() throws -> UInt16 {
            UInt16(try u8()) << 8 | UInt16(try u8())
        }

        mutating func u32() throws -> UInt32 {
            UInt32(try u16()) << 16 | UInt32(try u16())
        }

        mutating func skip(_ n: Int) throws {
            guard offset + n <= bytes.count else { throw DNSMessageError.truncated }
            offset += n
        }

        /// Sıkıştırma işaretçilerini (RFC 1035 §4.1.4) destekleyerek ad okur.
        mutating func name() throws -> String {
            var labels: [String] = []
            var pos = offset
            var jumped = false
            var hops = 0
            while true {
                guard pos < bytes.count else { throw DNSMessageError.truncated }
                let len = bytes[pos]
                if len & 0xC0 == 0xC0 {
                    guard pos + 1 < bytes.count else { throw DNSMessageError.truncated }
                    let target = Int(len & 0x3F) << 8 | Int(bytes[pos + 1])
                    hops += 1
                    guard hops < 32, target < bytes.count else { throw DNSMessageError.badPointer }
                    if !jumped { offset = pos + 2 }
                    jumped = true
                    pos = target
                } else if len == 0 {
                    if !jumped { offset = pos + 1 }
                    break
                } else {
                    let start = pos + 1
                    let end = start + Int(len)
                    guard end <= bytes.count else { throw DNSMessageError.truncated }
                    labels.append(String(decoding: bytes[start..<end], as: UTF8.self))
                    pos = end
                }
            }
            return labels.isEmpty ? "." : labels.joined(separator: ".")
        }
    }
}

extension Data {
    mutating func appendUInt16(_ v: UInt16) {
        append(UInt8(v >> 8))
        append(UInt8(v & 0xFF))
    }
}
