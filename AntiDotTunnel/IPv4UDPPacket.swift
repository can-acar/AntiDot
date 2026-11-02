// SPDX-License-Identifier: Apache-2.0
import Foundation

struct IPv4UDPPacket: Equatable {
    var source: [UInt8]
    var destination: [UInt8]
    var sourcePort: UInt16
    var destinationPort: UInt16
    var payload: Data

    init(source: [UInt8], destination: [UInt8], sourcePort: UInt16, destinationPort: UInt16, payload: Data) {
        self.source = source
        self.destination = destination
        self.sourcePort = sourcePort
        self.destinationPort = destinationPort
        self.payload = payload
    }

    init?(_ data: Data) {
        let b = [UInt8](data)
        guard b.count >= 28, b[0] >> 4 == 4, b[9] == 17 else { return nil }
        let ihl = Int(b[0] & 0x0F) * 4
        let totalLength = Int(b[2]) << 8 | Int(b[3])
        let fragmented = (b[6] & 0x3F) != 0 || b[7] != 0
        guard ihl >= 20, !fragmented, totalLength <= b.count, totalLength >= ihl + 8 else { return nil }
        let udpLength = Int(b[ihl + 4]) << 8 | Int(b[ihl + 5])
        guard udpLength >= 8, ihl + udpLength <= totalLength else { return nil }
        source = Array(b[12..<16])
        destination = Array(b[16..<20])
        sourcePort = UInt16(b[ihl]) << 8 | UInt16(b[ihl + 1])
        destinationPort = UInt16(b[ihl + 2]) << 8 | UInt16(b[ihl + 3])
        payload = Data(b[(ihl + 8)..<(ihl + udpLength)])
    }

    func reply(with payload: Data) -> IPv4UDPPacket {
        IPv4UDPPacket(source: destination, destination: source,
                      sourcePort: destinationPort, destinationPort: sourcePort, payload: payload)
    }

    var data: Data {
        let udpLength = 8 + payload.count
        let totalLength = 20 + udpLength
        var b: [UInt8] = [0x45, 0, UInt8(totalLength >> 8), UInt8(totalLength & 0xFF),
                          0, 0, 0x40, 0, 64, 17, 0, 0]
        b += source + destination
        let checksum = Self.checksum(b)
        b[10] = UInt8(checksum >> 8)
        b[11] = UInt8(checksum & 0xFF)
        b += [UInt8(sourcePort >> 8), UInt8(sourcePort & 0xFF),
              UInt8(destinationPort >> 8), UInt8(destinationPort & 0xFF),
              UInt8(udpLength >> 8), UInt8(udpLength & 0xFF), 0, 0]
        return Data(b) + payload
    }

    static func checksum(_ header: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        for i in stride(from: 0, to: header.count, by: 2) {
            sum += UInt32(header[i]) << 8 | UInt32(header[i + 1])
        }
        while sum > 0xFFFF { sum = (sum & 0xFFFF) + (sum >> 16) }
        return ~UInt16(sum)
    }
}
