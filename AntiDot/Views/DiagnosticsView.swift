// SPDX-License-Identifier: Apache-2.0
import SwiftUI

/// Bir alan adını hem sistem çözümleyicisiyle hem de seçili şifreli sunucuyla sorgular.
/// Sonuçlar farklıysa ağdaki DNS'in cevabı değiştiriyor olabileceğini gösterir.
struct DiagnosticsView: View {
    @EnvironmentObject private var store: ResolverStore
    @State private var domain = "wikipedia.org"
    @State private var type: DNSRecordType = .a
    @State private var running = false
    @State private var encrypted: EncryptedDNSClient.Result?
    @State private var encryptedError: String?
    @State private var system: [String] = []

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Alan adı", text: $domain)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Picker("Kayıt", selection: $type) {
                        ForEach([DNSRecordType.a, .aaaa, .cname, .txt]) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Button(running ? "Sorgulanıyor…" : "Karşılaştır") { Task { await run() } }
                        .disabled(running || domain.isEmpty)
                } footer: {
                    Text("Şifreli sorgu: \(store.selected.name) · \(store.selected.transport.title)")
                }

                if let encrypted {
                    Section("Şifreli cevap (\(Int(encrypted.latency * 1000)) ms, \(encrypted.response.rcodeDescription))") {
                        if encrypted.response.answers.isEmpty { Text("Kayıt yok").foregroundColor(.secondary) }
                        ForEach(encrypted.response.answers, id: \.self) { a in
                            VStack(alignment: .leading) {
                                Text(a.value).font(.body.monospaced())
                                Text("\(a.name) · TTL \(a.ttl)").font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }
                if let encryptedError {
                    Section("Şifreli sorgu hatası") { Text(encryptedError).foregroundColor(.red) }
                }

                if encrypted != nil, type == .a || type == .aaaa {
                    Section("Sistem çözümleyicisi") {
                        if system.isEmpty { Text("Cevap yok / engellendi").foregroundColor(.orange) }
                        ForEach(system, id: \.self) { Text($0).font(.body.monospaced()) }
                    }
                    Section { verdict }
                }
            }
            .navigationTitle("DNS Testi")
        }
    }

    @ViewBuilder private var verdict: some View {
        let encSet = Set(encrypted?.response.answers
            .filter { $0.type == type.rawValue }.map(\.value) ?? [])
        let sysSet = Set(system)
        if encSet.isEmpty {
            Text("Karşılaştırılacak şifreli kayıt yok.").foregroundColor(.secondary)
        } else if sysSet.isDisjoint(with: encSet) {
            Label("Sistem cevabı şifreli cevapla hiç örtüşmüyor. DNS manipülasyonu olabilir (CDN farkları da buna yol açabilir).",
                  systemImage: "exclamationmark.triangle.fill").foregroundColor(.orange)
        } else {
            Label("Cevaplar örtüşüyor.", systemImage: "checkmark.seal.fill").foregroundColor(.green)
        }
    }

    private func run() async {
        running = true
        defer { running = false }
        encrypted = nil
        encryptedError = nil
        let name = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        async let sys = SystemResolver.lookup(name)
        do {
            encrypted = try await EncryptedDNSClient().query(name, type: type, via: store.selected)
        } catch {
            encryptedError = error.localizedDescription
        }
        let all = await sys
        system = all.filter { type == .a ? !$0.contains(":") : $0.contains(":") }
    }
}
