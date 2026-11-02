// SPDX-License-Identifier: Apache-2.0
import NetworkExtension
import SwiftUI

struct TunnelCard: View {
    @EnvironmentObject private var store: ResolverStore
    @EnvironmentObject private var dns: DNSSettingsService
    @EnvironmentObject private var tunnel: TunnelService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Tünel modu", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.headline)
                Text("DENEYSEL")
                    .font(.caption2.weight(.heavy))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .foregroundColor(Theme.amber)
                    .background(Capsule().fill(Theme.amber.opacity(0.15)))
                Spacer()
                Text(statusText).font(.caption).foregroundColor(.secondary)
            }
            Text("DNS sorgularını yerel bir VPN tüneliyle yakalar ve \(store.selected.name) sunucusunun DoH ve DoT uçlarına aynı anda gönderir. Açıkken başka bir VPN kullanılamaz.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if tunnel.isRunning, let name = tunnel.configuredName, name != store.selected.name {
                Text("Tünel hâlâ \(name) ile çalışıyor; yeni sunucu için durdurup yeniden başlatın.")
                    .font(.footnote)
                    .foregroundColor(Theme.amber)
            }
            if dns.isInstalled && !tunnel.isRunning {
                Text("Önce DNS yapılandırmasını kaldırın; iki mod aynı anda çalışmaz.")
                    .font(.footnote)
                    .foregroundColor(Theme.amber)
            }
            Button {
                Theme.haptic()
                if tunnel.isRunning {
                    tunnel.stop()
                } else {
                    Task { await tunnel.start(store.selected.redundantGroup) }
                }
            } label: {
                Label(tunnel.isRunning ? "Tüneli durdur" : "Tüneli başlat",
                      systemImage: tunnel.isRunning ? "stop.fill" : "play.fill")
            }
            .buttonStyle(SecondaryButtonStyle(tint: tunnel.isRunning ? .red : Theme.indigo))
            .disabled(tunnel.isBusy || (dns.isInstalled && !tunnel.isRunning))
            if let error = tunnel.lastError {
                Text(error).font(.footnote).foregroundColor(.red)
            }
        }
        .card()
        .task { await tunnel.refresh() }
    }

    private var statusText: String {
        switch tunnel.status {
        case .connected: return "Bağlı"
        case .connecting, .reasserting: return "Bağlanıyor…"
        case .disconnecting: return "Kapanıyor…"
        case .disconnected: return "Kapalı"
        default: return "Kurulmadı"
        }
    }
}
