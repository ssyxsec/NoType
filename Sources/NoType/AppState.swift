import AppKit
import SwiftUI
import NoTypeCore
import UniformTypeIdentifiers
import Speech
import ApplicationServices

enum WorkPhase: String { case idle, preparing, recording, transcribing, uploading, refining, inserting
    var title: String { switch self { case .idle: return "准备就绪"; case .recording: return "正在聆听"
    case .preparing: return "正在准备麦克风"; case .transcribing: return "正在转写语音"; case .uploading: return "云端语音转写中"; case .refining: return "Codex 正在整理"; case .inserting: return "正在输入原应用" } }
}

struct AppPreferences: Codable {
    var engine = "whisper"
    var locale = "zh-CN"
    var codexExecutable = CodexBridge.defaultExecutable
    var codexModel = ""
    var whisperExecutable = "/opt/homebrew/bin/whisper-cli"
    var whisperModel = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NoType/Models/ggml-small.bin").path
    var useCodex = true
    var autoInsert = true
    var automaticInputMigration: Int? = 1
    var saveHistory = true
    var glossary = "NoType\nTypeless\nCodex"
    var customInstruction = ""
    var cloudSpeech: CloudSpeechConfiguration?
    var codexPreferFast: Bool?
    var codexTimeoutFallback: Bool?
    var recordingShortcut: RecordingShortcut?
}

