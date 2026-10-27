import Foundation

struct CFError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct CFZone: Decodable {
    let id: String
    let name: String
}

struct CFDNSRecord: Decodable {
    let id: String
    let name: String
    let type: String
    let content: String
    let proxied: Bool?
    let ttl: Int?
}

private struct CFEnvelope<T: Decodable>: Decodable {
    struct Message: Decodable {
        let code: Int?
        let message: String
    }
    let success: Bool
    let errors: [Message]?
    let result: T?
}

/// Cloudflare API v4 客户端（只用到 DNS 记录相关接口）
struct CloudflareAPI {
    let credentials: CFCredentials
    private let base = URL(string: "https://api.cloudflare.com/client/v4")!

    /// 验证凭证是否有效，返回说明文字
    func verifyCredentials() async throws -> String {
        switch credentials.authType {
        case .apiToken:
            struct TokenStatus: Decodable { let status: String }
            let r: TokenStatus = try await request("GET", "/user/tokens/verify")
            guard r.status == "active" else { throw CFError(message: "Token 状态：\(r.status)") }
            return "API Token 有效（active）"
        case .globalKey:
            struct User: Decodable { let email: String }
            let r: User = try await request("GET", "/user")
            return "Global API Key 有效（\(r.email)）"
        }
    }

    /// 根据完整域名查找所属 Zone（逐级去掉前缀查询）
    func findZone(for domain: String) async throws -> CFZone {
        var labels = domain.lowercased().split(separator: ".").map(String.init)
        while labels.count >= 2 {
            let name = labels.joined(separator: ".")
            let zones: [CFZone] = try await request("GET", "/zones", query: ["name": name])
            if let zone = zones.first { return zone }
            labels.removeFirst()
        }
        throw CFError(message: "未找到 \(domain) 所属的 Zone，请确认域名已添加到该 Cloudflare 账号，且凭证有 Zone:Read 权限")
    }

    func listRecords(zoneID: String, name: String, type: DNSRecordType) async throws -> [CFDNSRecord] {
        try await request("GET", "/zones/\(zoneID)/dns_records", query: ["name": name, "type": type.rawValue])
    }

    /// 更新（不存在则创建）DNS 记录，使用「仅 DNS」模式（不走 Cloudflare 代理），否则解析结果不会是优选 IP
    func upsertRecord(zoneID: String, name: String, type: DNSRecordType, ip: String) async throws -> CFDNSRecord {
        let body: [String: Any] = ["type": type.rawValue, "name": name, "content": ip, "ttl": 60, "proxied": false]
        if let existing = try await listRecords(zoneID: zoneID, name: name, type: type).first {
            return try await request("PATCH", "/zones/\(zoneID)/dns_records/\(existing.id)", body: body)
        }
        return try await request("POST", "/zones/\(zoneID)/dns_records", body: body)
    }

    private func request<T: Decodable>(_ method: String, _ path: String, query: [String: String] = [:], body: [String: Any]? = nil) async throws -> T {
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var req = URLRequest(url: comps.url!, timeoutInterval: 20)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        switch credentials.authType {
        case .apiToken:
            req.setValue("Bearer \(credentials.apiToken.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        case .globalKey:
            req.setValue(credentials.email.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "X-Auth-Email")
            req.setValue(credentials.globalKey.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "X-Auth-Key")
        }
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let env = try? JSONDecoder().decode(CFEnvelope<T>.self, from: data) else {
            throw CFError(message: "Cloudflare API 返回无法解析的响应（HTTP \(status)）")
        }
        guard env.success, let result = env.result else {
            let msg = env.errors?.map { e in e.code.map { "[\($0)] \(e.message)" } ?? e.message }.joined(separator: "; ")
            throw CFError(message: msg?.isEmpty == false ? msg! : "Cloudflare API 请求失败（HTTP \(status)）")
        }
        return result
    }
}
