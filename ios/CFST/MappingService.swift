import Foundation
import Network

/// 将测速结果映射到域名，并检测映射是否成功
@MainActor
final class MappingService: ObservableObject {
    @Published private(set) var isMapping = false
    @Published private(set) var isVerifying = false

    private let store: AppStore

    init(store: AppStore) {
        self.store = store
    }

    /// 按域名列表顺序依次分配第 1、2、3… 快的 IP（A 记录取 IPv4，AAAA 记录取 IPv6）
    static func assign(domains: [DomainEntry], results: [SpeedResult]) -> [UUID: String] {
        var v4 = results.filter { !$0.isIPv6 }.map(\.ip)[...]
        var v6 = results.filter { $0.isIPv6 }.map(\.ip)[...]
        var assigned: [UUID: String] = [:]
        for d in domains {
            switch d.type {
            case .A: if let ip = v4.popFirst() { assigned[d.id] = ip }
            case .AAAA: if let ip = v6.popFirst() { assigned[d.id] = ip }
            }
        }
        return assigned
    }

    /// 映射全部域名，返回结果摘要
    @discardableResult
    func mapAll() async -> String {
        guard !isMapping else { return "正在映射中" }
        guard store.credentials.isComplete else { return "请先在「设置」中保存 Cloudflare 凭证" }
        guard !store.domains.isEmpty else { return "请先在「域名」中添加域名" }
        guard !store.results.isEmpty else { return "没有测速结果，请先测速" }

        isMapping = true
        defer { isMapping = false }

        let api = CloudflareAPI(credentials: store.credentials)
        let assigned = Self.assign(domains: store.domains, results: store.results)
        var ok = 0
        for domain in store.domains {
            guard let ip = assigned[domain.id] else {
                store.updateDomain(domain.id) {
                    $0.mapStatus = .failure("没有可分配的 \(domain.type == .A ? "IPv4" : "IPv6") 测速结果")
                }
                continue
            }
            store.updateDomain(domain.id) { $0.mapStatus = .running }
            do {
                let zoneID = try await resolveZoneID(for: domain, api: api)
                let record = try await api.upsertRecord(zoneID: zoneID, name: domain.name, type: domain.type, ip: ip)
                store.updateDomain(domain.id) {
                    $0.assignedIP = record.content
                    $0.mappedAt = Date()
                    $0.mapStatus = .success("已更新为 \(record.content)")
                    $0.verify = VerifyResult()
                }
                ok += 1
            } catch {
                store.updateDomain(domain.id) { $0.mapStatus = .failure(error.localizedDescription) }
            }
        }
        return "映射完成：成功 \(ok) / \(store.domains.count)"
    }

    /// 检测全部已映射域名
    func verifyAll() async {
        guard !isVerifying else { return }
        isVerifying = true
        defer { isVerifying = false }
        for domain in store.domains {
            await verify(domain.id)
        }
    }

    /// 检测单个域名：① Cloudflare API 记录 ② 公共 DNS 解析 ③ IP TCP 连通性
    func verify(_ id: UUID) async {
        guard let domain = store.domains.first(where: { $0.id == id }) else { return }
        guard let ip = domain.assignedIP else {
            store.updateDomain(id) {
                $0.verify = VerifyResult(api: .failure("尚未映射"), dns: .unknown, tcp: .unknown, checkedAt: Date())
            }
            return
        }
        store.updateDomain(id) { $0.verify = VerifyResult(api: .running, dns: .running, tcp: .running) }

        async let apiState = checkAPI(domain, ip: ip)
        async let dnsState = Self.checkDNS(name: domain.name, type: domain.type, ip: ip)
        async let tcpState = Self.checkTCP(ip: ip, port: 443)
        let result = await VerifyResult(api: apiState, dns: dnsState, tcp: tcpState, checkedAt: Date())
        store.updateDomain(id) { $0.verify = result }
    }

    private func resolveZoneID(for domain: DomainEntry, api: CloudflareAPI) async throws -> String {
        if let id = domain.zoneID { return id }
        let zone = try await api.findZone(for: domain.name)
        store.updateDomain(domain.id) { $0.zoneID = zone.id }
        return zone.id
    }

