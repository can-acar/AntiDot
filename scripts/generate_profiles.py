#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Hazır sunucular için iOS/macOS .mobileconfig DNS profilleri üretir.

Bu profiller uygulama gerektirmez: iPhone'da Safari ile açılıp
Ayarlar > Profil İndirildi bölümünden yüklenebilir.
Kullanım: python3 scripts/generate_profiles.py
"""
import plistlib
import uuid
from pathlib import Path

NS = uuid.UUID("6f1c3b8e-2f7a-4d1e-9b0a-a17d07a17d07")
OUT = Path(__file__).resolve().parent.parent / "Profiles"

RESOLVERS = [
    ("Cloudflare", "https://cloudflare-dns.com/dns-query", "one.one.one.one",
     ["1.1.1.1", "1.0.0.1", "2606:4700:4700::1111", "2606:4700:4700::1001"]),
    ("Google", "https://dns.google/dns-query", "dns.google",
     ["8.8.8.8", "8.8.4.4", "2001:4860:4860::8888", "2001:4860:4860::8844"]),
    ("Quad9", "https://dns.quad9.net/dns-query", "dns.quad9.net",
     ["9.9.9.9", "149.112.112.112", "2620:fe::fe", "2620:fe::9"]),
    ("AdGuard", "https://dns.adguard-dns.com/dns-query", "dns.adguard-dns.com",
     ["94.140.14.14", "94.140.15.15", "2a10:50c0::ad1:ff", "2a10:50c0::ad2:ff"]),
    ("Mullvad", "https://dns.mullvad.net/dns-query", "dns.mullvad.net",
     ["194.242.2.2", "2a07:e340::2"]),
]


def profile(name, proto, endpoint, ips):
    slug = f"{name.lower()}-{proto.lower()}"
    ident = f"org.antidot.profile.{slug}"
    dns = {"DNSProtocol": proto, "ServerAddresses": ips}
    if proto == "HTTPS":
        dns["ServerURL"] = endpoint
    else:
        dns["ServerName"] = endpoint
    label = "DoH" if proto == "HTTPS" else "DoT"
    payload = {
        "PayloadType": "com.apple.dnsSettings.managed",
        "PayloadIdentifier": f"{ident}.dns",
        "PayloadUUID": str(uuid.uuid5(NS, f"{ident}.dns")).upper(),
        "PayloadVersion": 1,
        "PayloadDisplayName": f"AntiDot {name} {label}",
        "DNSSettings": dns,
    }
    return slug, {
        "PayloadType": "Configuration",
        "PayloadVersion": 1,
        "PayloadIdentifier": ident,
        "PayloadUUID": str(uuid.uuid5(NS, ident)).upper(),
        "PayloadDisplayName": f"AntiDot – {name} ({label})",
        "PayloadDescription": f"Tüm DNS sorgularını {name} {label} ile şifreler.",
        "PayloadOrganization": "AntiDot (Apache-2.0)",
        "PayloadRemovalDisallowed": False,
        "PayloadContent": [payload],
    }


def main():
    OUT.mkdir(exist_ok=True)
    for name, doh, dot, ips in RESOLVERS:
        for proto, endpoint in (("HTTPS", doh), ("TLS", dot)):
            slug, data = profile(name, proto, endpoint, ips)
            path = OUT / f"AntiDot-{slug}.mobileconfig"
            with open(path, "wb") as f:
                plistlib.dump(data, f, sort_keys=True)
            print(path.name)


if __name__ == "__main__":
    main()
