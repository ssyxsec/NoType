import AppKit
import SwiftUI
import NoTypeCore

enum Palette {
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255, alpha: 1)
        })
    }
    static let ink = adaptive(0x282E3A, 0xE8ECF2)
    static let muted = adaptive(0x7A8290, 0x929EAD)
    static let green = adaptive(0x087CD5, 0x58BBFB)
    static let violet = adaptive(0x8975C9, 0xAC96EF)
    static let canvas = adaptive(0xEDF0F4, 0x121820)
    static let card = adaptive(0xE4E9EF, 0x202A35)
    static let sidebar = adaptive(0xC9DFEE, 0x172B3A)
    static let line = adaptive(0xB6C1CE, 0x415267).opacity(0.4)
    static let coral = adaptive(0xC46850, 0xF4A28B)
    static let ai = adaptive(0x7D67BC, 0xB7A0F0)
    static let editor = adaptive(0xE3E7EC, 0x1A232D)
    static let aiSurface = adaptive(0xE6E2EF, 0x282337)
    static let hudBlue = adaptive(0x006ED6, 0x61C1FF)
    static let gradient = LinearGradient(colors: [green, violet], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let hudGradient = LinearGradient(colors: [hudBlue, adaptive(0x21B4EB, 0x3DE0F4)], startPoint: .bottomLeading, endPoint: .topTrailing)

}

struct MainView: View {
    @ObservedObject var state: AppState
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 182)
            Rectangle().fill(Palette.line).frame(width: 0.7)
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("WORKSPACE").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.8).foregroundStyle(Palette.muted)
                    Text("/").foregroundStyle(Palette.line)
                    Text(sectionTitle).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted)
                    Spacer()
                    Circle().fill(state.phase == .recording ? .red : Palette.green).frame(width: 5, height: 5)
                    Text(state.phase.title).font(.system(size: 10)).foregroundStyle(Palette.muted)
                }.padding(.horizontal, 30).frame(height: 58)
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if state.section == "history" { HistoryView(state: state) }
                        else if state.section == "statistics" { StatisticsView(state: state) }
                        else if state.section == "glossary" { GlossaryView(state: state) }
                        else if state.section == "settings" { PreferencesView(state: state) }
                        else { DictationView(state: state) }
                        if !state.error.isEmpty { message(state.error, error: true) }
                        if state.appleSetupRequired { Button("打开 macOS 听写设置") { state.openDictationSettings() } }
                        if state.canRetryAudio {
                            HStack {
                                Button("用 Whisper 重试") { state.retryTranscription(useWhisper: true) }.nativeGlassButton(prominent: true)
                                Button("重试当前引擎") { state.retryTranscription(useWhisper: false) }
                                Button("放弃录音") { state.discardRetryAudio() }
                            }.disabled(state.isBusy)
                        }
                        if !state.notice.isEmpty { message(state.notice, error: false) }
                    }.padding(.horizontal, 30).padding(.top, 16).padding(.bottom, 28)
                        .frame(maxWidth: 1000).frame(maxWidth: .infinity)
                }.id(state.section)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    ZStack(alignment: .topTrailing) {
                        Palette.canvas
                        Ellipse().fill(Palette.violet.opacity(0.07)).frame(width: 460, height: 260).blur(radius: 80).offset(x: 120, y: -80)
                        Ellipse().fill(Palette.green.opacity(0.05)).frame(width: 400, height: 300).blur(radius: 90).offset(x: -100, y: 250)
                    }.clipped()
                }
        }.background(Palette.canvas).foregroundStyle(Palette.ink).tint(Palette.green).buttonStyle(GlassActionStyle())
            .ignoresSafeArea(.container, edges: .top)
            .background(WindowChromeConfigurator().allowsHitTesting(false))
    }
    private var sectionTitle: String {
        switch state.section { case "history": return "转写历史"; case "statistics": return "使用统计"; case "glossary": return "个人词库"
        case "settings": return "设置"; default: return "语音工作台" }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "waveform").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 29, height: 29).background(Palette.gradient, in: RoundedRectangle(cornerRadius: 9))
                Text("NoType").font(.system(size: 20, weight: .semibold, design: .rounded)).tracking(-0.7)
            }.padding(.horizontal, 20).padding(.top, 52).padding(.bottom, 32)
            Text("声音，即文字").font(.system(size: 10)).foregroundStyle(Palette.muted).padding(.leading, 23).padding(.bottom, 20)
            navigation("dictation", "语音工作台", "waveform")
            navigation("history", "转写历史", "clock.arrow.circlepath")
            navigation("statistics", "使用统计", "chart.bar.xaxis")
            navigation("glossary", "个人词库", "text.book.closed")
            Spacer()
            Label(state.preferences.engine == "cloud" ? "云端识别" : "本机识别", systemImage: state.preferences.engine == "cloud" ? "cloud" : "lock.shield")
                .font(.system(size: 10)).foregroundStyle(Palette.muted).padding(.horizontal, 22).padding(.bottom, 15)
            navigation("settings", "设置", "slider.horizontal.3")
            Text("NoType " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""))
                .font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted.opacity(0.7))
                .padding(.horizontal, 23).padding(.top, 12).padding(.bottom, 22)
        }.background(Palette.sidebar.opacity(0.62))
    }
    private func navigation(_ id: String, _ title: String, _ icon: String) -> some View {
        Button { state.section = id } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 13)).frame(width: 18)
                Text(title).font(.system(size: 12, weight: state.section == id ? .semibold : .regular))
                Spacer(minLength: 0)
                if id == "history" { Text(state.records.count.formatted()).font(.system(size: 9, design: .monospaced)).opacity(0.6) }
            }.foregroundStyle(state.section == id ? Palette.green : Palette.muted)
                .padding(.horizontal, 12).frame(height: 38)
                .background(state.section == id ? Palette.green.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .leading) {
                    if state.section == id { Capsule().fill(Palette.gradient).frame(width: 3, height: 14).padding(.leading, 1) }
                }
        }.buttonStyle(.plain).padding(.horizontal, 12).padding(.bottom, 6)
    }
    private func message(_ text: String, error: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: error ? "exclamationmark.circle" : "checkmark.circle").foregroundStyle(error ? Color.orange : Palette.green)
            Text(text).textSelection(.enabled).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
            Button { if error { state.error = "" } else { state.notice = "" } } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(Palette.muted).accessibilityLabel("关闭提示")
        }.padding(14).nativeCard()
    }
}

