// SPDX-License-Identifier: Apache-2.0
import XCTest

final class IPv4UDPPacketTests: XCTestCase {
    func testHeaderChecksumMatchesKnownVector() {
        let header: [UInt8] = [0x45, 0x00, 0x00, 0x73, 0x00, 0x00, 0x40, 0x00, 0x40, 0x11, 0x00, 0x00,
                               0xC0, 0xA8, 0x00, 0x01, 0xC0, 0xA8, 0x00, 0xC7]
        XCTAssertEqual(IPv4UDPPacket.checksum(header), 0xB861)
    }

    func testReplyRoundTrip() throws {
        let query = IPv4UDPPacket(source: [198, 18, 0, 1], destination: [198, 18, 0, 53],
                                  sourcePort: 54321, destinationPort: 53, payload: Data([1, 2, 3, 4, 5]))
        let parsed = try XCTUnwrap(IPv4UDPPacket(query.data))
        XCTAssertEqual(parsed, query)

        let reply = try XCTUnwrap(IPv4UDPPacket(parsed.reply(with: Data([9, 9])).data))
        XCTAssertEqual(reply.source, [198, 18, 0, 53])
        XCTAssertEqual(reply.destination, [198, 18, 0, 1])
        XCTAssertEqual(reply.sourcePort, 53)
        XCTAssertEqual(reply.destinationPort, 54321)
        XCTAssertEqual(reply.payload, Data([9, 9]))
        XCTAssertEqual(IPv4UDPPacket.checksum(Array(reply.data.prefix(20))), 0)
    }

    func testRejectsNonUDPAndFragments() {
        var bytes = [UInt8](IPv4UDPPacket(source: [10, 0, 0, 1], destination: [10, 0, 0, 2],
                                          sourcePort: 1, destinationPort: 53, payload: Data(count: 4)).data)
        var tcp = bytes
        tcp[9] = 6
        XCTAssertNil(IPv4UDPPacket(Data(tcp)))
        bytes[6] = 0x20
        XCTAssertNil(IPv4UDPPacket(Data(bytes)))
        XCTAssertNil(IPv4UDPPacket(Data([0x45, 0, 0])))
    }

    func testRejectsLengthBeyondBuffer() {
        var bytes = [UInt8](IPv4UDPPacket(source: [10, 0, 0, 1], destination: [10, 0, 0, 2],
                                          sourcePort: 1, destinationPort: 53, payload: Data(count: 4)).data)
        bytes[20 + 5] = 200
        XCTAssertNil(IPv4UDPPacket(Data(bytes)))
    }
}

final class IPv4OptionsTests: XCTestCase {
    func testParsesHeaderWithOptions() throws {
        let plain = [UInt8](IPv4UDPPacket(source: [10, 0, 0, 1], destination: [10, 0, 0, 2],
                                          sourcePort: 7, destinationPort: 53, payload: Data([42])).data)
        var withOptions = Array(plain[0..<20]) + [1, 1, 1, 0] + Array(plain[20...])
        withOptions[0] = 0x46
        withOptions[3] = UInt8(withOptions.count)
        let parsed = try XCTUnwrap(IPv4UDPPacket(Data(withOptions)))
        XCTAssertEqual(parsed.destinationPort, 53)
        XCTAssertEqual(parsed.payload, Data([42]))
    }
}
