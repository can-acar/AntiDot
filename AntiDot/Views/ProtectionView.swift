// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import UIKit

struct ProtectionView: View {
    @EnvironmentObject private var store: ResolverStore
    @EnvironmentObject private var dns: DNSSettingsService
    @Environment(\.scenePhase) private var scenePhase

    @State private var latency: TimeInterval??
    @State private var measuring = false
    @State private var confirmUninstall = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 18) {
                    if DNSSettingsService.isSimulated { SimulatorBanner() }

                    header

                    primaryButton

                    if dns.state == .installedInactive {
                        activationCard
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    serverCard

                    statsGrid

                    if let error = dns.lastError {
                        errorCard(error)
                    }

                    if dns.isInstalled {
                        Button(role: .destructive) {
                            confirmUninstall = true
                        } label: {
                            Label("Yapılandırmayı kaldır", systemImage: "trash")
                        }
                        .buttonStyle(SecondaryButtonStyle(tint: .red))
                        .disabled(dns.isBusy)
                    }

                    Text("AntiDot yalnızca DNS sorgularını şifreler; trafiğinizi başka bir sunucuya yönlendirmez ve kayıt tutmaz.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: dns.state)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("AntiDot")
            .confirmationDialog("AntiDot yapılandırması kaldırılsın mı?",
                                isPresented: $confirmUninstall, titleVisibility: .visible) {
                Button("Kaldır", role: .destructive) { Task { await dns.uninstall() } }
                Button("Vazgeç", role: .cancel) {}
            } message: {
                Text("DNS sorgularınız yeniden şifresiz gönderilir.")
            }
        }
        .navigationViewStyle(.stack)
        .onChange(of: scenePhase) { phase in
            if phase == .active { Task { await dns.refresh() } }
        }
        .onChange(of: store.selectedKey) { _ in latency = nil }
    }

    // MARK: Başlık

    private var header: some View {
        VStack(spacing: 14) {
            ShieldHero(state: dns.state)

            Text(dns.state.pillText)
                .font(.caption.weight(.heavy))
                .tracking(1.2)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .foregroundColor(dns.state.tint)
                .background(Capsule().fill(dns.state.tint.opacity(0.15)))

            Text(dns.state.title)
                .font(.system(.title, design: .rounded).weight(.bold))

            Text(statusDetail)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
        }
        .padding(.top, 4)
    }

    private var statusDetail: String {
        switch dns.state {
        case .active:
            return "Tüm DNS sorgularınız \(dns.installedDescription.map { $0.replacingOccurrences(of: "AntiDot – ", with: "") } ?? "seçili sunucu") üzerinden şifreleniyor."
        case .installedInactive:
            return "Yapılandırma kaydedildi. iOS gereği son adımı Ayarlar'dan siz yapmalısınız."
        case .notInstalled:
            return "DNS sorgularınız şu an şifresiz gidiyor; ağınız bunları görebilir ve değiştirebilir."
        case .unknown:
            return " "
        }
    }

    // MARK: Ana buton

    private var primaryButton: some View {
        Button {
            Theme.haptic()
            Task { await dns.install(store.selected) }
        } label: {
            HStack(spacing: 10) {
                if dns.isBusy {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: dns.state == .notInstalled ? "power" : "arrow.triangle.2.circlepath")
                }
                Text(primaryTitle)
            }
        }
        .buttonStyle(PrimaryButtonStyle(colors: dns.state == .active
                                        ? [Theme.mint, Theme.teal]
                                        : [Theme.indigo, Theme.violet]))
        .disabled(dns.isBusy || dns.state == .unknown)
    }

    private var primaryTitle: String {
        if dns.isBusy { return "Uygulanıyor…" }
        switch dns.state {
        case .notInstalled, .unknown: return "Korumayı başlat"
        case .installedInactive, .active: return "Seçili sunucuyu uygula"
        }
    }

    // MARK: Etkinleştirme adımları

    private var activationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Son adım: Ayarlar'da AntiDot'u seçin", systemImage: "hand.tap.fill")
                .font(.headline)
                .foregroundColor(Theme.amber)

            VStack(alignment: .leading, spacing: 10) {
                StepRow(number: 1, text: "Ayarlar uygulamasını açın")
                StepRow(number: 2, text: "Genel › VPN ve Aygıt Yönetimi")
                StepRow(number: 3, text: "DNS bölümüne dokunun")
                StepRow(number: 4, text: "AntiDot'u seçin")
            }

            if DNSSettingsService.isSimulated {
                Button {
                    dns.simulateActivation()
                    Theme.success()
                } label: {
                    Label("Etkinleştirmeyi simüle et", systemImage: "wand.and.stars")
                }
                .buttonStyle(SecondaryButtonStyle(tint: Theme.amber))
            } else {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Ayarlar'ı aç", systemImage: "gear")
                }
                .buttonStyle(SecondaryButtonStyle(tint: Theme.amber))
            }
        }
        .card()
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Theme.amber.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: Sunucu kartı

    private var serverCard: some View {
        NavigationLink(destination: ResolverListView()) {
            HStack(spacing: 14) {
                ProviderBadge(resolver: store.selected, size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text("SEÇİLİ SUNUCU")
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundColor(.secondary)
                    HStack(spacing: 6) {
                        Text(store.selected.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                        TransportChip(transport: store.selected.transport)
                    }
                    Text(store.selected.endpointDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(Color(.tertiaryLabel))
            }
            .card()
        }
        .buttonStyle(.plain)
    }

    // MARK: Bilgi kutuları

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                  spacing: 12) {
            StatTile(icon: "lock.fill", title: "Şifreleme",
                     value: store.selected.transport == .doh ? "HTTPS" : "TLS", tint: Theme.indigo)
            StatTile(icon: "number", title: "Port",
                     value: "\(store.selected.transport.port)", tint: Theme.violet)
            StatTile(icon: "wifi", title: "Ağlar", value: "Wi‑Fi + Hücresel", tint: Theme.teal)
            latencyTile
        }
    }

    private var latencyTile: some View {
        Button {
            Task { await measure() }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "speedometer")
                    .font(.headline)
                    .foregroundColor(Theme.coral)
                Text("Gecikme")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Group {
                    if measuring {
                        ProgressView()
                    } else if let latency {
                        LatencyBadge(latency: latency)
                    } else {
                        Text("Ölçmek için dokunun")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.accentColor)
                    }
                }
                .frame(height: 20, alignment: .leading)
            }
            .card(padding: 14)
        }
        .buttonStyle(.plain)
        .disabled(measuring)
    }

    private func measure() async {
        measuring = true
        Theme.haptic(.light)
        let result = await LatencyProbe.measure(store.selected)
        latency = .some(result)
        measuring = false
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
            Text(message).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                dns.lastError = nil
            } label: {
                Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundColor(.secondary)
            }
        }
        .card()
    }
}

// MARK: - Yardımcı görünümler

/// Durumu renkli, nefes alan bir kalkanla gösterir.
struct ShieldHero: View {
    let state: DNSSettingsService.State
    @State private var breathe = false

    var body: some View {
        ZStack {
            ForEach(0..<3) { i in
                Circle()
                    .fill(state.tint.opacity(0.10 - Double(i) * 0.03))
                    .frame(width: 140 + CGFloat(i) * 46, height: 140 + CGFloat(i) * 46)
                    .scaleEffect(breathe && state == .active ? 1.0 + CGFloat(i + 1) * 0.03 : 1.0)
            }
            Circle()
                .fill(LinearGradient(colors: state.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 132, height: 132)
                .shadow(color: state.tint.opacity(0.45), radius: 22, x: 0, y: 12)
            Image(systemName: state.icon)
                .font(.system(size: 58, weight: .semibold))
                .foregroundColor(.white)
                .id(state)
                .transition(.scale.combined(with: .opacity))
        }
        .frame(height: 236)
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.title)
    }
}

struct StepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Theme.amber))
            Text(text).font(.subheadline)
        }
    }
}

struct StatTile: View {
    let icon: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundColor(tint)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(height: 20, alignment: .leading)
        }
        .card(padding: 14)
    }
}
