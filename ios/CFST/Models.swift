import Foundation

/// 单个 IP 的测速结果（对应 Go mobile.Result）
struct SpeedResult: Codable, Identifiable, Hashable {
    var ip: String
    var sent: Int
    var received: Int
    var lossRate: Double
    var delayMs: Double
    var speedMBps: Double
    var colo: String

    var id: String { ip }
    var isIPv6: Bool { ip.contains(":") }
}

/// IP 段来源
enum IPSource: String, Codable, CaseIterable, Identifiable {
    case ipv4, ipv6, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ipv4: return "IPv4"
        case .ipv6: return "IPv6"
        case .custom: return "自定义"
        }
    }
}

/// 测速参数（对应命令行参数）
struct SpeedTestSettings: Codable, Equatable {
    var routines = 200
    var pingTimes = 4
    var port = 443
    var testURL = "https://cf.xiu2.xyz/url"
    var httping = false
    var httpingCode = 0
    var coloFilter = ""
    var maxDelay = 9999
    var minDelay = 0
    var maxLossRate = 1.0
    var minSpeed = 0.0
    var downloadCount = 10
    var downloadSeconds = 10
    var disableDownload = false
    var testAll = false
    var ipSource = IPSource.ipv4
    var customIPs = ""
    var autoMapAfterTest = false
}

enum DNSRecordType: String, Codable, CaseIterable, Identifiable {
    case A, AAAA
    var id: String { rawValue }
}

enum CheckState: Codable, Equatable {
    case unknown
    case running
    case success(String)
    case failure(String)

    var symbol: String {
        switch self {
        case .unknown: return "—"
        case .running: return "…"
        case .success: return "✅"
        case .failure: return "❌"
        }
    }

    var message: String {
        switch self {
        case .unknown, .running: return ""
        case .success(let m), .failure(let m): return m
        }
    }
}

/// 映射检测结果
struct VerifyResult: Codable, Equatable {
    var api: CheckState = .unknown
    var dns: CheckState = .unknown
    var tcp: CheckState = .unknown
    var checkedAt: Date?
}

/// 需要映射的域名
struct DomainEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var type: DNSRecordType = .A
    var zoneID: String?
    var assignedIP: String?
    var mappedAt: Date?
    var mapStatus: CheckState = .unknown
    var verify = VerifyResult()
}
