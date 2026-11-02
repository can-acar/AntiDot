// SPDX-License-Identifier: Apache-2.0
import SwiftUI

/// İlk açılışta gösterilen üç sayfalık tanıtım.
struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var page = 0

    private struct Page {
        let icon: String
        let title: String
        let text: String
    }

    private let pages: [Page] = [
        Page(icon: "eye.slash.fill",
             title: "DNS'iniz açıkta",
             text: "Ziyaret ettiğiniz her sitenin adı ağınıza düz metin olarak gider. İnternet sağlayıcınız bunu görebilir, engelleyebilir ya da sahte cevap verebilir."),
        Page(icon: "lock.shield.fill",
             title: "AntiDot şifreler",
             text: "Tüm DNS sorgularınız DoH veya DoT ile seçtiğiniz güvenilir sunucuya şifreli gider. VPN gerekmez, internet hızınız düşmez."),
        Page(icon: "hand.tap.fill",
             title: "Tek dokunuşla başlayın",
             text: "Korumayı başlatın, ardından iOS'un istediği son adım olarak Ayarlar'dan AntiDot'u seçin. Hepsi bu."),
    ]

    var body: some View {
        ZStack {
            Theme.brandGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if page < pages.count - 1 {
                        Button("Geç", action: onFinish)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white.opacity(0.85))
                    }
                }
                .frame(height: 44)
                .padding(.horizontal, 24)

                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { i in
                        pageView(pages[i]).tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                Button {
                    Theme.haptic()
                    if page < pages.count - 1 {
                        withAnimation { page += 1 }
                    } else {
                        onFinish()
                    }
                } label: {
                    Text(page < pages.count - 1 ? "Devam" : "Başlayalım")
                        .font(.headline)
                        .foregroundColor(Theme.indigo)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    private func pageView(_ p: Page) -> some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle().fill(Color.white.opacity(0.12)).frame(width: 200, height: 200)
                Circle().fill(Color.white.opacity(0.18)).frame(width: 150, height: 150)
                Image(systemName: p.icon)
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundColor(.white)
            }
            VStack(spacing: 12) {
                Text(p.title)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .multilineTextAlignment(.center)
                Text(p.text)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .opacity(0.9)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
    }
}
