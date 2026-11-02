// SPDX-License-Identifier: Apache-2.0
import SwiftUI

struct ResolverListView: View {
    @EnvironmentObject private var store: ResolverStore
    @EnvironmentObject private var dns: DNSSettingsService
    @State private var editing: DNSResolver?
    @State private var latencies: [String: TimeInterval?] = [:]
    @State private var probing = false

    var body: some View {
        List {
            Section {
                ForEach(DNSResolver.presets) { row($0) }
            } header: {
                Text("Hazır sunucular")
            } footer: {
                Text("DoH (HTTPS) çoğu ağda en iyi çalışır, çünkü normal web trafiğinden ayırt edilmesi zordur. DoT (TLS) 853 portunu kullanır ve bazı ağlarda engellenebilir.")
            }

            Section {
                ForEach(store.customResolvers) { resolver in
                    row(resolver)
                        .swipeActions {
                            Button(role: .destructive) { store.delete(resolver) } label: {
                                Label("Sil", systemImage: "trash")
                            }
                            Button { editing = resolver } label: {
                                Label("Düzenle", systemImage: "pencil")
                            }
                            .tint(Theme.indigo)
                        }
                }
                Button {
                    editing = DNSResolver(name: "", transport: .doh, dohURL: "https://",
                                          dotServerName: nil, bootstrapServers: [])
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                                .foregroundColor(.accentColor)
                            Image(systemName: "plus").font(.headline)
                        }
                        .frame(width: 42, height: 42)
                        Text("Özel sunucu ekle").font(.body.weight(.semibold))
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Özel sunucular")
            } footer: {
                Text("Seçim değiştiğinde sistem ayarı otomatik güncellenir (kuruluysa).")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Sunucular")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await probeAll() }
                } label: {
                    if probing {
                        ProgressView()
                    } else {
                        Label("Hız testi", systemImage: "speedometer")
                    }
                }
                .disabled(probing)
            }
        }
        .sheet(item: $editing) { resolver in
            ResolverEditView(resolver: resolver) { saved in
                if store.customResolvers.contains(where: { $0.id == saved.id }) {
                    store.update(saved)
                } else {
                    store.add(saved)
                }
            }
        }
    }

    private func row(_ resolver: DNSResolver) -> some View {
        let isSelected = resolver.selectionKey == store.selectedKey
        return Button {
            Theme.haptic(.light)
            withAnimation(.easeInOut(duration: 0.2)) { store.selectedKey = resolver.selectionKey }
            if dns.isInstalled {
                Task { await dns.install(resolver) }
            }
        } label: {
            HStack(spacing: 14) {
                ProviderBadge(resolver: resolver)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(resolver.name)
                            .font(.body.weight(.semibold))
                            .foregroundColor(.primary)
                        TransportChip(transport: resolver.transport)
                    }
                    Text(resolver.isBuiltIn ? resolver.tagline : resolver.endpointDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 4)
                if let measured = latencies[resolver.selectionKey] {
                    LatencyBadge(latency: measured)
                }
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? .accentColor : Color(.tertiaryLabel))
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Tüm sunuculara aynı anda küçük bir sorgu gönderip gecikmeleri gösterir.
    private func probeAll() async {
        probing = true
        latencies = [:]
        let resolvers = store.allResolvers
        await withTaskGroup(of: (String, TimeInterval?).self) { group in
            for resolver in resolvers {
                group.addTask { (resolver.selectionKey, await LatencyProbe.measure(resolver)) }
            }
            for await (key, value) in group {
                withAnimation { latencies[key] = .some(value) }
            }
        }
        probing = false
        Theme.success()
    }
}

struct ResolverEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State var resolver: DNSResolver
    @State private var ipText: String
    let onSave: (DNSResolver) -> Void

    init(resolver: DNSResolver, onSave: @escaping (DNSResolver) -> Void) {
        _resolver = State(initialValue: resolver)
        _ipText = State(initialValue: resolver.bootstrapServers.joined(separator: ", "))
        self.onSave = onSave
    }

    private var draft: DNSResolver {
        var r = resolver
        r.bootstrapServers = ipText
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" })
            .map(String.init)
        if r.transport == .doh { r.dotServerName = nil } else { r.dohURL = nil }
        return r
    }

    var body: some View {
        NavigationView {
            Form {
                TextField("İsim", text: $resolver.name)
                Picker("Protokol", selection: $resolver.transport) {
                    ForEach(DNSTransport.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                if resolver.transport == .doh {
                    TextField("https://ornek.com/dns-query", text: Binding(
                        get: { resolver.dohURL ?? "" }, set: { resolver.dohURL = $0 }))
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                } else {
                    TextField("dns.ornek.com", text: Binding(
                        get: { resolver.dotServerName ?? "" }, set: { resolver.dotServerName = $0 }))
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                }

                Section {
                    TextField("1.1.1.1, 2606:4700:4700::1111", text: $ipText)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: {
                    Text("Sunucu IP adresleri")
                } footer: {
                    Text("Sunucu adının düz DNS ile çözülmemesi için IP adresleri gereklidir.")
                }

                if let error = draft.validationError {
                    Text(error).foregroundColor(.red).font(.footnote)
                }
            }
            .navigationTitle("Sunucu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { onSave(draft); dismiss() }
                        .disabled(draft.validationError != nil)
                }
            }
        }
    }
}
