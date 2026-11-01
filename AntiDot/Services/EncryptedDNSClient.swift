// SPDX-License-Identifier: Apache-2.0
import Foundation
import Network

/// Seçili sunucuya uygulama içinden doğrudan DoH/DoT sorgusu atar.
/// Sistem ayarı etkin olmasa bile sunucunun çalıştığını ve
/// yerel ağdaki çözümleyicinin cevabı değiştirip değiştirmediğini görmek için kullanılır.
struct EncryptedDNSClient {
    struct Result {
        var response: DNSResponse
        var latency: TimeInterval
    }

    enum ClientError: LocalizedError {
        case badHTTPStatus(Int)
        case missingEndpoint
        case timeout
        case connection(String)

        var errorDescription: String? {
            switch self {
            case .badHTTPStatus(let c): return "DoH sunucusu HTTP \(c) döndü."
            case .missingEndpoint: return "Sunucu adresi eksik."
            case .timeout: return "Zaman aşımı."
            case .connection(let m): return "Bağlantı hatası: \(m)"
            }
        }
    }

    var timeout: TimeInterval = 8

    func query(_ name: String, type: DNSRecordType, via resolver: DNSResolver) async throws -> Result {
        let started = Date()
        let response: DNSResponse
        switch resolver.transport {
        case .doh: response = try await queryDoH(name, type: type, resolver: resolver)
        case .dot: response = try await queryDoT(name, type: type, resolver: resolver)
        }
        return Result(response: response, latency: Date().timeIntervalSince(started))
    }

    // MARK: DoH (RFC 8484, POST application/dns-message)

    private func queryDoH(_ name: String, type: DNSRecordType, resolver: DNSResolver) async throws -> DNSResponse {
        guard let s = resolver.dohURL, let url = URL(string: s) else { throw ClientError.missingEndpoint }
        let query = try DNSMessage.makeQuery(name: name, type: type, id: 0)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/dns-message", forHTTPHeaderField: "Content-Type")
        request.setValue("application/dns-message", forHTTPHeaderField: "Accept")
        request.httpBody = query

        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw ClientError.badHTTPStatus(http.statusCode)
        }
        return try DNSMessage.parseResponse(data, expectedID: 0)
    }

    // MARK: DoT (RFC 7858, TCP/853 + TLS, 2 bayt uzunluk önekli)

    private func queryDoT(_ name: String, type: DNSRecordType, resolver: DNSResolver) async throws -> DNSResponse {
        guard let serverName = resolver.dotServerName, let ip = resolver.bootstrapServers.first else {
            throw ClientError.missingEndpoint
        }
        let id = UInt16.random(in: 1...UInt16.max)
        var framed = Data()
        let query = try DNSMessage.makeQuery(name: name, type: type, id: id)
        framed.appendUInt16(UInt16(query.count))
        framed.append(query)

        // IP'ye bağlan, sertifikayı sunucu adına (SNI) göre doğrula:
        // böylece sunucu adını çözmek için düz DNS'e ihtiyaç kalmaz.
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, serverName)
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        let params = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        let connection = NWConnection(host: NWEndpoint.Host(ip), port: 853, using: params)

        let raw = try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask { try await Self.exchange(connection: connection, payload: framed) }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw ClientError.timeout
            }
            defer {
                group.cancelAll()
                connection.cancel()
            }
            return try await group.next()!
        }
        return try DNSMessage.parseResponse(raw, expectedID: id)
    }

    private static func exchange(connection: NWConnection, payload: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            let once = ResumeOnce(cont)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: payload, completion: .contentProcessed { error in
                        if let error { once.fail(ClientError.connection(error.localizedDescription)) }
                    })
                    receiveFramed(connection, once: once)
                case .failed(let error), .waiting(let error):
                    once.fail(ClientError.connection(error.localizedDescription))
                case .cancelled:
                    once.fail(CancellationError())
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
    }

    private static func receiveFramed(_ connection: NWConnection, once: ResumeOnce) {
        connection.receive(minimumIncompleteLength: 2, maximumLength: 2) { header, _, _, error in
            if let error { return once.fail(ClientError.connection(error.localizedDescription)) }
            guard let header, header.count == 2 else { return once.fail(DNSMessageError.truncated) }
            let length = Int(header[header.startIndex]) << 8 | Int(header[header.startIndex + 1])
            connection.receive(minimumIncompleteLength: length, maximumLength: length) { body, _, _, error in
                if let error { return once.fail(ClientError.connection(error.localizedDescription)) }
                guard let body, body.count == length else { return once.fail(DNSMessageError.truncated) }
                once.succeed(body)
            }
        }
    }

    /// Continuation'ın yalnızca bir kez devam ettirilmesini garanti eder.
    private final class ResumeOnce: @unchecked Sendable {
        private var cont: CheckedContinuation<Data, Error>?
        private let lock = NSLock()
        init(_ cont: CheckedContinuation<Data, Error>) { self.cont = cont }

        private func take() -> CheckedContinuation<Data, Error>? {
            lock.lock(); defer { lock.unlock() }
            let c = cont; cont = nil; return c
        }
        func succeed(_ d: Data) { take()?.resume(returning: d) }
        func fail(_ e: Error) { take()?.resume(throwing: e) }
    }
}

/// İşletim sisteminin o anki çözümleyicisiyle (operatör/Wi-Fi DNS'i veya etkinse AntiDot) sorgu.
/// Şifreli cevapla karşılaştırarak DNS manipülasyonu tespit etmek için kullanılır.
enum SystemResolver {
    static func lookup(_ host: String) async -> [String] {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                var hints = addrinfo(ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM,
                                     ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil,
                                     ai_addr: nil, ai_next: nil)
                var result: UnsafeMutablePointer<addrinfo>?
                guard getaddrinfo(host, nil, &hints, &result) == 0 else {
                    return cont.resume(returning: [])
                }
                defer { freeaddrinfo(result) }
                var addresses: [String] = []
                var cursor = result
                while let info = cursor?.pointee {
                    var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(info.ai_addr, info.ai_addrlen, &buf, socklen_t(buf.count),
                                   nil, 0, NI_NUMERICHOST) == 0 {
                        let s = String(cString: buf)
                        if !addresses.contains(s) { addresses.append(s) }
                    }
                    cursor = info.ai_next
                }
                cont.resume(returning: addresses)
            }
        }
    }
}
