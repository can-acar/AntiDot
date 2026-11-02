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
| Arayüz | `AntiDot/Views/*` | SwiftUI: tanıtım, Koruma, Sunucular, Test sekmeleri; ortak tema `Theme.swift` |

**Bootstrap koruması:** Her sunucu için IP adresleri de verilir. iOS, sunucunun adını
çözmek için düz DNS'e başvurmak yerine doğrudan bu IP'lere bağlanır ve TLS sertifikasını
sunucu adına göre doğrular. Böylece ilk adımda da manipülasyon yapılamaz.

## iOS Simülatörde deneme (en hızlı yol)

Gereksinimler: Mac, Xcode 16+ (bir iPhone simülatörü yüklü), [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
git clone https://github.com/can-acar/AntiDot.git && cd AntiDot
xcodegen generate
open AntiDot.xcodeproj
```

1. Xcode üst çubuğunda şema olarak **AntiDot**, hedef olarak bir simülatör seçin (ör. **iPhone 16 Pro**).
2. ▶︎ (Cmd+R). Simülatör için cihaz kaydı veya provisioning profili gerekmez.
3. İlk açılışta tanıtım ekranları gelir. Ardından:
   - **Koruma**: *Korumayı başlat* → "Bir adım kaldı" kartında *Etkinleştirmeyi simüle et* → kalkan yeşile döner.
   - **Sunucular**: sağ üstteki hız göstergesiyle tüm sunucuların gecikmesini ölçün, birini seçin.
   - **DNS Testi**: bir alan adını ağın DNS'i ile şifreli sunucu arasında karşılaştırın (gerçek ağ sorgusu yapar).

Simülatör sistem DNS ayarını uygulayamadığı için uygulama orada **demo modunda** çalışır
(üstte mavi bir şerit görünür): kurulum/etkinleştirme/kaldırma adımları taklit edilir,
gecikme ölçümü ve DNS testi ise gerçek DoH/DoT sorguları gönderir. Tanıtımı yeniden görmek için
uygulamayı simülatörden silip tekrar çalıştırın.

Komut satırından:

```bash
xcodebuild -project AntiDot.xcodeproj -scheme AntiDot \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

## iPhone'a kurulum

Üç yol var. Hangisinin size uyduğu Apple hesabınıza bağlı.

### Yol 1: Uygulamasız, ücretsiz (DNS profili)

Uygulamayı kurmadan aynı korumayı hemen almak için hazır profillerden birini yükleyin:

1. iPhone'da **Safari** ile bu reponun [`Profiles/`](Profiles) klasörünü açın.
2. Bir profil seçin (ör. `AntiDot-cloudflare-https.mobileconfig`), **Raw** / **İndir**'e dokunun, **İzin Ver** deyin.
3. **Ayarlar › Profil İndirildi › Yükle**.
4. **Ayarlar › Genel › VPN ve Aygıt Yönetimi › DNS** bölümünde profilin seçili olduğunu kontrol edin.

Profiller imzasız olduğu için iOS "Doğrulanmadı" uyarısı gösterir; bu normaldir.
İçerikleri düz metin XML'dir, `scripts/generate_profiles.py` ile yeniden üretilebilir.
Kaldırmak için: Ayarlar › Genel › VPN ve Aygıt Yönetimi › profil › Profili Sil.

### Yol 2: Xcode ile doğrudan iPhone'a (ücretli Developer hesabı)

Gereksinimler: Mac, Xcode 15+, iOS 15+ iPhone, [Apple Developer Program](https://developer.apple.com/programs/) üyeliği
(Network Extension yeteneği ücretsiz kişisel hesapla imzalanamaz), [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
git clone https://github.com/can-acar/AntiDot.git && cd AntiDot
xcodegen generate
open AntiDot.xcodeproj
```

1. Xcode › Settings › Accounts: Apple ID'nizi ekleyin.
2. AntiDot hedefi › **Signing & Capabilities**: *Automatically manage signing* açık olmalı. Team, `project.yml` içindeki
   `DEVELOPMENT_TEAM` (`6Z7VX56BQX`) değerinden gelir; fork'larda kendi Team ID'nizi yazıp `xcodegen generate` çalıştırın.
3. Bundle ID başkasına aitse `PRODUCT_BUNDLE_IDENTIFIER`'ı kendinize ait bir değerle değiştirin (ör. `com.adiniz.antidot`).
4. Aynı sekmede **Network Extensions › DNS Settings** işaretli görünmeli (entitlement dosyada tanımlı;
   Xcode App ID'yi bu yetenekle otomatik oluşturur).
5. iPhone'u kabloyla bağlayın, cihazda **Ayarlar › Gizlilik ve Güvenlik › Geliştirici Modu**'nu açın (iOS 16+), yeniden başlatın.
6. Xcode'da hedef cihaz olarak iPhone'u seçip ▶︎ (Cmd+R).
7. Uygulamada **Şifreli DNS'i kur**, ardından **Ayarlar › Genel › VPN ve Aygıt Yönetimi › DNS › AntiDot**.

### Yol 3: TestFlight / App Store (başkalarıyla paylaşmak için)

1. Yol 2'deki imzalama adımlarını tamamlayın.
2. [App Store Connect](https://appstoreconnect.apple.com)'te aynı Bundle ID ile bir uygulama kaydı oluşturun.
3. Xcode'da hedef olarak *Any iOS Device* seçin › **Product › Archive** › **Distribute App › TestFlight & App Store**.
4. App Store Connect › TestFlight'ta test kullanıcılarını (veya herkese açık bağlantıyı) ekleyin.

Şifreleme beyanı `ITSAppUsesNonExemptEncryption = NO` olarak ayarlı (yalnızca işletim sisteminin standart
HTTPS/TLS'i kullanılıyor), bu yüzden yükleme sırasında ek ihracat belgesi istenmez.

### Testler

```bash
xcodebuild test -project AntiDot.xcodeproj -scheme AntiDot \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
```

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
- **Simülatör** sistem DNS ayarını uygulamaz; uygulama orada demo modunda çalışır.
  Gerçek korumayı cihazda test edin. DNS Testi ve gecikme ölçümü simülatörde de gerçek sorgu yapar.

## Yol haritası (öneriler)

- Packet Tunnel tabanlı mod (DNS + basit engelleme listeleri)
- Otomatik en hızlı sunucu seçimi (gecikme ölçümü hazır)
- Uygulama içinden özel sunucu için `.mobileconfig` dışa aktarma
- İngilizce yerelleştirme

## Katkı

Bu proje herkesin yararına geliştirilmektedir. Hata bildirimi ve pull request'ler memnuniyetle karşılanır.

## Lisans

[Apache License 2.0](LICENSE). Ayrıntılar için `LICENSE` ve `NOTICE` dosyalarına bakın.
