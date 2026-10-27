import Foundation

/// App 全局状态：测速参数、域名列表、最近测速结果、Cloudflare 凭证
@MainActor
final class AppStore: ObservableObject {
    @Published var settings: SpeedTestSettings { didSet { save(settings, key: Keys.settings) } }
    @Published var domains: [DomainEntry] { didSet { save(domains, key: Keys.domains) } }
    @Published var results: [SpeedResult] { didSet { save(results, key: Keys.results) } }
    @Published var resultsDate: Date? { didSet { save(resultsDate, key: Keys.resultsDate) } }
    @Published var credentials: CFCredentials

    private enum Keys {
        static let settings = "settings"
        static let domains = "domains"
        static let results = "results"
        static let resultsDate = "resultsDate"
    }

    init() {
        settings = Self.load(SpeedTestSettings.self, key: Keys.settings) ?? SpeedTestSettings()
        domains = Self.load([DomainEntry].self, key: Keys.domains) ?? []
        results = Self.load([SpeedResult].self, key: Keys.results) ?? []
        resultsDate = Self.load(Date.self, key: Keys.resultsDate)
        credentials = KeychainStore.load() ?? CFCredentials()
    }

    func saveCredentials(_ c: CFCredentials) -> Bool {
        credentials = c
        return KeychainStore.save(c)
    }

    func clearCredentials() {
        KeychainStore.delete()
        credentials = CFCredentials()
    }

    func updateDomain(_ id: UUID, _ change: (inout DomainEntry) -> Void) {
        guard let i = domains.firstIndex(where: { $0.id == id }) else { return }
        change(&domains[i])
    }

    /// 读取要测速的 IP 段数据
    func ipRangesText() -> String {
        switch settings.ipSource {
        case .ipv4: return Self.bundleText("ip")
        case .ipv6: return Self.bundleText("ipv6")
        case .custom: return settings.customIPs
        }
    }

    private static func bundleText(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return text
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