struct DictationView: View {
    @ObservedObject var state: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("想到什么，就说出来。").font(.system(size: 28, weight: .semibold)).tracking(-0.6)
                    Text("说出想法，文字会回到你的输入框。").font(.system(size: 13)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Button { state.importAudio() } label: { Label("导入音频", systemImage: "square.and.arrow.down") }
                    .disabled(state.isBusy)
            }
            recorderCard
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("表达方式").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Toggle("Codex 整理", isOn: $state.preferences.useCodex).tint(Palette.ai).toggleStyle(.switch).controlSize(.small).disabled(state.isBusy)
                }
                HStack(spacing: 9) {
                    ForEach(WritingMode.allCases) { mode in
                        Button { state.mode = mode } label: { Label(mode.title, systemImage: mode.icon).frame(maxWidth: .infinity) }
                            .buttonStyle(GlassActionStyle(prominent: state.mode == mode)).disabled(state.isBusy)
                    }
                }
            }

            HStack(alignment: .top, spacing: 16) {
                editor(title: "原始转写", subtitle: "也可以直接输入文字", text: $state.rawText, accent: Palette.muted, surface: Palette.editor)
                editor(title: "最终文字", subtitle: state.refinementStatus.isEmpty ? "可以在这里继续修改" : state.refinementStatus, text: $state.resultText, accent: Palette.ai, surface: Palette.aiSurface)
            }
            HStack {
                Button("新建") { state.newDraft() }.disabled(state.isBusy)
                Spacer()
                if state.phase == .refining || state.phase == .transcribing || state.phase == .uploading {
                    ProgressView().controlSize(.small)
                    if state.phase == .refining { Button("立即使用原文") { state.useRawImmediately() } }
                    Button("取消处理") { state.cancelProcessing() }
                } else {
                    Button { state.refineText() } label: { Label("用 Codex 整理", systemImage: "sparkles") }
                        .buttonStyle(GlassActionStyle(prominent: true, accent: Palette.ai))
                        .disabled(state.isBusy || state.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button { state.copyResult() } label: { Label("复制文字", systemImage: "doc.on.doc") }
                        .buttonStyle(GlassActionStyle(prominent: true)).disabled(state.resultText.isEmpty)
                    Button("输入到原应用") { state.retryInsertion() }.disabled(state.isBusy || state.resultText.isEmpty)
                }
            }
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lock.shield")
                Text(state.preferences.engine == "cloud" ? "音频发送至你配置的语音服务。开启 Codex 后，文字与词库会发送至 Codex。" : "语音在本机转写。开启 Codex 后，文字与词库会发送至 Codex。")
                    .fixedSize(horizontal: false, vertical: true)
            }.font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(3)
        }
    }
    private var recorderCard: some View {
        VStack(spacing: 20) {
            HStack {
                Label(state.engineTitle, systemImage: "desktopcomputer")
                Spacer()
                Text(state.recordingShortcut.displayName).font(.system(size: 11, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 9).padding(.vertical, 5).background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
            }.font(.system(size: 11)).foregroundStyle(Palette.muted)
            HStack(spacing: 24) {
                Button { state.toggleRecording() } label: {
                    Image(systemName: state.phase == .recording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 23, weight: .medium)).foregroundStyle(Palette.coral)
                        .frame(width: 28, height: 40)
                }.buttonStyle(GlassActionStyle(prominent: true, accent: Palette.coral))
                    .tint(state.phase == .recording ? .red : .accentColor).disabled(state.isBusy && state.phase != .recording)
                VStack(alignment: .leading, spacing: 7) {
                    Text(state.phase == .idle ? "按下快捷键，开始说话" : state.phase.title).font(.system(size: 19, weight: .medium))
                    Text(state.phase == .recording ? "再次按下结束 · 最长 5 分钟" : "在其他应用中也能使用全局快捷键")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                Spacer()
                if state.phase == .recording {
                    Text(String(format: "%02d:%02d", Int(state.elapsed) / 60, Int(state.elapsed) % 60)).monospacedDigit().font(.system(size: 23, weight: .light))
                    Button("取消") { state.cancelRecording() }.buttonStyle(GlassActionStyle())
                }
            }.padding(.vertical, 10)
        }.padding(24).nativeCard(radius: 20)
            .overlay(alignment: .trailing) {
                Image(systemName: "waveform").font(.system(size: 110, weight: .ultraLight)).foregroundStyle(Palette.gradient).opacity(0.06)
                    .padding(.trailing, 24).allowsHitTesting(false)
            }
    }
    private func editor(title: String, subtitle: String, text: Binding<String>, accent: Color, surface: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) { Capsule().fill(accent).frame(width: 3, height: 10); Text(title).font(.system(size: 12, weight: .semibold)); Spacer()
                Text("\(text.wrappedValue.count) 字").font(.system(size: 10)).foregroundStyle(Palette.muted) }
            TextEditor(text: text).font(.system(size: 14)).lineSpacing(5).scrollContentBackground(.hidden)
                .foregroundStyle(Palette.ink).padding(10).frame(height: 150).background(surface.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.line)).disabled(state.isBusy)
            Text(subtitle).font(.system(size: 10)).foregroundStyle(Palette.muted)
        }.frame(maxWidth: .infinity)
    }
}

