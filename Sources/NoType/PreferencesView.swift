import AppKit
import SwiftUI
import ApplicationServices
import UniformTypeIdentifiers
import NoTypeCore

struct PreferencesView: View {
    @ObservedObject var state: AppState
    @State private var cloudKeyDraft = ""
    @State private var confirmRemoveCloudKey = false
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("设置").font(.system(size: 26, weight: .semibold))
            card("语音引擎", icon: "mic") {
                Picker("转写方式", selection: $state.preferences.engine) {
                    Text("Whisper · 本地模型").tag("whisper")
                    Text("Apple · 设备端语音识别").tag("apple")
                    Text("云端 API · 自定义").tag("cloud")
                }.pickerStyle(.segmented).disabled(state.isBusy)
                    .onChange(of: state.preferences.engine) { _, engine in
                        if engine == "apple" && state.preferences.locale == "auto" { state.preferences.locale = "zh-CN" }
                    }
                Text(state.preferences.engine == "cloud" ? "录音将通过 HTTPS 上传至你配置的语音服务，按该服务商 API 额度计费。Codex 整理是独立的后续步骤。" : state.preferences.engine == "apple"
                     ? "使用 Apple Speech 的设备端识别。需要语音识别权限及对应语言资源，不支持离线的语言会报错。"
                     : "音频由本机 whisper.cpp 识别。small 多语言模型约 466 MiB，识别时才占用算力。")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                Picker("语音语言", selection: $state.preferences.locale) {
                    Text("中文（简体）").tag("zh-CN")
                    Text("English (US)").tag("en-US")
                    Text("日本語").tag("ja-JP")
                    Text("自动检测（Whisper / 云端）").tag("auto")
                }.disabled(state.isBusy)
                if state.preferences.engine == "whisper" {
                    pathRow("Whisper 程序", value: $state.preferences.whisperExecutable)
                    pathRow("模型文件", value: $state.preferences.whisperModel)
                    Text(FileManager.default.fileExists(atPath: state.preferences.whisperModel) ? "模型已就绪。" : "模型尚未就绪，或文件路径不存在。")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                } else if state.preferences.engine == "apple" {
                    Button("打开 macOS 听写设置") { state.openDictationSettings() }
                    Text("若提示 Siri 与听写已关闭，请在“系统设置 → 键盘 → 听写”开启听写，再回来重试。支持设备端识别不代表系统听写服务已启用。")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    Text("Apple 引擎不能使用“自动检测”；请选择具体语言。语言资源可用性由 macOS 决定。")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    HStack { Text(state.appleDiagnostic).font(.system(size: 11)).foregroundStyle(Palette.muted)
                        Spacer(); Button("检查支持情况") { state.checkApple() } }
                } else if state.preferences.engine == "cloud" {
                    cloudSettings
                }
            }
            card("Codex 整理", icon: "sparkles") {
                Toggle("转写后自动整理文字", isOn: $state.preferences.useCodex).disabled(state.isBusy)
                Text("复用本机 Codex CLI 的现有登录。开启后，转写文字、词库与写作偏好会发送到 Codex 云端；无需在 NoType 中填写 API Key。")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                pathRow("Codex 程序", value: $state.preferences.codexExecutable)
                HStack {
                    Picker("模型", selection: $state.preferences.codexModel) {
                        Text(state.automaticCodexModel.map { "自动选择 · \($0.displayName)" } ?? "自动选择（正在读取模型）").tag("")
                        if !state.preferences.codexModel.isEmpty && !state.models.contains(where: { $0.model == state.preferences.codexModel }) {
                            Text("\(state.preferences.codexModel)（当前目录未找到）").tag(state.preferences.codexModel)
                        }
                        ForEach(state.models, id: \.model) { model in
                            Text(model.displayName + (model.model == state.recommendedCodexModel?.model ? " · 推荐" : "")).tag(model.model)
                        }
                    }.pickerStyle(.menu).disabled(state.isBusy)
                    Button("刷新模型") { state.checkCodex() }.disabled(state.diagnosticBusy || state.isBusy)
                }
                if state.models.isEmpty {
                    Text(state.diagnosticBusy ? "正在读取此 Codex CLI 的可选模型…" : "模型列表尚未载入，请点击“刷新模型”。")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                } else {
                    Text("可选模型（\(state.models.count)）· 点击即可切换")
                        .font(.system(size: 12, weight: .medium))
                    Text("实时读取本机所配置 Codex CLI 的可选目录。更换电脑、登录账号或升级 CLI 后，可点“刷新模型”重新连接获取。")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 8) {
                        ForEach(state.models, id: \.model) { model in
                            Button {
                                state.preferences.codexModel = model.model
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: state.selectedCodexModel?.model == model.model ? "largecircle.fill.circle" : "circle")
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(model.displayName + (model.model == state.recommendedCodexModel?.model ? " · 短文本推荐" : ""))
                                            .font(.system(size: 12, weight: .medium))
                                        Text(model.model).font(.system(size: 11, design: .monospaced))
                                        if let description = model.description, !description.isEmpty {
                                            Text(description).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }.foregroundStyle(Palette.ink).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Palette.sidebar.opacity(0.34), in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain).disabled(state.isBusy)
                                .accessibilityLabel("选择 \(model.displayName)" + (state.selectedCodexModel?.model == model.model ? "，已选中" : ""))
                        }
                    }
                    if let selected = state.selectedCodexModel {
                        Text("当前使用：\(selected.model)").font(.system(size: 12, weight: .medium)).textSelection(.enabled)
                    }
                    if let recommended = state.recommendedCodexModel {
                        Text("默认推荐 \(recommended.displayName)，优先兼顾短文本纠错、去口头语与响应速度；实际耗时受网络和服务负载影响。")
                            .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if state.diagnosticBusy { ProgressView().controlSize(.small) }
                Text(state.diagnostic).font(.system(size: 11)).foregroundStyle(Palette.muted).textSelection(.enabled)
                Toggle("低延迟模式（自动选择较快模型与最低可用推理强度）", isOn: Binding(get: { state.preferences.codexPreferFast ?? true }, set: { state.preferences.codexPreferFast = $0 }))
                Toggle("Codex 超过 20 秒时自动使用转写原文", isOn: Binding(get: { state.preferences.codexTimeoutFallback ?? true }, set: { state.preferences.codexTimeoutFallback = $0 }))
                Text("后台预热并复用 CLI；每次整理仍使用独立会话。等待时可点“立即使用原文”跳过优化。模型响应速度仍受网络与服务负载影响。")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            card("输入与快捷键", icon: "keyboard") {
                ShortcutSettings(state: state)
                Toggle("完成后自动输入原应用", isOn: $state.preferences.autoInsert).disabled(state.isBusy)
                Text("默认自动输入录音前的输入框。若你打开了 NoType，完成后会返回原应用；若切到其他应用或输入框，则仅复制。首次需要辅助功能授权。")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                HStack {
                    Text(state.inputPermissionGranted ? "辅助功能权限：已授权" : "自动输入需要辅助功能权限").font(.system(size: 12))
                    Spacer(); Button("授权辅助功能") { state.insertion.requestPermission() }
                }
            }
            card("本机数据", icon: "externaldrive") {
                Toggle("保存文字历史", isOn: $state.preferences.saveHistory)
                Text("只保存原始转写、最终文字、模式和时间。录音成功后删除；识别失败时临时保留，重试成功、开始新录音、放弃或退出时清理。导入的原始文件保留。关闭历史不会删除已有记录。")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                Button("打开数据目录") {
                    try? FileManager.default.createDirectory(at: AppState.supportDirectory, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(AppState.supportDirectory)
                }
            }
        }
        .task { state.ensureCodexModels() }
    }
    private var cloudSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("接口协议", selection: $state.cloudConfiguration.apiProtocol) {
                Text("千问 ASR Flash · 音频 Chat 接口").tag(SpeechAPIProtocol.qwen)
                Text("通用转写 · multipart /audio/transcriptions").tag(SpeechAPIProtocol.multipart)
            }
            HStack {
                Button("千问北京预设") { useQwenPreset("https://dashscope.aliyuncs.com/compatible-mode/v1") }
                Button("千问新加坡预设") { useQwenPreset("https://dashscope-intl.aliyuncs.com/compatible-mode/v1") }
            }
            TextField("HTTPS Base URL 或完整接口地址", text: $state.cloudConfiguration.baseURL)
                .textFieldStyle(GlacierTextFieldStyle()).font(.system(size: 11, design: .monospaced))
            TextField("模型名称，例如 qwen3-asr-flash", text: $state.cloudConfiguration.model).textFieldStyle(GlacierTextFieldStyle())
            SecureField("API Key（填入后点击保存）", text: $cloudKeyDraft).textFieldStyle(GlacierTextFieldStyle())
            HStack {
                Button("保存 API Key") { if state.saveCloudKey(cloudKeyDraft) { cloudKeyDraft = "" } }.disabled(cloudKeyDraft.isEmpty)
                Button("删除已存 Key", role: .destructive) { confirmRemoveCloudKey = true }
                Spacer()
            }
            Text("地址/协议变更后需要为该接口另存 Key。北京与新加坡的 Key 不通用。千问预设使用 qwen3-asr-flash 系列，不支持异步 filetrans 模型；通用协议需要服务商明确支持 multipart 转写。")
                .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            Button("用内置示例测试转写（会调用 API）") { state.testCloudSpeech() }.disabled(state.cloudTestBusy)
            if state.cloudTestBusy { ProgressView().controlSize(.small) }
            Text(state.cloudStatus).font(.system(size: 11)).foregroundStyle(Palette.muted).textSelection(.enabled)
            Link("千问语音接口文档", destination: URL(string: "https://help.aliyun.com/zh/model-studio/recording-file-recognition-qwen")!).font(.system(size: 11))
        }.disabled(state.isBusy || state.cloudTestBusy)
            .confirmationDialog("删除当前接口保存在钥匙串中的 API Key？", isPresented: $confirmRemoveCloudKey) {
                Button("删除 Key", role: .destructive) { state.removeCloudKey() }
            }
    }
    private func useQwenPreset(_ url: String) {
        var config = CloudSpeechConfiguration(); config.baseURL = url
        state.cloudConfiguration = config; cloudKeyDraft = ""
    }
    private func pathRow(_ label: String, value: Binding<String>) -> some View {
        HStack {
            Text(label).font(.system(size: 12)).frame(width: 86, alignment: .leading)
            TextField("绝对文件路径", text: value).font(.system(size: 11, design: .monospaced)).textFieldStyle(GlacierTextFieldStyle())
            Button("选择") {
                let panel = NSOpenPanel(); panel.allowsMultipleSelection = false
                if panel.runModal() == .OK, let url = panel.url { value.wrappedValue = url.path }
            }
        }.disabled(state.isBusy)
    }
    private func card<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(title == "Codex 整理" ? Palette.ai : title == "语音引擎" ? Palette.coral : Palette.ink)
            content()
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).nativeCard(radius: 16)
    }
}
