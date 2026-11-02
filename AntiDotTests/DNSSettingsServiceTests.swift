// SPDX-License-Identifier: Apache-2.0
import XCTest
@testable import AntiDot

/// Simülatör demo modunun kurulum → etkinleştirme → kaldırma akışı.
@MainActor
final class DNSSettingsServiceTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "antidot.tests.\(UUID().uuidString)")!
    }

    func testSimulatedLifecycle() async {
        let defaults = freshDefaults()
        let service = DNSSettingsService(simulated: true, defaults: defaults)
        await service.refresh()
        XCTAssertEqual(service.state, .notInstalled)

        await service.install(DNSResolver.presets[0])
        XCTAssertEqual(service.state, .installedInactive)
        XCTAssertTrue(service.isInstalled)

        service.simulateActivation()
        XCTAssertEqual(service.state, .active)

        // Etkinken başka sunucu uygulamak etkin durumu korur.
        await service.install(DNSResolver.presets[2])
        XCTAssertEqual(service.state, .active)
        XCTAssertEqual(service.installedDescription, "AntiDot – Google DoH (HTTPS)")

        // Durum yeniden açılışta korunur.
        let reopened = DNSSettingsService(simulated: true, defaults: defaults)
        await reopened.refresh()
        XCTAssertEqual(reopened.state, .active)

        await service.uninstall()
        XCTAssertEqual(service.state, .notInstalled)
        XCTAssertNil(service.installedDescription)
    }

    func testInvalidResolverIsRejected() async {
        let service = DNSSettingsService(simulated: true, defaults: freshDefaults())
        await service.refresh()
        let bad = DNSResolver(name: "", transport: .doh, dohURL: "http://x", dotServerName: nil,
                              bootstrapServers: [])
        await service.install(bad)
        XCTAssertEqual(service.state, .notInstalled)
        XCTAssertNotNil(service.lastError)
    }
}
