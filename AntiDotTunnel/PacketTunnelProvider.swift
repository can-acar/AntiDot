// SPDX-License-Identifier: Apache-2.0
import NetworkExtension
import os

let tunnelLog = Logger(subsystem: "com.canacar.antidot.tunnel", category: "dns")

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private static let tunnelAddress = "198.18.0.1"
    private static let dnsAddress = "198.18.0.53"
    private static let mtu = 1500
    private static let maxUDPPayload = mtu - 28
    private static let maxInFlight = 64

    private let inFlightLock = NSLock()
    private var inFlight = 0

    private var resolvers: [DNSResolver] = []
    private let client = EncryptedDNSClient(timeout: 5, session: EncryptedDNSClient.makeEphemeralSession())

    override func startTunnel(options: [String: NSObject]?) async throws {
        guard let proto = protocolConfiguration as? NETunnelProviderProtocol,
              let data = proto.providerConfiguration?[PacketTunnelKeys.resolvers] as? Data,
              let decoded = try? JSONDecoder().decode([DNSResolver].self, from: data),
              !decoded.isEmpty, decoded.allSatisfy({ $0.validationError == nil })
        else {
            tunnelLog.error("startTunnel: invalid providerConfiguration")
            throw NEVPNError(.configurationInvalid)
        }
        resolvers = decoded
        tunnelLog.info("startTunnel: \(decoded.map(\.endpointDescription), privacy: .public)")

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        let ipv4 = NEIPv4Settings(addresses: [Self.tunnelAddress], subnetMasks: ["255.255.255.255"])
        ipv4.includedRoutes = [NEIPv4Route(destinationAddress: Self.dnsAddress, subnetMask: "255.255.255.255")]
        settings.ipv4Settings = ipv4
        let dns = NEDNSSettings(servers: [Self.dnsAddress])
        dns.matchDomains = [""]
        settings.dnsSettings = dns
        settings.mtu = NSNumber(value: Self.mtu)
        try await setTunnelNetworkSettings(settings)
        tunnelLog.info("startTunnel: network settings applied")
        readPackets()
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {}

    private func readPackets() {
        packetFlow.readPackets { [weak self] packets, _ in
            guard let self else { return }
            packets.forEach(self.handle)
            self.readPackets()
        }
    }

    private func handle(_ raw: Data) {
        guard let packet = IPv4UDPPacket(raw), packet.destinationPort == 53, packet.payload.count >= 12 else {
            tunnelLog.debug("dropped packet: \(raw.count) bytes, first byte \(raw.first ?? 0)")
            return
        }
        let query = packet.payload
        guard reserveSlot() else { return write(DNSMessage.emptyReply(to: query, flags: 0x80, rcode: 2), for: packet) }
        Task { [resolvers, client] in
            var answer: Data
            do {
                answer = try await DNSRace.first(query, resolvers: resolvers, client: client)
            } catch {
                tunnelLog.error("query failed on all resolvers: \(error.localizedDescription, privacy: .public)")
                answer = DNSMessage.emptyReply(to: query, flags: 0x80, rcode: 2)
            }
            if answer.count > Self.maxUDPPayload { answer = DNSMessage.emptyReply(to: query, flags: 0x82, rcode: 0) }
            self.write(answer, for: packet)
            self.releaseSlot()
        }
    }

    private func write(_ answer: Data, for packet: IPv4UDPPacket) {
        packetFlow.writePackets([packet.reply(with: answer).data], withProtocols: [NSNumber(value: AF_INET)])
    }

    private func reserveSlot() -> Bool {
        inFlightLock.lock(); defer { inFlightLock.unlock() }
        guard inFlight < Self.maxInFlight else { return false }
        inFlight += 1
        return true
    }

    private func releaseSlot() {
        inFlightLock.lock(); defer { inFlightLock.unlock() }
        inFlight -= 1
    }
}

enum DNSRace {
    static func first(_ query: Data, resolvers: [DNSResolver], client: EncryptedDNSClient) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            for resolver in resolvers {
                group.addTask {
                    let answer: Data
                    do {
                        answer = try await client.exchange(query, via: resolver)
                    } catch {
                        tunnelLog.error("\(resolver.endpointDescription, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        throw error
                    }
                    guard answer.count >= 12, answer.prefix(2) == query.prefix(2) else { throw DNSMessageError.idMismatch }
                    return answer
                }
            }
            var lastError: Error = EncryptedDNSClient.ClientError.missingEndpoint
            var fallback: Data?
            while let result = await group.nextResult() {
                switch result {
                case .success(let answer) where isDefinitive(answer):
                    group.cancelAll()
                    return answer
                case .success(let answer):
                    fallback = fallback ?? answer
                case .failure(let error):
                    lastError = error
                }
            }
            if let fallback { return fallback }
            throw lastError
        }
    }

    static func isDefinitive(_ answer: Data) -> Bool {
        let rcode = answer[answer.startIndex + 3] & 0x0F
        return rcode == 0 || rcode == 3
    }
}
