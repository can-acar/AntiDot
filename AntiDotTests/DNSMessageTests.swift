// SPDX-License-Identifier: Apache-2.0
import XCTest
@testable import AntiDot

final class DNSMessageTests: XCTestCase {
    func testQueryEncoding() throws {
        let q = try DNSMessage.makeQuery(name: "example.com", type: .a, id: 0xABCD)
        let expected: [UInt8] = [
            0xAB, 0xCD, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            7, 0x65, 0x78, 0x61, 0x6d, 0x70, 0x6c, 0x65, 3, 0x63, 0x6f, 0x6d, 0,
            0x00, 0x01, 0x00, 0x01,
        ]
        XCTAssertEqual([UInt8](q), expected)
    }

    func testRejectsLongLabel() {
        let label = String(repeating: "a", count: 64)
        XCTAssertThrowsError(try DNSMessage.makeQuery(name: "\(label).com", type: .a, id: 1))
    }

    func testParsesCompressedAnswers() throws {
        var msg = [UInt8](try DNSMessage.makeQuery(name: "example.com", type: .a, id: 0x1234))
        msg[2] = 0x81; msg[3] = 0x80   // QR, RD, RA
        msg[7] = 2                      // ANCOUNT = 2
        // CNAME: example.com -> www.example.com  (pointer to offset 12)
        msg += [0xC0, 0x0C, 0x00, 0x05, 0x00, 0x01, 0x00, 0x00, 0x0E, 0x10, 0x00, 0x06,
                3, 0x77, 0x77, 0x77, 0xC0, 0x0C]
        // A: www.example.com (pointer to offset 41) -> 93.184.216.34
        msg += [0xC0, 41, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x3C, 0x00, 0x04,
                93, 184, 216, 34]

        let r = try DNSMessage.parseResponse(Data(msg), expectedID: 0x1234)
        XCTAssertEqual(r.rcode, 0)
        XCTAssertEqual(r.answers.count, 2)
        XCTAssertEqual(r.answers[0].value, "www.example.com")
        XCTAssertEqual(r.answers[0].ttl, 3600)
        XCTAssertEqual(r.answers[1].name, "www.example.com")
        XCTAssertEqual(r.answers[1].value, "93.184.216.34")
    }

    func testParsesAAAA() throws {
        var msg = [UInt8](try DNSMessage.makeQuery(name: "a.io", type: .aaaa, id: 7))
        msg[2] = 0x81; msg[3] = 0x80; msg[7] = 1
        msg += [0xC0, 0x0C, 0x00, 0x1C, 0x00, 0x01, 0, 0, 0, 60, 0x00, 0x10,
                0x26, 0x06, 0x47, 0x00, 0x47, 0x00, 0, 0, 0, 0, 0, 0, 0, 0, 0x11, 0x11]
        let r = try DNSMessage.parseResponse(Data(msg))
        XCTAssertEqual(r.answers.first?.value, "2606:4700:4700::1111")
    }

    func testIDMismatchIsRejected() throws {
        let msg = try DNSMessage.makeQuery(name: "a.io", type: .a, id: 1)
        XCTAssertThrowsError(try DNSMessage.parseResponse(msg, expectedID: 2)) {
            XCTAssertEqual($0 as? DNSMessageError, .idMismatch)
        }
    }

    func testPointerLoopIsRejected() {
        var msg: [UInt8] = [0, 1, 0x81, 0x80, 0, 1, 0, 0, 0, 0, 0, 0]
        msg += [0xC0, 0x0C, 0, 1, 0, 1]   // name points to itself
        XCTAssertThrowsError(try DNSMessage.parseResponse(Data(msg)))
    }

    func testPresetsAreValid() {
        for preset in DNSResolver.presets {
            XCTAssertNil(preset.validationError, preset.selectionKey)
        }
    }
}
