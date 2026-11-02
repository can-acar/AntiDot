// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Hazır + kullanıcı tanımlı sunucuları ve seçili sunucuyu saklar.
@MainActor
final class ResolverStore: ObservableObject {
    @Published private(set) var customResolvers: [DNSResolver] = []
    @Published var selectedKey: String {
        didSet { defaults.set(selectedKey, forKey: Keys.selected) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let custom = "antidot.customResolvers"
        static let selected = "antidot.selectedResolver"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.selectedKey = defaults.string(forKey: Keys.selected)
            ?? DNSResolver.presets[0].selectionKey
        if let data = defaults.data(forKey: Keys.custom),
           let decoded = try? JSONDecoder().decode([DNSResolver].self, from: data) {
            customResolvers = decoded
        }
    }

    var allResolvers: [DNSResolver] { DNSResolver.presets + customResolvers }

    var selected: DNSResolver {
        allResolvers.first { $0.selectionKey == selectedKey } ?? DNSResolver.presets[0]
    }

    func add(_ resolver: DNSResolver) {
        var r = resolver
        r.isBuiltIn = false
        customResolvers.append(r)
        persist()
    }

    func update(_ resolver: DNSResolver) {
        guard let i = customResolvers.firstIndex(where: { $0.id == resolver.id }) else { return }
        customResolvers[i] = resolver
        persist()
    }

    func delete(_ resolver: DNSResolver) {
        customResolvers.removeAll { $0.id == resolver.id }
        if selectedKey == resolver.selectionKey {
            selectedKey = DNSResolver.presets[0].selectionKey
        }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(customResolvers) {
            defaults.set(data, forKey: Keys.custom)
        }
    }
}