struct RecordingOverlay: View {
    @ObservedObject var state: AppState
    @ObservedObject var recorder: AudioCapture
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var recording: Bool { state.phase == .recording }
    private var finished: Bool { state.phase == .idle }
    private var title: String {
        switch state.phase {
        case .recording: return "聆听中"
        case .transcribing: return "转写中"
        case .uploading: return "云端识别"
        case .refining: return "Codex 整理"
        case .inserting: return "输入中"
        case .preparing: return "准备中"
        case .idle: return !state.error.isEmpty ? "处理未完成" : state.overlayMessage.contains("未自动输入") ? "文字已复制" : "文字已就绪"
        }
    }
    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 0.06, paused: recording || finished)) { timeline in
            HStack(spacing: 8) {
                activity(at: timeline.date).frame(width: 20, height: 20).accessibilityHidden(true)
                Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1).foregroundStyle(Palette.hudBlue)
                    .contentTransition(.opacity)
                Spacer(minLength: 0)
                if !finished {
                    Text(clock(recording ? state.elapsed : state.processingStartedAt.map { timeline.date.timeIntervalSince($0) } ?? 0))
                        .font(.system(size: 9, weight: .medium, design: .monospaced)).monospacedDigit().foregroundStyle(Palette.hudBlue.opacity(0.75))
                }
                if recording {
                    action("stop.fill", title: "结束录音") { state.toggleRecording() }
                } else if finished {
                    action("arrow.up.right", title: "查看结果") { state.openOverlayResult() }
                } else if state.phase != .inserting && state.phase != .preparing {
                    action("xmark", title: "取消处理") { state.cancelProcessing() }
                } else {
                    Color.clear.frame(width: 16, height: 16)
                }
            }
            .padding(.horizontal, 10).frame(width: 208, height: 36)
        }
        .accessibilityElement(children: .contain).accessibilityLabel("NoType 语音状态")
    }
    @ViewBuilder private func activity(at date: Date) -> some View {
        if finished {
            Image(systemName: state.error.isEmpty ? "checkmark" : "exclamationmark")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(state.error.isEmpty ? Palette.hudBlue : .orange)
        } else if recording {
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule().fill(Palette.hudGradient)
                        .frame(width: 2, height: 3 + CGFloat(recorder.level) * CGFloat(7 + (index * 7) % 15))
                }
            }
        } else {
            HStack(spacing: 3.5) {
                ForEach(0..<3) { index in
                    Capsule().fill(Palette.hudGradient)
                        .frame(width: 3, height: reduceMotion ? 8 : 6 + 12 * (0.5 + 0.5 * sin(date.timeIntervalSinceReferenceDate * 3 - Double(index) * 0.8)))
                }
            }
        }
    }
    private func action(_ symbol: String, title: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Palette.hudBlue).frame(width: 16, height: 16)
                .contentShape(Circle())
        }.buttonStyle(.plain).help(title).accessibilityLabel(title)
    }
    private func clock(_ seconds: TimeInterval) -> String {
        let value = Int(max(0, seconds))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}

