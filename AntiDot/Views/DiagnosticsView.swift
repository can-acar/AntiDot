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
    @State private var queriedType: DNSRecordType = .a
    @FocusState private var fieldFocused: Bool

    private let suggestions = ["wikipedia.org", "x.com", "youtube.com", "reddit.com", "archive.org"]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    inputCard

                    if running {
                        ProgressView("Sorgulanıyor…")
                            .frame(maxWidth: .infinity)
                            .card()
                    }

                    if !running && (encrypted != nil || encryptedError != nil) {
                        if (queriedType == .a || queriedType == .aaaa) && encrypted != nil {
                            verdictCard
                        }
                        encryptedCard
                        if queriedType == .a || queriedType == .aaaa {
                            systemCard
                        }
                    }

                    if encrypted == nil && encryptedError == nil && !running {
                        explainer
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
                .animation(.easeInOut(duration: 0.25), value: running)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("DNS Testi")
        }
        .navigationViewStyle(.stack)
    }

    // MARK: Giriş

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "globe").foregroundColor(.secondary)
                TextField("Alan adı", text: $domain)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($fieldFocused)
                    .onSubmit { Task { await run() } }
                if !domain.isEmpty {
                    Button { domain = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(Color(.tertiaryLabel))
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.background))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { s in
                        Button { domain = s } label: {
                            Text(s)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .foregroundColor(domain == s ? .white : .accentColor)
                                .background(Capsule().fill(domain == s ? Color.accentColor : Color.accentColor.opacity(0.12)))
                        }
                    }
                }
            }

            Picker("Kayıt", selection: $type) {
                ForEach([DNSRecordType.a, .aaaa, .cname, .txt]) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            Button {
                Task { await run() }
            } label: {
                Label("Karşılaştır", systemImage: "arrow.left.arrow.right")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(running || domain.trimmingCharacters(in: .whitespaces).isEmpty)

            HStack(spacing: 8) {
                ProviderBadge(resolver: store.selected, size: 22)
                Text("Şifreli sorgu: \(store.selected.name) · \(store.selected.transport.title)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .card()
    }

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Bu test ne yapar?", systemImage: "questionmark.circle.fill")
                .font(.headline)
                .foregroundColor(Theme.indigo)
            Text("Aynı alan adı hem ağınızın kendi DNS'ine hem de şifreli sunucuya sorulur. Cevaplar hiç örtüşmüyorsa ağınız DNS cevaplarını değiştiriyor olabilir.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    // MARK: Sonuçlar

    private var encryptedSet: Set<String> {
        Set(encrypted?.response.answers.filter { $0.type == queriedType.rawValue }.map(\.value) ?? [])
    }

    @ViewBuilder private var verdictCard: some View {
        let enc = encryptedSet
        let sys = Set(system)
        if enc.isEmpty {
            verdict(icon: "questionmark.diamond.fill", color: .secondary,
                    title: "Karşılaştırılamadı",
                    detail: "Şifreli sunucu bu kayıt türü için adres döndürmedi.")
        } else if sys.isEmpty {
            verdict(icon: "hand.raised.fill", color: Theme.coral,
                    title: "Ağınız cevap vermedi",
                    detail: "Şifreli sunucu adresi buldu ama ağınızın DNS'i boş döndü. Alan adı DNS ile engelleniyor olabilir.")
        } else if sys.isDisjoint(with: enc) {
            verdict(icon: "exclamationmark.triangle.fill", color: Theme.amber,
                    title: "Cevaplar örtüşmüyor",
                    detail: "Olası DNS manipülasyonu. CDN kullanan siteler de farklı adres verebilir; birkaç kez deneyin.")
        } else {
            verdict(icon: "checkmark.seal.fill", color: Theme.mint,
                    title: "Cevaplar örtüşüyor",
                    detail: "Ağınızın DNS'i bu alan adı için doğru adres döndürüyor.")
        }
    }

    private func verdict(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(color.opacity(0.35), lineWidth: 1)
        )
    }

    private var encryptedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Şifreli cevap", systemImage: "lock.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Theme.indigo)
                Spacer()
                if let encrypted {
                    LatencyBadge(latency: encrypted.latency)
                }
            }
            if let encryptedError {
                Text(encryptedError).font(.subheadline).foregroundColor(.red)
            } else if let encrypted {
                if encrypted.response.answers.isEmpty {
                    Text("Kayıt yok (\(encrypted.response.rcodeDescription))")
                        .font(.subheadline).foregroundColor(.secondary)
                }
                ForEach(encrypted.response.answers, id: \.self) { a in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.value)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                        Text("\(a.name) · TTL \(a.ttl)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .card()
    }

    private var systemCard: some View {
        let enc = encryptedSet
        return VStack(alignment: .leading, spacing: 10) {
            Label("Ağınızın DNS'i", systemImage: "network")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
            if system.isEmpty {
                Text("Cevap yok / engellendi").font(.subheadline).foregroundColor(Theme.coral)
            }
            ForEach(system, id: \.self) { ip in
                HStack {
                    Text(ip).font(.callout.monospaced()).textSelection(.enabled)
                    Spacer()
                    Image(systemName: enc.contains(ip) ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundColor(enc.contains(ip) ? Theme.mint : Theme.amber)
                }
            }
        }
        .card()
    }

    private func run() async {
        let name = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty, !running else { return }
        fieldFocused = false
        running = true
        defer { running = false }
        encrypted = nil
        encryptedError = nil
        system = []
        queriedType = type
        let recordType = type
        async let sys = SystemResolver.lookup(name)
        do {
            encrypted = try await EncryptedDNSClient().query(name, type: recordType, via: store.selected)
        } catch {
            encryptedError = error.localizedDescription
        }
        let all = await sys
        system = all.filter { recordType == .a ? !$0.contains(":") : $0.contains(":") }
        Theme.haptic(.light)
    }
}
