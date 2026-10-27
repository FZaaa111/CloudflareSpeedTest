import Cfst
import Foundation
import UIKit

/// 接收 Go 测速核心的进度回调（在后台线程调用）
private final class RunListener: NSObject, MobileListenerProtocol {
    let progress: (String, Int, Int) -> Void
    let log: (String) -> Void

    init(progress: @escaping (String, Int, Int) -> Void, log: @escaping (String) -> Void) {
        self.progress = progress
        self.log = log
    }

    func onProgress(_ stage: String?, done: Int, total: Int) {
        progress(stage ?? "", done, total)
    }

    func onLog(_ msg: String?) {
        log(msg ?? "")
    }
}

/// 调用 Go 测速核心执行测速
@MainActor
final class SpeedTestRunner: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var stage = ""
    @Published private(set) var done = 0
    @Published private(set) var total = 0
    @Published private(set) var logs: [String] = []
    @Published var errorMessage: String?

    var stageTitle: String {
        switch stage {
        case "ping": return "延迟测速"
        case "download": return "下载测速"
        default: return stage
        }
    }

    var fraction: Double { total > 0 ? Double(done) / Double(total) : 0 }

    /// 开始测速，完成后返回结果（按速度排序；禁用下载测速时按延迟排序）
    func run(settings s: SpeedTestSettings, ipRanges: String) async -> [SpeedResult]? {
        guard !isRunning else { return nil }
        isRunning = true
        stage = ""
        done = 0
        total = 0
        logs = []
        errorMessage = nil
        UIApplication.shared.isIdleTimerDisabled = true // 测速期间保持屏幕常亮，避免进入后台中断测速
        defer {
            isRunning = false
            UIApplication.shared.isIdleTimerDisabled = false
        }

        guard let cfg = MobileConfig() else { return nil } // 对应 Go mobile.NewConfig()，带默认值
        cfg.routines = s.routines
        cfg.pingTimes = s.pingTimes
        cfg.port = s.port
        cfg.testURL = s.testURL
        cfg.httping = s.httping
        cfg.httpingCode = s.httpingCode
        cfg.coloFilter = s.coloFilter
        cfg.maxDelay = s.maxDelay
        cfg.minDelay = s.minDelay
        cfg.maxLossRate = s.maxLossRate
        cfg.minSpeed = s.minSpeed
        cfg.downloadCount = s.downloadCount
        cfg.downloadSeconds = s.downloadSeconds
        cfg.disableDownload = s.disableDownload
        cfg.testAll = s.testAll
        cfg.ipRanges = ipRanges

        let listener = RunListener(
            progress: { [weak self] stage, done, total in
                Task { @MainActor in
                    self?.stage = stage
                    self?.done = done
                    self?.total = total
                }
            },
            log: { [weak self] msg in
                Task { @MainActor in self?.logs.append(msg) }
            }
        )

        let output: Result<String, Error> = await Task.detached(priority: .userInitiated) { () -> Result<String, Error> in
            var err: NSError?
            let json: String? = MobileRun(cfg, listener, &err)
            if let err { return .failure(err) }
            return .success(json ?? "[]")
        }.value

        switch output {
        case .failure(let err):
            errorMessage = err.localizedDescription
            return nil
        case .success(let json):
            do {
                return try JSONDecoder().decode([SpeedResult].self, from: Data(json.utf8))
            } catch {
                errorMessage = "解析测速结果失败：\(error.localizedDescription)"
                return nil
            }
        }
    }

    func stop() {
        MobileStop()
    }
}
