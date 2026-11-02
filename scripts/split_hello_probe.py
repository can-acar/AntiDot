#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
import socket
import ssl
import sys
import time


def client_hello(host):
    incoming, outgoing = ssl.MemoryBIO(), ssl.MemoryBIO()
    tls = ssl.create_default_context().wrap_bio(incoming, outgoing, server_hostname=host)
    try:
        tls.do_handshake()
    except ssl.SSLWantReadError:
        pass
    return outgoing.read()


def tls_record_split(hello, at):
    body = hello[5:]
    record = lambda chunk: hello[:3] + len(chunk).to_bytes(2, "big") + chunk
    split = record(body[: at - 5]) + record(body[at - 5:])
    assert len(split) == len(hello) + 5
    return split


def probe(host, ip, mode):
    hello = client_hello(host)
    sni = hello.find(host.encode())
    assert sni > 5, "SNI ClientHello içinde bulunamadı"
    cut = sni + len(host) // 2
    if mode == "tls-record":
        hello = tls_record_split(hello, cut)
    with socket.create_connection((ip, 443), timeout=5) as s:
        s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        if mode == "tcp-split":
            s.sendall(hello[:cut])
            time.sleep(0.2)
            s.sendall(hello[cut:])
        else:
            s.sendall(hello)
        try:
            head = s.recv(5)
        except (ConnectionResetError, socket.timeout) as error:
            return f"ENGELLİ ({type(error).__name__})"
    return "GEÇTİ (ServerHello)" if head[:1] == b"\x16" else f"ENGELLİ (cevap: {head.hex() or 'bağlantı kapandı'})"


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("kullanım: split_hello_probe.py <engelli-alan-adı> [ip]")
    host = sys.argv[1]
    ip = sys.argv[2] if len(sys.argv) > 2 else socket.gethostbyname(host)
    print(f"{host} -> {ip}")
    for mode in ("düz", "tcp-split", "tls-record"):
        print(f"  {mode:10} {probe(host, ip, mode)}")