    private func checkAPI(_ domain: DomainEntry, ip: String) async -> CheckState {
        guard store.credentials.isComplete else { return .failure("未保存凭证") }
        let api = CloudflareAPI(credentials: store.credentials)
        do {
            let zoneID = try await resolveZoneID(for: domain, api: api)
            let records = try await api.listRecords(zoneID: zoneID, name: domain.name, type: domain.type)
            guard !records.isEmpty else { return .failure("未找到 \(domain.type.rawValue) 记录") }
            guard records.contains(where: { Self.sameIP($0.content, ip) }) else {
                return .failure("记录值为 \(records.map(\.content).joined(separator: ", "))，与 \(ip) 不一致")
            }
            if records.contains(where: { Self.sameIP($0.content, ip) && $0.proxied == true }) {
                return .failure("记录已开启代理（橙色云朵），解析不会返回优选 IP")
            }
            return .success("记录值 \(ip)，仅 DNS")
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// 通过 DNS over HTTPS（Cloudflare 与 Google）查询域名解析结果
    private static func checkDNS(name: String, type: DNSRecordType, ip: String) async -> CheckState {
        struct DoHAnswer: Decodable {
            let type: Int
            let data: String
        }
        struct DoHResponse: Decodable {
            let answers: [DoHAnswer]?
            enum CodingKeys: String, CodingKey { case answers = "Answer" }
        }
        let resolvers = [
            ("Cloudflare", "https://cloudflare-dns.com/dns-query"),
            ("Google", "https://dns.google/resolve"),
        ]
        let typeCode = type == .A ? 1 : 28
        var lines: [String] = []
        var matched = 0
        for (label, endpoint) in resolvers {
            var comps = URLComponents(string: endpoint)!
            comps.queryItems = [URLQueryItem(name: "name", value: name), URLQueryItem(name: "type", value: type.rawValue)]
            var req = URLRequest(url: comps.url!, timeoutInterval: 10)
            req.setValue("application/dns-json", forHTTPHeaderField: "Accept")
            req.cachePolicy = .reloadIgnoringLocalCacheData
            do {
                let (data, _) = try await URLSession.shared.data(for: req)
                let resp = try JSONDecoder().decode(DoHResponse.self, from: data)
                let ips = (resp.answers ?? []).filter { $0.type == typeCode }.map(\.data)
                if ips.contains(where: { sameIP($0, ip) }) {
                    matched += 1
                    lines.append("\(label): \(ips.joined(separator: ", "))")
                } else {
                    lines.append("\(label): \(ips.isEmpty ? "无解析结果" : ips.joined(separator: ", "))")
                }
            } catch {
                lines.append("\(label): 查询失败 \(error.localizedDescription)")
            }
        }
        let detail = lines.joined(separator: "\n")
        if matched == resolvers.count { return .success(detail) }
        if matched > 0 { return .success(detail + "\n（部分 DNS 尚未生效，TTL 过后再检测）") }
        return .failure(detail + "\n（若刚刚映射，DNS 缓存可能尚未过期，请稍后再检测）")
    }

    /// 对映射的 IP 建立一次 TCP 连接，确认 IP 可用并测量延迟
    private static func checkTCP(ip: String, port: UInt16) async -> CheckState {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return .failure("端口无效") }
        let conn = NWConnection(host: NWEndpoint.Host(ip), port: nwPort, using: .tcp)
        let start = Date()
        return await withCheckedContinuation { cont in
            let lock = NSLock()
            var finished = false
            func finish(_ state: CheckState) {
                lock.lock()
                defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                conn.cancel()
                cont.resume(returning: state)
            }
            conn.stateUpdateHandler = { s in
                switch s {
                case .ready:
                    finish(.success(String(format: "TCP %d 连接成功，%.0f ms", Int(port), Date().timeIntervalSince(start) * 1000)))
                case .failed(let e), .waiting(let e):
                    finish(.failure("TCP 连接失败：\(e.localizedDescription)"))
                default:
                    break
                }
            }
            conn.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                finish(.failure("TCP 连接超时"))
            }
        }
    }

    /// 比较两个 IP 是否相同（兼容 IPv6 不同写法）
    nonisolated static func sameIP(_ a: String, _ b: String) -> Bool {
        if let x = IPv6Address(a), let y = IPv6Address(b) { return x.rawValue == y.rawValue }
        if let x = IPv4Address(a), let y = IPv4Address(b) { return x.rawValue == y.rawValue }
        return a.lowercased() == b.lowercased()
    }
}
