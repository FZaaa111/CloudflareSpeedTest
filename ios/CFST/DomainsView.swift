import SwiftUI

struct DomainsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var mapping: MappingService
    @State private var newName = ""
    @State private var newType = DNSRecordType.A
    @State private var alertMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("域名，如 cf.example.com", text: $newName)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Picker("记录类型", selection: $newType) {
                        ForEach(DNSRecordType.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Button("添加域名", action: addDomain)
                        .disabled(normalized(newName).isEmpty)
                } header: {
                    Text("添加")
                }

                Section {
                    if store.domains.isEmpty {
                        Text("还没有域名").foregroundStyle(.secondary)
                    }
                    ForEach(Array(store.domains.enumerated()), id: \.element.id) { index, d in
                        DomainRow(index: index + 1, domain: d, preview: preview[d.id])
                            .swipeActions {
                                Button(role: .destructive) {
                                    store.domains.removeAll { $0.id == d.id }
                                } label: { Label("删除", systemImage: "trash") }
                                Button {
                                    Task { await mapping.verify(d.id) }
                                } label: { Label("检测", systemImage: "checkmark.shield") }
                                    .tint(.blue)
                            }
                    }
                    .onMove { store.domains.move(fromOffsets: $0, toOffset: $1) }
                } header: {
                    Text("域名（拖动排序，第 N 个域名使用第 N 快的 IP）")
                }

                Section {
                    Button {
                        Task {
                            alertMessage = await mapping.mapAll()
                            await mapping.verifyAll()
                        }
                    } label: {
                        Label(mapping.isMapping ? "映射中…" : "一键映射", systemImage: "arrow.triangle.branch")
                    }
                    .disabled(mapping.isMapping || store.domains.isEmpty)
                    Button {
                        Task { await mapping.verifyAll() }
                    } label: {
                        Label(mapping.isVerifying ? "检测中…" : "检测映射", systemImage: "checkmark.shield")
                    }
                    .disabled(mapping.isVerifying || store.domains.isEmpty)
                } footer: {
                    Text("检测项：① Cloudflare API 中的记录值是否为分配的 IP 且未开启代理；② Cloudflare / Google 公共 DNS 是否已解析到该 IP；③ 该 IP 的 443 端口是否可以连通。")
                }
            }
            .navigationTitle("域名映射")
            .toolbar { EditButton() }
            .alert(alertMessage ?? "", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
                Button("好") {}
            }
        }
    }

    /// 按当前测速结果预览每个域名将分配到的 IP
    private var preview: [UUID: String] {
        MappingService.assign(domains: store.domains, results: store.results)
    }

    private func normalized(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private func addDomain() {
        let name = normalized(newName)
        guard !name.isEmpty else { return }
        guard !store.domains.contains(where: { $0.name == name && $0.type == newType }) else {
            alertMessage = "\(name) 的 \(newType.rawValue) 记录已存在"
            return
        }
        store.domains.append(DomainEntry(name: name, type: newType))
        newName = ""
    }
}

private struct DomainRow: View {
    let index: Int
    let domain: DomainEntry
    let preview: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(index). \(domain.name)").font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
                Text(domain.type.rawValue)
                    .font(.caption.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
            }
            if let ip = domain.assignedIP {
                Text("当前映射：\(ip)").font(.system(.footnote, design: .monospaced))
            }
            if let p = preview, p != domain.assignedIP {
                Text("待映射：\(p)").font(.system(.footnote, design: .monospaced)).foregroundStyle(.orange)
            }
            statusLine("映射", domain.mapStatus)
            if domain.verify.checkedAt != nil || domain.verify.api == .running {
                statusLine("API 记录", domain.verify.api)
                statusLine("DNS 解析", domain.verify.dns)
                statusLine("连通性", domain.verify.tcp)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func statusLine(_ title: String, _ state: CheckState) -> some View {
        if state != .unknown {
            HStack(alignment: .top, spacing: 6) {
                Text(state.symbol)
                Text(title).bold()
                Text(state.message).foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }
}
