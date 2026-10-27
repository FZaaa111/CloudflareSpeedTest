import SwiftUI

struct SpeedTestView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var runner: SpeedTestRunner
    @EnvironmentObject private var mapping: MappingService
    @State private var alertMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("IP 段", selection: $store.settings.ipSource) {
                        ForEach(IPSource.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if store.settings.ipSource == .custom {
                        TextField("每行或逗号分隔，如 104.16.0.0/13", text: $store.settings.customIPs, axis: .vertical)
                            .lineLimit(3...8)
                            .font(.system(.footnote, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    NavigationLink("测速参数") { SpeedTestSettingsView() }
                    Toggle("测速完成后自动映射到域名", isOn: $store.settings.autoMapAfterTest)
                }

                Section {
                    if runner.isRunning {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(runner.stageTitle.isEmpty ? "准备中" : runner.stageTitle)  \(runner.done) / \(runner.total)")
                                .font(.subheadline)
                            ProgressView(value: runner.fraction)
                        }
                        Button(role: .destructive) { runner.stop() } label: {
                            Label("停止测速", systemImage: "stop.circle")
                        }
                    } else {
                        Button { Task { await startTest() } } label: {
                            Label("开始测速", systemImage: "play.circle.fill")
                        }
                    }
                    if let err = runner.errorMessage {
                        Text(err).foregroundStyle(.red).font(.footnote)
                    }
                    if let last = runner.logs.last, runner.isRunning {
                        Text(last).font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section {
                    if store.results.isEmpty {
                        Text("暂无测速结果").foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(store.results.enumerated()), id: \.element.id) { index, r in
                            ResultRow(index: index + 1, result: r)
                                .contextMenu {
                                    Button("复制 IP") { UIPasteboard.general.string = r.ip }
                                }
                        }
                    }
                } header: {
                    HStack {
                        Text("测速结果")
                        Spacer()
                        if let date = store.resultsDate {
                            Text(date, style: .relative) + Text("前")
                        }
                    }
                } footer: {
                    if !store.results.isEmpty {
                        Text(store.settings.disableDownload ? "按丢包率、延迟排序" : "按下载速度排序")
                    }
                }

                if !store.results.isEmpty {
                    Section {
                        Button {
                            Task { alertMessage = await mapping.mapAll() }
                        } label: {
                            Label(mapping.isMapping ? "映射中…" : "映射到域名", systemImage: "arrow.triangle.branch")
                        }
                        .disabled(mapping.isMapping || runner.isRunning)
                    } footer: {
                        Text("按「域名」页的顺序，依次把第 1、2、3… 个 IP 写入对应域名的 A / AAAA 记录")
                    }
                }
            }
            .navigationTitle("Cloudflare 测速")
            .alert(alertMessage ?? "", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
                Button("好") {}
            }
        }
    }

    private func startTest() async {
        let ranges = store.ipRangesText()
        guard let results = await runner.run(settings: store.settings, ipRanges: ranges) else { return }
        store.results = results
        store.resultsDate = Date()
        if store.settings.autoMapAfterTest && !results.isEmpty {
            alertMessage = await mapping.mapAll()
            await mapping.verifyAll()
        }
    }
}

private struct ResultRow: View {
    let index: Int
    let result: SpeedResult

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(index)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.ip)
                    .font(.system(.subheadline, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("丢包 \(Int(result.lossRate * 100))%  ·  \(result.colo.isEmpty ? "N/A" : result.colo)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.0f ms", result.delayMs))
                    .font(.subheadline.monospacedDigit())
                Text(String(format: "%.2f MB/s", result.speedMBps))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SpeedTestSettingsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Form {
            Section("延迟测速") {
                Stepper("线程数：\(store.settings.routines)", value: $store.settings.routines, in: 10...1000, step: 10)
                Stepper("测速次数：\(store.settings.pingTimes)", value: $store.settings.pingTimes, in: 1...20)
                LabeledContent("端口") {
                    TextField("443", value: $store.settings.port, format: .number.grouping(.never))
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                }
                Toggle("HTTPing 模式", isOn: $store.settings.httping)
                if store.settings.httping {
                    LabeledContent("有效状态码") {
                        TextField("0 = 200/301/302", value: $store.settings.httpingCode, format: .number.grouping(.never))
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("地区码") {
                        TextField("如 HKG,NRT,LAX", text: $store.settings.coloFilter)
                            .textInputAutocapitalization(.characters).multilineTextAlignment(.trailing)
                    }
                }
                Toggle("测速全部 IP（仅 IPv4）", isOn: $store.settings.testAll)
            }

            Section("过滤条件") {
                LabeledContent("延迟上限 (ms)") {
                    TextField("9999", value: $store.settings.maxDelay, format: .number.grouping(.never))
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                }
                LabeledContent("延迟下限 (ms)") {
                    TextField("0", value: $store.settings.minDelay, format: .number.grouping(.never))
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                }
                LabeledContent("丢包率上限") {
                    TextField("1.00", value: $store.settings.maxLossRate, format: .number.precision(.fractionLength(2)))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
            }

            Section {
                Toggle("禁用下载测速", isOn: $store.settings.disableDownload)
                if !store.settings.disableDownload {
                    Stepper("下载测速数量：\(store.settings.downloadCount)", value: $store.settings.downloadCount, in: 1...100)
                    Stepper("单个 IP 下载时间：\(store.settings.downloadSeconds) 秒", value: $store.settings.downloadSeconds, in: 3...60)
                    LabeledContent("速度下限 (MB/s)") {
                        TextField("0", value: $store.settings.minSpeed, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                }
            } header: {
                Text("下载测速")
            }

            Section {
                TextField("https://...", text: $store.settings.testURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("测速地址")
            } footer: {
                Text("HTTPing 与下载测速使用该地址，默认地址不保证可用性，建议自建。")
            }

            Section {
                Button("恢复默认参数", role: .destructive) {
                    let keep = store.settings
                    var s = SpeedTestSettings()
                    s.ipSource = keep.ipSource
                    s.customIPs = keep.customIPs
                    s.autoMapAfterTest = keep.autoMapAfterTest
                    store.settings = s
                }
            }
        }
        .navigationTitle("测速参数")
        .navigationBarTitleDisplayMode(.inline)
    }
}
