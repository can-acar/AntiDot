// SPDX-License-Identifier: Apache-2.0
import Foundation
import NetworkExtension

/// iOS 14+ `NEDNSSettingsManager` sarmalayıcısı.
///
/// Bu API, VPN kurmadan tüm cihazın DNS trafiğini seçilen DoH/DoT sunucusuna
/// yönlendirir. Yapılandırma kaydedildikten sonra kullanıcının
/// Ayarlar > Genel > VPN ve Aygıt Yönetimi > DNS bölümünden "AntiDot"u
/// bir kez seçmesi gerekir; iOS bunu programatik olarak etkinleştirmeye izin vermez.
@MainActor
final class DNSSettingsService: ObservableObject {
    enum State: Equatable {
        case unknown
        case notInstalled
        case installedInactive   // Kaydedildi ama Ayarlar'dan seçilmedi
        case active
    }

    @Published private(set) var state: State = .unknown
    @Published private(set) var installedDescription: String?
    @Published var lastError: String?
    @Published private(set) var isBusy = false

    private let manager = NEDNSSettingsManager.shared()
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .NEDNSSettingsConfigurationDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func refresh() async {
        do {
            try await manager.loadFromPreferences()
            updateState()
        } catch {
            lastError = "Ayarlar okunamadı: \(error.localizedDescription)"
        }
    }

    /// Seçilen sunucuyu sistem DNS yapılandırması olarak kaydeder.
    func install(_ resolver: DNSResolver) async {
        if let problem = resolver.validationError {
            lastError = problem
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            try await manager.loadFromPreferences()
            manager.localizedDescription = "AntiDot – \(resolver.name) \(resolver.transport.title)"
            manager.dnsSettings = resolver.makeSystemSettings()
            // Tüm ağlarda (Wi-Fi ve hücresel) şifreli DNS kullan.
            let rule = NEOnDemandRuleConnect()
            rule.interfaceTypeMatch = .any
            manager.onDemandRules = [rule]
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
            lastError = nil
            updateState()
        } catch {
            lastError = "Kaydedilemedi: \(error.localizedDescription)"
        }
    }

    func uninstall() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await manager.loadFromPreferences()
            try await manager.removeFromPreferences()
            try await manager.loadFromPreferences()
            lastError = nil
            updateState()
        } catch {
            lastError = "Kaldırılamadı: \(error.localizedDescription)"
        }
    }

    private func updateState() {
        installedDescription = manager.localizedDescription
        if manager.dnsSettings == nil {
            state = .notInstalled
        } else {
            state = manager.isEnabled ? .active : .installedInactive
        }
    }
}