@MainActor final class AppState: ObservableObject {
    @Published var preferences: AppPreferences { didSet { persistPreferences() } }
    @Published var phase: WorkPhase = .idle { didSet { updateOverlay(from: oldValue) } }
    @Published private(set) var overlayMessage = ""
    @Published private(set) var processingStartedAt: Date?
    @Published var mode: WritingMode = .clean
    @Published var rawText = ""
    @Published var resultText = ""
    @Published private(set) var refinementStatus = ""
    @Published var records: [DictationRecord] = []
    @Published var models: [CodexModel] = []
    @Published var diagnostic = "尚未检查 Codex"
    @Published var diagnosticBusy = false
    @Published var appleDiagnostic = "首次使用 Apple 引擎时会请求语音识别权限。"
    @Published var notice = ""
    @Published var error = ""
    @Published var appleSetupRequired = false
    @Published var canRetryAudio = false
    @Published var cloudStatus = "Key 存入 macOS 钥匙串，按协议与 API 地址分别保存。留空不会删除已保存的 Key。"
    @Published var cloudTestBusy = false
    @Published var inputPermissionGranted = false
    @Published var hotkeyStatus = ""
    @Published var elapsed: Double = 0
    @Published var section = "dictation"
    let recorder = AudioCapture()
    let insertion = InputInsertion()
    private let codex = CodexBridge(timeout: 20)
    private let store: HistoryStore
    private var timer: Timer?
    private var recordingStarted: Date?
    private var currentRecordID: UUID?
    private var activeTask: Task<Void, Never>?
    private var targetName = "NoType"
    private var activeAudio: URL?
    private var floatingPanel: NSPanel?
    private var overlayDismissTask: Task<Void, Never>?
    private var insertionAttempted = false
    private var hotkey: GlobalHotkey?
    private var historyNeedsRecovery = false
    private var retryAudio: URL?
    private var retryAudioOwned = false
    private var pendingInsertion = false
    private var prewarmTask: Task<Void, Never>?
    private var useRawOnCancellation = false
    private var draftSource = "typed"
    private var dictationCharacters: Int?
    private var hotkeyCaptureActive = false
    var recordingShortcut: RecordingShortcut { preferences.recordingShortcut ?? .standard }
    var isBusy: Bool { phase != .idle }
    var cloudConfiguration: CloudSpeechConfiguration {
        get { preferences.cloudSpeech ?? CloudSpeechConfiguration() }
        set { preferences.cloudSpeech = newValue }
    }
    var engineTitle: String {
        switch preferences.engine { case "apple": return "Apple 设备端识别"; case "cloud": return "云端 API · " + cloudConfiguration.model; default: return "Whisper 本地识别" }
    }
    var glossary: [String] { preferences.glossary.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NoType", isDirectory: true)
    }
    init() {
        let prefsURL = Self.supportDirectory.appendingPathComponent("preferences.json")
        preferences = (try? JSONDecoder().decode(AppPreferences.self, from: Data(contentsOf: prefsURL))) ?? AppPreferences()
        store = HistoryStore(directory: Self.supportDirectory)
        inputPermissionGranted = AXIsProcessTrusted()
        if preferences.automaticInputMigration == nil {
            preferences.autoInsert = true
            preferences.automaticInputMigration = 1
            persistPreferences()
        }
        do { records = try store.load() } catch {
            historyNeedsRecovery = true
            self.error = "无法读取历史记录：\(error.localizedDescription)。原文件已保留，恢复前暂停写入历史。"
        }
    }
    func installHotkey() {
        guard hotkey == nil else { return }
        hotkey = GlobalHotkey(shortcut: recordingShortcut) { [weak self] in Task { @MainActor in self?.toggleRecording() } }
        if hotkey?.registered == false { error = "全局快捷键注册失败，可能与其他应用冲突。请使用窗口或菜单栏录音。" }
        warmCodex()
    }
    func beginHotkeyCapture() {
        guard !isBusy else { return }
        hotkeyCaptureActive = true; hotkey = nil; hotkeyStatus = ""
    }
    func endHotkeyCapture() {
        hotkeyCaptureActive = false
        if hotkey == nil { installHotkey() }
    }
    @discardableResult func applyHotkey(_ shortcut: RecordingShortcut) -> Bool {
        guard !isBusy else { return false }
        if let message = shortcut.validationError { hotkeyStatus = message; return false }
        if shortcut == recordingShortcut, hotkey?.registered == true { return true }
        let replacement = GlobalHotkey(shortcut: shortcut) { [weak self] in Task { @MainActor in self?.toggleRecording() } }
        guard replacement.registered else {
            hotkeyStatus = "这个快捷键已被系统或其他应用占用，请换一个组合。原设置已保留。"
            return false
        }
        hotkey = replacement; preferences.recordingShortcut = shortcut
        hotkeyStatus = "快捷键已保存：\(shortcut.displayName)"
        return true
    }
    func refreshInputPermission() { inputPermissionGranted = AXIsProcessTrusted() }
    var recommendedCodexModel: CodexModel? { CodexModel.recommendedForShortText(in: models) }
    var automaticCodexModel: CodexModel? {
        (preferences.codexPreferFast ?? true) ? recommendedCodexModel : (models.first { $0.isDefault } ?? models.first)
    }
    var selectedCodexModel: CodexModel? {
        models.first { $0.model == preferences.codexModel } ?? (preferences.codexModel.isEmpty ? automaticCodexModel : nil)
    }
    private func updateModels(_ available: [CodexModel]) {
        models = available
    }
    func ensureCodexModels() {
        guard models.isEmpty, !diagnosticBusy, prewarmTask == nil else { return }
        checkCodex()
    }
    func warmCodex() {
        guard preferences.useCodex, prewarmTask == nil else { return }
        let executable = preferences.codexExecutable
        prewarmTask = Task {
            defer { prewarmTask = nil }
            do { updateModels(try await codex.discoverModels(executable: executable)); diagnostic = "已载入 \(models.count) 个模型 · Codex 连接已预热" }
            catch { diagnostic = "预热失败，可在整理时重试：\(error.localizedDescription)" }
        }
    }
    private func persistPreferences() {
        do {
            try FileManager.default.createDirectory(at: Self.supportDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let path = Self.supportDirectory.appendingPathComponent("preferences.json")
            try JSONEncoder().encode(preferences).write(to: path, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
        } catch { self.error = "设置保存失败：\(error.localizedDescription)" }
    }
    func toggleRecording() {
        if phase == .recording { finishRecording(); return }
        guard phase == .idle, !hotkeyCaptureActive else { return }
        guard preferences.engine != "unconfigured" else {
            section = "settings"; error = "请先选择语音引擎。Codex 当前不能直接识别音频。"; return
        }
        insertion.captureTarget()
        draftSource = "recording"; dictationCharacters = nil
        useRawOnCancellation = false
        clearRetryAudio()
        targetName = insertion.targetName ?? "NoType"
        pendingInsertion = true
        // Never prompt on the recording hotkey. Permission is requested only by
        // the explicit Settings button; an untrusted app still records normally.
        activeTask = Task { [weak self] in
            guard let self else { return }
            do {
                phase = .preparing // blocks repeat presses while the permission dialog is open
                error = ""; appleSetupRequired = false; notice = ""; refinementStatus = ""; rawText = ""; resultText = ""; currentRecordID = nil; elapsed = 0
                activeAudio = try await recorder.start()
                try Task.checkCancellation()
                phase = .recording; recordingStarted = Date()
                timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, let start = self.recordingStarted else { return }
                        self.elapsed = Date().timeIntervalSince(start)
                        if self.elapsed >= 300 { self.finishRecording() }
                    }
                }
                showOverlay()
            } catch {
                recorder.cancel(); activeAudio = nil
                if error is CancellationError { notice = "已取消。" } else { self.error = error.localizedDescription }
                phase = .idle
            }
        }
    }
    private func finishRecording() {
        if let start = recordingStarted { elapsed = Date().timeIntervalSince(start) }
        timer?.invalidate(); timer = nil
        guard let audio = recorder.stop() else { phase = .idle; error = "没有可转写的录音。"; return }
        phase = .transcribing
        activeTask = Task { [weak self] in await self?.process(audio: audio, removeAfter: true) }
    }
    func cancelRecording() {
        activeTask?.cancel(); recorder.cancel(); timer?.invalidate(); timer = nil
        hideOverlay(); phase = .idle; notice = "已取消录音。"; activeAudio = nil
    }
    func cancelProcessing() { useRawOnCancellation = false; activeTask?.cancel(); notice = "正在取消…" }
    func importAudio() {
        guard !isBusy else { return }
        guard preferences.engine != "unconfigured" else { section = "settings"; error = "请先选择语音引擎。"; return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.wav, .mp3, .mpeg4Audio, .aiff]
        panel.allowsMultipleSelection = false
        panel.message = preferences.engine == "cloud" ? "音频将发送到你配置的语音 API 服务；开启 Codex 整理后，文字再发送给 Codex。" : "音频在本机转写；开启 Codex 整理时会将文字发送给 Codex。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        clearRetryAudio(); pendingInsertion = false; appleSetupRequired = false
        draftSource = "imported"; dictationCharacters = nil
        rawText = ""; resultText = ""; refinementStatus = ""; currentRecordID = nil; error = ""; elapsed = 0; targetName = "导入音频"; phase = .transcribing
        activeTask = Task { [weak self] in await self?.process(audio: url, removeAfter: false) }
    }
    private func process(audio: URL, removeAfter: Bool) async {
        let prefs = preferences; let writingMode = mode
        var keepForRetry = false
        defer {
            if removeAfter && !keepForRetry { try? FileManager.default.removeItem(at: audio) }
            activeAudio = nil; phase = .idle
        }
        do {
            if prefs.engine == "cloud" {
                phase = .uploading
                let config = prefs.cloudSpeech ?? CloudSpeechConfiguration()
                let account = try config.endpoint().absoluteString
                let key = try CloudCredentialStore.read(account: config.apiProtocol.rawValue + "|" + account)
                rawText = try await LocalTranscriber().transcribeCloud(audio: audio, configuration: config, apiKey: key, locale: prefs.locale)
            } else {
                phase = .transcribing
                rawText = try await LocalTranscriber().transcribe(audio: audio, engine: prefs.engine, locale: prefs.locale,
                    whisperExecutable: prefs.whisperExecutable, whisperModel: prefs.whisperModel)
            }
            resultText = rawText
            refinementStatus = prefs.useCodex ? "等待 Codex 整理" : "转写原文 · 未启用 Codex 整理"
            dictationCharacters = UsageStatistics.characterCount(rawText)
            try Task.checkCancellation()
            saveCurrent(mode: writingMode, engine: prefs.engine)
            if prefs.useCodex { try await performRefinement(mode: writingMode, prefs: prefs) }
            else { notice = prefs.engine == "cloud" ? "已完成云端转写，文字未发送至 Codex。" : "已完成本机转写，文字未发送至 Codex。" }
            try await deliverResult(autoInsert: prefs.autoInsert)
        } catch {
            if isCodexTimeout(error), !rawText.isEmpty, prefs.codexTimeoutFallback ?? true {
                await deliverRawAfterCancellation(mode: writingMode, prefs: prefs)
                notice = "Codex 整理超过 20 秒，未完成优化，已使用转写原文。"
                return
            }
            if error is CancellationError, useRawOnCancellation, !rawText.isEmpty {
                await deliverRawAfterCancellation(mode: writingMode, prefs: prefs)
                return
            }
            if error is CancellationError { notice = "已取消处理。" } else { self.error = error.localizedDescription }
            if rawText.isEmpty && !(error is CancellationError) {
                keepForRetry = true; retryAudio = audio; retryAudioOwned = removeAfter; canRetryAudio = true
                appleSetupRequired = (error as? LocalTranscriptionError)?.appleSetupRequired == true
                notice = "本段录音暂时保留，可直接重试；开始新录音、放弃或退出时删除。"
            }
            if !rawText.isEmpty { notice = "原始转写已保留，可以编辑或重试 Codex 整理。" }
        }
    }
    private func deliverResult(autoInsert: Bool) async throws {
        guard autoInsert, pendingInsertion else { return }
        try Task.checkCancellation()
        insertionAttempted = true
        phase = .inserting
        let inserted = try await insertion.insert(text: resultText)
        pendingInsertion = !inserted
        notice = inserted ? "已输入到 \(targetName) 的原输入框。" : insertion.failureReason
    }
    func retryTranscription(useWhisper: Bool) {
        guard !isBusy, let audio = retryAudio else { return }
        let owned = retryAudioOwned
        retryAudio = nil; retryAudioOwned = false; canRetryAudio = false
        if useWhisper { preferences.engine = "whisper" }
        error = ""; notice = ""; appleSetupRequired = false; phase = .transcribing
        activeTask = Task { [weak self] in await self?.process(audio: audio, removeAfter: owned) }
    }
    func discardRetryAudio() { clearRetryAudio(); notice = "已放弃本段录音。" }
    func retryInsertion() {
        guard !isBusy, !resultText.isEmpty else { return }
        error = ""
        if !insertion.hasTarget { insertion.captureTarget(); targetName = insertion.targetName ?? "原应用" }
        pendingInsertion = true
        phase = .inserting
        activeTask = Task {
            defer { phase = .idle }
            do { try await deliverResult(autoInsert: true) }
            catch { self.error = error.localizedDescription }
        }
    }
    func useRawImmediately() { useRawOnCancellation = true; activeTask?.cancel() }
    private func isCodexTimeout(_ error: Error) -> Bool {
        if let value = error as? CodexBridgeError, case .timeout = value { return true }
        return false
    }
    private func deliverRawAfterCancellation(mode: WritingMode, prefs: AppPreferences) async {
        useRawOnCancellation = false; resultText = rawText
        refinementStatus = "未完成整理 · 使用转写原文"
        saveCurrent(mode: mode, engine: prefs.engine)
        // The refinement task is cancelled. Use a fresh task for deliberate
        // raw-text insertion so cancellation cannot suppress the user's choice.
        let delivery = Task {
            phase = .inserting
            do { try await deliverResult(autoInsert: prefs.autoInsert) }
            catch { self.error = error.localizedDescription }
        }
        activeTask = delivery
        notice = "已跳过 Codex，使用转写原文。"
        // Keep the processing owner alive until the fresh, uncancelled delivery
        // finishes. Its idle cleanup must not hide the panel before paste ends.
        await delivery.value
    }
    private func clearRetryAudio() {
        if retryAudioOwned, let retryAudio { try? FileManager.default.removeItem(at: retryAudio) }
        retryAudio = nil; retryAudioOwned = false; canRetryAudio = false
    }
    func shutdown() { overlayDismissTask?.cancel(); hideOverlay(); activeTask?.cancel(); prewarmTask?.cancel(); codex.shutdown(); recorder.cancel(); clearRetryAudio() }
    func openDictationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Dictation")!)
    }
    func saveCloudKey(_ key: String) -> Bool {
        do {
            guard let account = cloudConfiguration.credentialAccount else { _ = try cloudConfiguration.endpoint(); return false }
            try CloudCredentialStore.save(key, account: account)
            cloudStatus = "API Key 已保存到钥匙串。可用示例音频测试当前接口。"; return true
        } catch { cloudStatus = error.localizedDescription; return false }
    }
    func removeCloudKey() {
        guard let account = cloudConfiguration.credentialAccount else { return }
        do { try CloudCredentialStore.delete(account: account); cloudStatus = "已删除当前地址保存的 API Key。" }
        catch { cloudStatus = error.localizedDescription }
    }
    func testCloudSpeech() {
        guard !isBusy, !cloudTestBusy else { return }
        let configuration = cloudConfiguration
        cloudTestBusy = true; cloudStatus = "正在发送约 5 秒的英文示例音频，最长等待 45 秒…"
        Task {
            defer { cloudTestBusy = false }
            let started = Date()
            do {
                guard let sample = Bundle.main.url(forResource: "speech-test", withExtension: "wav") else { throw CloudSpeechError("找不到内置测试音频，请使用打包后的 NoType.app。") }
                let endpoint = try configuration.endpoint()
                let key = try CloudCredentialStore.read(account: configuration.apiProtocol.rawValue + "|" + endpoint.absoluteString)
                let result = try await LocalTranscriber().transcribeCloud(audio: sample, configuration: configuration, apiKey: key, locale: "en-US")
                cloudStatus = String(format: "转写测试成功（%.1f 秒）：", Date().timeIntervalSince(started)) + result
            } catch { cloudStatus = error.localizedDescription }
        }
    }
    func refineText() {
        guard !isBusy else { return }
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { error = "请先录音、导入音频，或输入需要整理的文字。"; return }
        error = ""; notice = ""; let prefs = preferences; let writingMode = mode; phase = .refining
        activeTask = Task { [weak self] in
            guard let self else { return }
            defer { phase = .idle }
            do { try await performRefinement(mode: writingMode, prefs: prefs); try await deliverResult(autoInsert: prefs.autoInsert) }
            catch {
                if isCodexTimeout(error), prefs.codexTimeoutFallback ?? true {
                    await deliverRawAfterCancellation(mode: writingMode, prefs: prefs)
                    notice = "Codex 整理超过 20 秒，未完成优化，已使用转写原文。"
                }
                else if error is CancellationError, useRawOnCancellation { await deliverRawAfterCancellation(mode: writingMode, prefs: prefs) }
                else if error is CancellationError { notice = "已取消整理。" }
                else { self.error = error.localizedDescription }
            }
        }
    }
    private func performRefinement(mode: WritingMode, prefs: AppPreferences) async throws {
        prewarmTask?.cancel()
        phase = .refining
        refinementStatus = "Codex 正在整理…"
        defer {
            if refinementStatus == "Codex 正在整理…" { refinementStatus = "整理未完成 · 可重试" }
        }
        let instruction = mode.instruction + "\n用户附加的写作偏好：\n" + prefs.customInstruction
        let words = prefs.glossary.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let started = Date()
        let result = try await codex.refine(text: rawText, instruction: instruction, glossary: words,
            executable: prefs.codexExecutable, model: prefs.codexModel.isEmpty ? nil : prefs.codexModel,
            preferFast: prefs.codexPreferFast ?? true)
        try Task.checkCancellation()
        resultText = result.text
        refinementStatus = String(format: "已整理 · %@ · %.1f 秒", result.model, Date().timeIntervalSince(started))
        saveCurrent(mode: mode, engine: prefs.engine, model: result.model)
        notice = String(format: "Codex 整理完成 · %@ · %.1f 秒", result.model, Date().timeIntervalSince(started))
    }
    private func saveCurrent(mode: WritingMode, engine: String, model: String = "") {
        guard preferences.saveHistory, !historyNeedsRecovery else { return }
        let previous = records.first { $0.id == currentRecordID }
        let record = DictationRecord(id: currentRecordID ?? UUID(), createdAt: previous?.createdAt ?? Date(), rawText: rawText, text: resultText,
            mode: mode.title, engine: engine, model: model, duration: elapsed, appName: targetName,
            source: draftSource, dictationCharacters: dictationCharacters)
        currentRecordID = record.id
        if let index = records.firstIndex(where: { $0.id == record.id }) { records[index] = record }
        else { records.insert(record, at: 0) }
        persistHistory()
    }
    private func persistHistory() {
        guard !historyNeedsRecovery else { error = "历史文件存在读取错误，请先打开数据目录备份并修复 history.json。"; return }
        do { try store.save(records) } catch { self.error = "历史保存失败：\(error.localizedDescription)" }
    }
    func delete(_ id: UUID) { records.removeAll { $0.id == id }; persistHistory() }
    func clearHistory() { records = []; currentRecordID = nil; persistHistory() }
    func load(_ record: DictationRecord) {
        guard !isBusy else { return }
        clearRetryAudio(); pendingInsertion = false
        currentRecordID = record.id; rawText = record.rawText; resultText = record.text; elapsed = record.duration
        refinementStatus = record.model.isEmpty ? "无 Codex 整理记录" : "已整理 · " + record.model
        draftSource = record.source ?? (record.duration > 0 ? "recording" : "typed")
        dictationCharacters = record.dictationCharacters ?? UsageStatistics.characterCount(record.rawText)
        targetName = record.appName; section = "dictation"
    }
    func newDraft() { guard !isBusy else { return }; clearRetryAudio(); pendingInsertion = false; currentRecordID = nil; rawText = ""; resultText = ""; refinementStatus = ""; elapsed = 0; notice = ""; error = ""; appleSetupRequired = false; draftSource = "typed"; dictationCharacters = nil }
    func copyResult() { guard !resultText.isEmpty else { return }; InputInsertion.copy(resultText); notice = "已复制结果。" }
    func checkCodex() {
        guard !diagnosticBusy else { return }
        diagnosticBusy = true; diagnostic = "正在连接本机 Codex CLI…"
        Task {
            defer { diagnosticBusy = false }
            do {
                updateModels(try await codex.discoverModels(executable: preferences.codexExecutable, refresh: true))
                diagnostic = "已连接 · \(models.count) 个可用模型 · 音频转写使用本地引擎"
            } catch { diagnostic = "连接失败：\(error.localizedDescription)" }
        }
    }
    func checkApple() {
        let locale = preferences.locale == "auto" ? "zh-CN" : preferences.locale
        let supported = SFSpeechRecognizer(locale: Locale(identifier: locale))?.supportsOnDeviceRecognition == true
        let permission: String
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: permission = "已授权"
        case .denied: permission = "已拒绝，请到系统设置开启"
        case .restricted: permission = "系统限制"
        default: permission = "首次转写时需要授权"
        }
        appleDiagnostic = "\(locale)：\(supported ? "系统报告支持设备端识别" : "暂不支持设备端识别") · \(permission)"
    }
    func exportHistory() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "NoType-history.json"; panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(records).write(to: url, options: .atomic); notice = "历史记录已导出。"
        } catch { self.error = "导出失败：\(error.localizedDescription)" }
    }
    private func showOverlay() {
        guard floatingPanel == nil else { return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 236, height: 64),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.title = "NoType 语音状态"
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 236, height: 64))
        let hosting = TransparentHostingView(rootView: RecordingOverlay(state: self, recorder: recorder))
        let bounds = NSRect(x: 14, y: 14, width: 208, height: 36)
        hosting.frame = NSRect(origin: .zero, size: bounds.size)
        hosting.autoresizingMask = [.width, .height]
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: bounds)
            glass.style = .clear
            glass.tintColor = nil // No white/blue fill layered over Clear Glass.
            glass.cornerRadius = 18
            glass.contentView = hosting
            root.addSubview(glass)
        } else {
            let material = NSVisualEffectView(frame: bounds)
            material.material = .hudWindow
            material.blendingMode = .behindWindow
            material.state = .active
            material.wantsLayer = true
            material.layer?.cornerRadius = 18
            material.layer?.masksToBounds = true
            hosting.frame = material.bounds
            hosting.autoresizingMask = [.width, .height]
            material.addSubview(hosting)
            root.addSubview(material)
        }
        panel.contentView = root
        if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - 118, y: screen.visibleFrame.minY + 36))
        }
        panel.orderFrontRegardless(); floatingPanel = panel
    }
    private func updateOverlay(from previous: WorkPhase) {
        overlayDismissTask?.cancel(); overlayDismissTask = nil
        guard phase == .idle else {
            if previous == .idle { insertionAttempted = false }
            overlayMessage = ""
            if phase == .recording || phase == .preparing { processingStartedAt = nil }
            else if previous == .recording || processingStartedAt == nil { processingStartedAt = Date() }
            showOverlay()
            return
        }
        processingStartedAt = nil
        guard floatingPanel != nil else { return }
        if !error.isEmpty { overlayMessage = "处理未完成，点击查看详情" }
        else if !resultText.isEmpty, !insertionAttempted || pendingInsertion {
            overlayMessage = insertionAttempted ? "文字已复制，未自动输入" : "文字已保留，点击查看"
        }
        else { hideOverlay(); return }
        overlayDismissTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 4_000_000_000) } catch { return }
            guard let self, phase == .idle else { return }
            hideOverlay(); overlayMessage = ""
        }
    }
    func openOverlayResult() {
        section = "dictation"
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" || $0.title == "NoType" }) {
            window.makeKeyAndOrderFront(nil)
        }
        overlayDismissTask?.cancel(); hideOverlay()
    }
    private func hideOverlay() { floatingPanel?.orderOut(nil); floatingPanel = nil }
}
