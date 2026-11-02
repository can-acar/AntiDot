// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import UIKit

/// Uygulamanın renkleri ve ortak görsel bileşenleri.
enum Theme {
    static let indigo = Color(red: 0.23, green: 0.36, blue: 0.99)
    static let violet = Color(red: 0.48, green: 0.25, blue: 0.89)
    static let mint = Color(red: 0.12, green: 0.78, blue: 0.55)
    static let teal = Color(red: 0.04, green: 0.58, blue: 0.76)
    static let amber = Color(red: 1.00, green: 0.66, blue: 0.15)
    static let coral = Color(red: 0.96, green: 0.40, blue: 0.27)

    static let brandGradient = LinearGradient(
        colors: [indigo, violet], startPoint: .topLeading, endPoint: .bottomTrailing)

    static let background = Color(.systemGroupedBackground)
    static let cardBackground = Color(.secondarySystemGroupedBackground)

    @MainActor static func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    @MainActor static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

// MARK: - Durum görünümü

extension DNSSettingsService.State {
    var tint: Color {
        switch self {
        case .active: return Theme.mint
        case .installedInactive: return Theme.amber
        case .notInstalled, .unknown: return Color(.systemGray)
        }
    }

    var gradient: [Color] {
        switch self {
        case .active: return [Theme.mint, Theme.teal]
        case .installedInactive: return [Theme.amber, Theme.coral]
        case .notInstalled, .unknown: return [Color(.systemGray2), Color(.systemGray)]
        }
    }

    var icon: String {
        switch self {
        case .active: return "lock.shield.fill"
        case .installedInactive: return "exclamationmark.shield.fill"
        case .notInstalled, .unknown: return "shield.slash.fill"
        }
    }

    var title: String {
        switch self {
        case .active: return "Korunuyorsunuz"
        case .installedInactive: return "Bir adım kaldı"
        case .notInstalled: return "Koruma kapalı"
        case .unknown: return "Durum okunuyor…"
        }
    }

    var pillText: String {
        switch self {
        case .active: return "ETKİN"
        case .installedInactive: return "BEKLİYOR"
        case .notInstalled: return "KAPALI"
        case .unknown: return "…"
        }
    }
}

// MARK: - Kart

struct CardModifier: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.cardBackground)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardModifier(padding: padding)) }
}

// MARK: - Butonlar

struct PrimaryButtonStyle: ButtonStyle {
    var colors: [Color] = [Theme.indigo, Theme.violet]
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
            )
            .shadow(color: (colors.first ?? .clear).opacity(isEnabled ? 0.35 : 0), radius: 14, x: 0, y: 8)
            .opacity(isEnabled ? 1 : 0.55)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundColor(tint)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.22 : 0.12))
            )
    }
}

// MARK: - Küçük bileşenler

/// Sağlayıcıyı renkli bir harf rozetiyle gösterir.
struct ProviderBadge: View {
    let resolver: DNSResolver
    var size: CGFloat = 42

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(LinearGradient(colors: resolver.brandColors,
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            if resolver.isBuiltIn {
                Text(resolver.monogram)
                    .font(.system(size: size * 0.45, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
            } else {
                Image(systemName: "server.rack")
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .frame(width: size, height: size)
    }
}

struct TransportChip: View {
    let transport: DNSTransport

    var body: some View {
        Text(transport.shortTitle)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundColor(transport == .doh ? Theme.indigo : Theme.violet)
            .background(Capsule().fill((transport == .doh ? Theme.indigo : Theme.violet).opacity(0.14)))
    }
}

/// Bir gecikme ölçümünü renkli nokta ve milisaniye ile gösterir.
struct LatencyBadge: View {
    let latency: TimeInterval?

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption.monospacedDigit().weight(.semibold))
        }
        .foregroundColor(color)
    }

    private var text: String {
        guard let latency else { return "Hata" }
        return "\(Int((latency * 1000).rounded())) ms"
    }

    private var color: Color {
        guard let latency else { return .red }
        switch latency {
        case ..<0.08: return Theme.mint
        case ..<0.2: return Theme.amber
        default: return Theme.coral
        }
    }
}

struct SimulatorBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "iphone.gen3")
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Simülatör demo modu").font(.subheadline.weight(.semibold))
                Text("Sistem DNS ayarı taklit ediliyor. DNS testleri gerçek ağda çalışır.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .foregroundColor(Theme.indigo)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.indigo.opacity(0.1))
        )
    }
}

// MARK: - Sağlayıcı renkleri

extension DNSResolver {
    var monogram: String {
        String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    var brandColors: [Color] {
        guard isBuiltIn else { return [Color(.systemGray), Color(.darkGray)] }
        switch name {
        case "Cloudflare": return [Color(red: 0.98, green: 0.62, blue: 0.20), Color(red: 0.95, green: 0.42, blue: 0.13)]
        case "Google": return [Color(red: 0.26, green: 0.52, blue: 0.96), Color(red: 0.13, green: 0.36, blue: 0.85)]
        case "Quad9": return [Color(red: 0.93, green: 0.23, blue: 0.43), Color(red: 0.72, green: 0.12, blue: 0.38)]
        case "AdGuard": return [Color(red: 0.40, green: 0.75, blue: 0.40), Color(red: 0.18, green: 0.55, blue: 0.32)]
        case "Mullvad": return [Color(red: 0.98, green: 0.80, blue: 0.20), Color(red: 0.86, green: 0.55, blue: 0.10)]
        default: return [Theme.indigo, Theme.violet]
        }
    }

    var tagline: String {
        guard isBuiltIn else { return "Özel sunucu" }
        switch name {
        case "Cloudflare": return "Hızlı, gizlilik odaklı"
        case "Google": return "Yaygın ve kararlı"
        case "Quad9": return "Zararlı alan adlarını engeller"
        case "AdGuard": return "Reklam ve izleyicileri engeller"
        case "Mullvad": return "Kayıt tutmaz, filtresiz"
        default: return ""
        }
    }
}

// MARK: - Gecikme ölçümü

enum LatencyProbe {
    /// Sunucuya küçük bir şifreli sorgu gönderip gidiş-dönüş süresini ölçer.
    static func measure(_ resolver: DNSResolver) async -> TimeInterval? {
        try? await EncryptedDNSClient().query("example.com", type: .a, via: resolver).latency
    }
}
