// SPDX-License-Identifier: Apache-2.0
import SwiftUI

struct ResolverListView: View {
    @EnvironmentObject private var store: ResolverStore
    @EnvironmentObject private var dns: DNSSettingsService
    @State private var editing: DNSResolver?

    var body: some View {
        List {
            Section("Hazır sunucular") {
                ForEach(DNSResolver.presets) { row($0) }
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
                        }
                }
                Button {
                    editing = DNSResolver(name: "", transport: .doh, dohURL: "https://",
                                          dotServerName: nil, bootstrapServers: [])
                } label: {
                    Label("Özel sunucu ekle", systemImage: "plus")
                }
            } header: {
                Text("Özel sunucular")
            } footer: {
                Text("Seçim değiştiğinde sistem ayarı otomatik güncellenir (kuruluysa).")
            }
        }
        .navigationTitle("Sunucular")
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
        Button {
            store.selectedKey = resolver.selectionKey
            if dns.state != .notInstalled && dns.state != .unknown {
                Task { await dns.install(resolver) }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(resolver.name) · \(resolver.transport.title)").foregroundColor(.primary)
                    Text(resolver.endpointDescription).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                if resolver.selectionKey == store.selectedKey {
                    Image(systemName: "checkmark").foregroundColor(.accentColor)
                }
            }
        }
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
