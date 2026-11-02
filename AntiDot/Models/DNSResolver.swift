// SPDX-License-Identifier: Apache-2.0
import Foundation
import NetworkExtension

/// Şifreli DNS taşıma protokolü.
enum DNSTransport: String, Codable, CaseIterable, Identifiable {
    case doh   // DNS over HTTPS (RFC 8484), port 443
    case dot   // DNS over TLS (RFC 7858), port 853

    var id: String { rawValue }

    var title: String {
        switch self {
        case .doh: return "DoH (HTTPS)"
        case .dot: return "DoT (TLS)"
        }
    }

    var shortTitle: String {
        switch self {
        case .doh: return "DoH"
        case .dot: return "DoT"
        }
    }

    var port: Int {
        switch self {
        case .doh: return 443
        case .dot: return 853
        }
    }
}

/// Bir şifreli DNS sunucusunun tanımı.
///
/// `bootstrapServers`: Sunucunun IP adresleri. iOS, DoH/DoT sunucusunun adını
/// çözmek için düz (şifresiz) DNS kullanmasın diye bunları doğrudan bağlantı
/// adresi olarak kullanır. Bu, "bootstrap" aşamasındaki manipülasyonu da engeller.
struct DNSResolver: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var transport: DNSTransport
    /// DoH için tam URL, ör. https://cloudflare-dns.com/dns-query
    var dohURL: String?
    /// DoT için TLS sertifika adı (SNI), ör. one.one.one.one
    var dotServerName: String?
    var bootstrapServers: [String]
    var isBuiltIn: Bool = false

    /// Kullanıcıya gösterilecek uç nokta.
    var endpointDescription: String {
        switch transport {
        case .doh: return dohURL ?? "-"
        case .dot: return "tls://\(dotServerName ?? "-")"
        }
    }

    /// Doğrulama hatası varsa Türkçe açıklamasını döner.
    var validationError: String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "İsim boş olamaz." }
        if bootstrapServers.isEmpty { return "En az bir IP adresi gerekli." }
        if let bad = bootstrapServers.first(where: { !IPAddressValidator.isValid($0) }) {
            return "Geçersiz IP adresi: \(bad)"
        }
        switch transport {
        case .doh:
            guard let s = dohURL, let url = URL(string: s), url.scheme == "https", url.host != nil else {
                return "DoH adresi https:// ile başlayan geçerli bir URL olmalı."
            }
        case .dot:
            guard let n = dotServerName, !n.isEmpty, !n.contains("/") else {
                return "DoT için sunucu adı (ör. dns.google) gerekli."
            }
        }
        return nil
    }

    /// NetworkExtension'ın sistem geneli DNS ayar nesnesini üretir.
    func makeSystemSettings() -> NEDNSSettings {
        switch transport {
        case .doh:
            let settings = NEDNSOverHTTPSSettings(servers: bootstrapServers)
            settings.serverURL = dohURL.flatMap(URL.init(string:))
            return settings
        case .dot:
            let settings = NEDNSOverTLSSettings(servers: bootstrapServers)
            settings.serverName = dotServerName
            return settings
        }
    }
}

// MARK: - Hazır sunucular

extension DNSResolver {
    private static func pair(
        _ name: String, doh: String, dot: String, ips: [String]
    ) -> [DNSResolver] {
        [
            DNSResolver(name: name, transport: .doh, dohURL: doh, dotServerName: nil,
                        bootstrapServers: ips, isBuiltIn: true),
            DNSResolver(name: name, transport: .dot, dohURL: nil, dotServerName: dot,
                        bootstrapServers: ips, isBuiltIn: true),
        ]
    }

    /// Kalıcı seçim anahtarı. Hazır sunucuların UUID'si her açılışta değiştiği için
    /// onlar isim+protokol ile, özel sunucular UUID ile saklanır.
    var selectionKey: String {
        isBuiltIn ? "preset:\(name)|\(transport.rawValue)" : "custom:\(id.uuidString)"
    }

    static let presets: [DNSResolver] =
        pair("Cloudflare", doh: "https://cloudflare-dns.com/dns-query", dot: "one.one.one.one",
             ips: ["1.1.1.1", "1.0.0.1", "2606:4700:4700::1111", "2606:4700:4700::1001"])
        + pair("Google", doh: "https://dns.google/dns-query", dot: "dns.google",
               ips: ["8.8.8.8", "8.8.4.4", "2001:4860:4860::8888", "2001:4860:4860::8844"])
        + pair("Quad9", doh: "https://dns.quad9.net/dns-query", dot: "dns.quad9.net",
               ips: ["9.9.9.9", "149.112.112.112", "2620:fe::fe", "2620:fe::9"])
        + pair("AdGuard", doh: "https://dns.adguard-dns.com/dns-query", dot: "dns.adguard-dns.com",
               ips: ["94.140.14.14", "94.140.15.15", "2a10:50c0::ad1:ff", "2a10:50c0::ad2:ff"])
        + pair("Mullvad", doh: "https://dns.mullvad.net/dns-query", dot: "dns.mullvad.net",
               ips: ["194.242.2.2", "2a07:e340::2"])
}

enum IPAddressValidator {
    static func isValid(_ string: String) -> Bool {
        var v4 = in_addr()
        var v6 = in6_addr()
        return inet_pton(AF_INET, string, &v4) == 1 || inet_pton(AF_INET6, string, &v6) == 1
    }
}
