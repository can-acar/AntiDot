// SPDX-License-Identifier: Apache-2.0
import Foundation
import NetworkExtension

@MainActor
final class TunnelService: ObservableObject {
    static let providerBundleIdentifier = "com.canacar.antidot.tunnel"

    @Published private(set) var status: NEVPNStatus = .invalid
    @Published var lastError: String?
    @Published private(set) var isBusy = false
    @Published private(set) var configuredName: String?

    private var manager: NETunnelProviderManager?
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.status = self?.manager?.connection.status ?? .invalid }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    var isRunning: Bool { status == .connected || status == .connecting || status == .reasserting }

    func refresh() async {
        do {
            manager = try await NETunnelProviderManager.loadAllFromPreferences().first
            status = manager?.connection.status ?? .invalid
            configuredName = manager.flatMap(Self.configuredName)
        } catch {
            lastError = "Tünel ayarları okunamadı: \(error.localizedDescription)"
        }
    }

    func start(_ resolvers: [DNSResolver]) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let manager = try await NETunnelProviderManager.loadAllFromPreferences().first ?? NETunnelProviderManager()
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = Self.providerBundleIdentifier
            proto.serverAddress = "AntiDot"
            proto.providerConfiguration = [PacketTunnelKeys.resolvers: try JSONEncoder().encode(resolvers)]
            manager.protocolConfiguration = proto
            manager.localizedDescription = "AntiDot Tünel"
            manager.isEnabled = true
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
            try manager.connection.startVPNTunnel()
            self.manager = manager
            status = manager.connection.status
            configuredName = resolvers.first?.name
            lastError = nil
        } catch {
            lastError = "Tünel başlatılamadı: \(error.localizedDescription)"
        }
    }

    func stop() {
        manager?.connection.stopVPNTunnel()
    }

    private static func configuredName(_ manager: NETunnelProviderManager) -> String? {
        guard let proto = manager.protocolConfiguration as? NETunnelProviderProtocol,
              let data = proto.providerConfiguration?[PacketTunnelKeys.resolvers] as? Data else { return nil }
        return (try? JSONDecoder().decode([DNSResolver].self, from: data))?.first?.name
    }
}

extension DNSResolver {
    var redundantGroup: [DNSResolver] {
        isBuiltIn ? DNSResolver.presets.filter { $0.name == name } : [self]
    }
}
