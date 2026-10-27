import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var draft = CFCredentials()
    @State private var status: CheckState = .unknown
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("认证方式", selection: $draft.authType) {
                        ForEach(CFAuthType.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    switch draft.authType {
                    case .apiToken:
                        SecureField("API Token", text: $draft.apiToken)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    case .globalKey:
                        TextField("账号邮箱", text: $draft.email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("Global API Key", text: $draft.globalKey)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                } header: {
                    Text("Cloudflare 凭证")
                } footer: {
                    Text("推荐使用 API Token：在 Cloudflare 控制台「我的个人资料 → API 令牌」创建，权限需包含 区域-Zone-读取 与 区域-DNS-编辑。用户令牌和账户令牌都支持。凭证保存在本机钥匙串中。")
                }

                Section {
                    Button("保存并验证") { Task { await saveAndVerify() } }
                        .disabled(!draft.isComplete || status == .running)
                    if status != .unknown {
                        HStack(alignment: .top) {
                            Text(status == .running ? "验证中…" : status.symbol)
                            Text(status.message).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Button("清除凭证", role: .destructive) {
                        store.clearCredentials()
                        draft = CFCredentials()
                        status = .unknown
                    }
                }

                Section("关于") {
                    LabeledContent("测速核心", value: "XIU2/CloudflareSpeedTest")
                    Link("项目主页", destination: URL(string: "https://github.com/XIU2/CloudflareSpeedTest")!)
                }
            }
            .navigationTitle("设置")
            .onAppear {
                if !loaded {
                    draft = store.credentials
                    loaded = true
                }
            }
        }
    }

    private func saveAndVerify() async {
        guard store.saveCredentials(draft) else {
            status = .failure("保存到钥匙串失败")
            return
        }
        // 凭证变化后 Zone 缓存可能失效
        for d in store.domains {
            store.updateDomain(d.id) { $0.zoneID = nil }
        }
        status = .running
        do {
            status = .success(try await CloudflareAPI(credentials: draft).verifyCredentials())
        } catch {
            status = .failure(error.localizedDescription)
        }
    }
}