struct HistoryView: View {
    @ObservedObject var state: AppState
    @State private var query = ""
    @State private var confirmClear = false
    private var filtered: [DictationRecord] { state.records.filter { query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) || $0.rawText.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { VStack(alignment: .leading, spacing: 8) { Text("转写历史").font(.system(size: 26, weight: .semibold))
                Text("历史仅保存在这台 Mac，可随时删除。").font(.system(size: 12)).foregroundStyle(Palette.muted) }
                Spacer(); Button("导出") { state.exportHistory() }; Button("清空", role: .destructive) { confirmClear = true }.disabled(state.records.isEmpty) }
            TextField("搜索转写内容", text: $query).textFieldStyle(GlacierTextFieldStyle())
            if filtered.isEmpty {
                VStack(spacing: 14) { Image(systemName: "clock.arrow.circlepath").font(.system(size: 32)).foregroundStyle(Palette.muted)
                    Text(query.isEmpty ? "从第一段录音开始" : "没有找到匹配内容").font(.system(size: 16))
                    Text("完成的语音转写与 Codex 整理会显示在这里。").font(.system(size: 12)).foregroundStyle(Palette.muted)
                }.frame(maxWidth: .infinity).padding(.vertical, 100)
            }
            ForEach(filtered) { record in
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text(record.createdAt, format: .dateTime.month().day().hour().minute()).font(.system(size: 11)).foregroundStyle(Palette.muted)
                        Text(record.mode).font(.system(size: 10)).padding(.horizontal, 7).padding(.vertical, 3).background(Palette.green.opacity(0.08), in: Capsule())
                        Spacer(); Text(record.appName).font(.system(size: 10)).foregroundStyle(Palette.muted) }
                    Text(record.text).font(.system(size: 14)).lineLimit(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    HStack { Button("打开编辑") { state.load(record) }.disabled(state.isBusy)
                        Button("复制") { InputInsertion.copy(record.text) }; Spacer()
                        Button(role: .destructive) { state.delete(record.id) } label: { Image(systemName: "trash") } }.controlSize(.small)
                }.padding(20).background(Palette.card.opacity(0.58), in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line))
            }
        }.confirmationDialog("清空全部转写历史？此操作无法撤销。", isPresented: $confirmClear) {
            Button("清空全部历史", role: .destructive) { state.clearHistory() }
        }
    }
}

struct GlossaryView: View {
    @ObservedObject var state: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("个人词库").font(.system(size: 26, weight: .semibold))
            Text("每行填写一个人名、产品名或术语，也可以写“识别错误 → 正确写法”。词库会随文字交给 Codex，用于整理时纠错；不会用于训练语音模型。")
                .font(.system(size: 13)).foregroundStyle(Palette.muted).lineSpacing(5)
            TextEditor(text: $state.preferences.glossary).font(.system(size: 15, design: .monospaced)).scrollContentBackground(.hidden)
                .padding(18).frame(height: 330).background(Palette.card.opacity(0.58), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line))
            Label("\(state.glossary.count) 个词条 · 自动保存在本机", systemImage: "checkmark.circle").font(.system(size: 12)).foregroundStyle(Palette.green)
            Text("写作偏好").font(.system(size: 14, weight: .semibold))
            Text("例如：使用简体中文，保留技术术语，不要使用感叹号。").font(.system(size: 12)).foregroundStyle(Palette.muted)
            TextEditor(text: $state.preferences.customInstruction).font(.system(size: 14)).scrollContentBackground(.hidden)
                .padding(12).frame(height: 100).background(Palette.card.opacity(0.58), in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.line))
        }
    }
}
