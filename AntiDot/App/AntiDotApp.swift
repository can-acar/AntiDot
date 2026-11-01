// SPDX-License-Identifier: Apache-2.0
import SwiftUI

@main
struct AntiDotApp: App {
    @StateObject private var store = ResolverStore()
    @StateObject private var dnsService = DNSSettingsService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(dnsService)
                .task { await dnsService.refresh() }
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            ProtectionView()
                .tabItem { Label("Koruma", systemImage: "lock.shield") }
            ResolverListView()
                .tabItem { Label("Sunucular", systemImage: "server.rack") }
            DiagnosticsView()
                .tabItem { Label("Test", systemImage: "stethoscope") }
        }
    }
}
