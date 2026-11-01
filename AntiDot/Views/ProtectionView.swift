// SPDX-License-Identifier: Apache-2.0
import SwiftUI

struct ProtectionView: View {
    @EnvironmentObject private var store: ResolverStore
    @EnvironmentObject private var dns: DNSSettingsService
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: statusIcon)
                            .font(.system(size: 44))
                            .foregroundColor(statusColor)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(statusTitle).font(.headline)
                            Text(statusDetail).font(.subheadline).foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section("Seçili sunucu") {
                    NavigationLink(destination: ResolverListView()) {
                        VStack(alignment: .leading) {
                            Text("\(store.selected.name) · \(store.selected.transport.title)")
                            Text(store.selected.endpointDescription)
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }

                Section {
                    Button {
                        Task { await dns.install(store.selected) }
                    } label: {
                        Label(dns.state == .notInstalled ? "Şifreli DNS'i kur" : "Seçili sunucuyu uygula",
                              systemImage: "checkmark.shield")
                    }
                    .disabled(dns.isBusy)

                    if dns.state == .installedInactive {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("Ayarlar'ı aç", systemImage: "gear")
                        }
                    }

                    if dns.state != .notInstalled && dns.state != .unknown {
                        Button(role: .destructive) {
                            Task { await dns.uninstall() }
                        } label: {
                            Label("Yapılandırmayı kaldır", systemImage: "trash")
                        }
                        .disabled(dns.isBusy)
                    }
                } footer: {
                    if dns.state == .installedInactive {
                        Text("iOS güvenlik gereği son adımı sizin yapmanız gerekir: Ayarlar › Genel › VPN ve Aygıt Yönetimi › DNS › AntiDot'u seçin.")
                    }
                }

                if let error = dns.lastError {
                    Section("Hata") {
                        Text(error).foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("AntiDot")
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { Task { await dns.refresh() } }
        }
    }

    private var statusIcon: String {
        switch dns.state {
        case .active: return "lock.shield.fill"
        case .installedInactive: return "exclamationmark.shield"
        default: return "shield.slash"
        }
    }

    private var statusColor: Color {
        switch dns.state {
        case .active: return .green
        case .installedInactive: return .orange
        default: return .secondary
        }
    }

    private var statusTitle: String {
        switch dns.state {
        case .active: return "Koruma etkin"
        case .installedInactive: return "Kuruldu, etkin değil"
        case .notInstalled: return "Koruma kapalı"
        case .unknown: return "Durum okunuyor…"
        }
    }

    private var statusDetail: String {
        switch dns.state {
        case .active: return dns.installedDescription ?? "DNS sorguları şifreleniyor."
        case .installedInactive: return "Ayarlar'dan AntiDot'u DNS olarak seçin."
        case .notInstalled: return "DNS sorgularınız şu an şifresiz gidiyor."
        case .unknown: return ""
        }
    }
}
