# AntiDot

**AntiDot**, iPhone ve iPad'de tüm DNS trafiğinizi **DNS over HTTPS (DoH)** veya
**DNS over TLS (DoT)** ile şifreleyen, açık kaynaklı (Apache 2.0) bir iOS uygulamasıdır.
Amacı, internet servis sağlayıcısı ya da ağ yöneticisi tarafından yapılan DNS
manipülasyonunu (sahte cevap, DNS tabanlı engelleme, enjeksiyon, gözetleme)
herkesin kolayca atlatabilmesidir.

## Özellikler

- Sistem geneli şifreli DNS: Safari dahil tüm uygulamalar etkilenir, VPN gerekmez.
- Hazır sunucular: Cloudflare, Google, Quad9, AdGuard, Mullvad (her biri DoH ve DoT).
- Özel sunucu ekleme (kendi DoH URL'niz veya DoT adınız + IP adresleri).
- **DNS Testi** sekmesi: bir alan adını hem ağın kendi DNS'iyle hem de şifreli
  sunucuyla sorgular, cevaplar örtüşmüyorsa olası manipülasyonu gösterir.
- Wi-Fi ve hücresel ağlarda otomatik etkin.

## Nasıl çalışır?

```
 Uygulamalar ──► iOS DNS çözümleyicisi ──(NEDNSSettingsManager ayarı)──►
     DoH: HTTPS/443  ──► https://cloudflare-dns.com/dns-query
     DoT: TLS/853    ──► one.one.one.one (1.1.1.1)
```

| Katman | Dosya | Görev |
|---|---|---|
| Sistem ayarı | `AntiDot/Services/DNSSettingsService.swift` | `NEDNSSettingsManager` ile DoH/DoT yapılandırmasını kaydeder, kaldırır, durumu izler |
| Model | `AntiDot/Models/DNSResolver.swift` | Sunucu tanımı, hazır sunucular, `NEDNSOverHTTPSSettings` / `NEDNSOverTLSSettings` üretimi |
| Saklama | `AntiDot/Models/ResolverStore.swift` | Özel sunucular ve seçim (`UserDefaults`) |
| Test istemcisi | `AntiDot/Services/EncryptedDNSClient.swift` | Uygulama içinden RFC 8484 DoH (POST) ve RFC 7858 DoT sorgusu, sistem çözümleyicisiyle karşılaştırma |
| DNS kodlama | `AntiDot/Services/DNSMessage.swift` | RFC 1035 sorgu üretimi ve cevap ayrıştırma (sıkıştırma işaretçileri dahil) |
| Arayüz | `AntiDot/Views/*` | SwiftUI: Koruma, Sunucular, Test sekmeleri |

**Bootstrap koruması:** Her sunucu için IP adresleri de verilir. iOS, sunucunun adını
çözmek için düz DNS'e başvurmak yerine doğrudan bu IP'lere bağlanır ve TLS sertifikasını
sunucu adına göre doğrular. Böylece ilk adımda da manipülasyon yapılamaz.

## Kurulum (geliştirici)

Gereksinimler: macOS, Xcode 15+, iOS 15+ cihaz, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
open AntiDot.xcodeproj
```

1. Xcode > AntiDot hedefi > *Signing & Capabilities*: kendi Team'inizi seçin
   (veya `project.yml` içindeki `DEVELOPMENT_TEAM` değerini doldurun).
2. `PRODUCT_BUNDLE_IDENTIFIER` değerini kendinize ait bir kimlikle değiştirin.
3. *Network Extensions* yeteneğinde **DNS Settings** işaretli olmalı
   (`AntiDot.entitlements` içinde `dns-settings` zaten tanımlı).
4. Gerçek cihazda çalıştırın, **Şifreli DNS'i kur**'a dokunun.
5. **Ayarlar › Genel › VPN ve Aygıt Yönetimi › DNS** bölümünden **AntiDot**'u seçin.

Testler: `xcodebuild test -project AntiDot.xcodeproj -scheme AntiDot -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO`

## iOS kısıtları ve bilinmesi gerekenler

- **Ücretli Apple Developer Program üyeliği gerekir.** Network Extension yetenekleri
  ücretsiz (kişisel) hesaplarla imzalanamaz.
- **Son adım kullanıcıda.** iOS, uygulamanın DNS ayarını kendi kendine etkinleştirmesine
  izin vermez; kullanıcı Ayarlar'dan bir kez seçmelidir.
- **VPN önceliklidir.** Aktif bir VPN kendi DNS'ini dayatırsa AntiDot ayarı devre dışı kalır.
- **Sadece DNS'i korur.** DoH/DoT, alan adı sorgularını şifreler; ancak bağlantının
  hedef IP'si ve TLS SNI alanı hâlâ görünür. IP veya SNI tabanlı engellemeleri tek başına
  aşmaz. Bunun için ECH destekli tarayıcı, VPN veya Tor gibi ek çözümler gerekir.
- **Kaptif portallar** (otel/havalimanı Wi-Fi) bazen şifreli DNS ile açılmaz; iOS bu
  durumda geçici olarak ağın DNS'ine dönebilir.
- **Simülatör** sistem DNS ayarını uygulamaz; bunu gerçek cihazda test edin.
  DNS Testi sekmesi ise simülatörde de çalışır.

## Yol haritası (öneriler)

- Packet Tunnel tabanlı mod (DNS + basit engelleme listeleri)
- Oturum açılışında sunucu gecikme testi ve otomatik en hızlı sunucu seçimi
- `.mobileconfig` profil dışa aktarma (MDM / uygulamasız kullanım)
- İngilizce yerelleştirme

## Katkı

Bu proje herkesin yararına geliştirilmektedir. Hata bildirimi ve pull request'ler memnuniyetle karşılanır.

## Lisans

[Apache License 2.0](LICENSE). Ayrıntılar için `LICENSE` ve `NOTICE` dosyalarına bakın.
