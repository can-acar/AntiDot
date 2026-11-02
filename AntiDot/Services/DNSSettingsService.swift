// SPDX-License-Identifier: Apache-2.0
import Foundation
import NetworkExtension

/// iOS 14+ `NEDNSSettingsManager` sarmalayıcısı.
///
/// Bu API, VPN kurmadan tüm cihazın DNS trafiğini seçilen DoH/DoT sunucusuna
/// yönlendirir. Yapılandırma kaydedildikten sonra kullanıcının
/// Ayarlar > Genel > VPN ve Aygıt Yönetimi > DNS bölümünden "AntiDot"u
/// bir kez seçmesi gerekir; iOS bunu programatik olarak etkinleştirmeye izin vermez.
///
/// **Simülatör:** iOS Simülatörü sistem DNS ayarlarını uygulamaz. Arayüzün tüm
/// akışı denenebilsin diye simülatörde servis "demo modunda" çalışır: kurulum,
/// etkinleştirme ve kaldırma adımları cihaza dokunmadan taklit edilir.
@MainActor
final class DNSSettingsService: ObservableObject {
    enum State: String, Equatable {
        case unknown
        case notInstalled
        case installedInactive   // Kaydedildi ama Ayarlar'dan seçilmedi
        case active
    }

    #if targetEnvironment(simulator)
    nonisolated static let isSimulated = true
    #else
    nonisolated static let isSimulated = false
    #endif

    @Published private(set) var state: State = .unknown
    @Published private(set) var installedDescription: String?
    @Published var lastError: String?
    @Published private(set) var isBusy = false

    private let simulated: Bool
    private let defaults: UserDefaults
    private var observer: NSObjectProtocol?
    private lazy var manager = NEDNSSettingsManager.shared()

    private enum Keys {
        static let simState = "antidot.sim.state"
        static let simDescription = "antidot.sim.description"
    }

    init(simulated: Bool = DNSSettingsService.isSimulated, defaults: UserDefaults = .standard) {
        self.simulated = simulated
        self.defaults = defaults
        guard !simulated else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .NEDNSSettingsConfigurationDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    var isInstalled: Bool { state == .installedInactive || state == .active }

    func refresh() async {
        if simulated {
            state = defaults.string(forKey: Keys.simState).flatMap(State.init(rawValue:)) ?? .notInstalled
            installedDescription = defaults.string(forKey: Keys.simDescription)
            return
        }
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
        let description = "AntiDot – \(resolver.name) \(resolver.transport.title)"

        if simulated {
            try? await Task.sleep(nanoseconds: 700_000_000)
            setSimulated(state == .active ? .active : .installedInactive, description: description)
            lastError = nil
            return
        }

        do {
            try await manager.loadFromPreferences()
            manager.localizedDescription = description
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

        if simulated {
            try? await Task.sleep(nanoseconds: 400_000_000)
            setSimulated(.notInstalled, description: nil)
            lastError = nil
            return
        }

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

    /// Yalnızca demo modunda: kullanıcının Ayarlar'dan AntiDot'u seçmesini taklit eder.
    func simulateActivation() {
        guard simulated, state == .installedInactive else { return }
        setSimulated(.active, description: installedDescription)
    }

    private func setSimulated(_ newState: State, description: String?) {
        state = newState
        installedDescription = description
        defaults.set(newState.rawValue, forKey: Keys.simState)
        defaults.set(description, forKey: Keys.simDescription)
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
