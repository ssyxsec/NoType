import Foundation
import Speech
import AVFoundation
import NoTypeCore

struct LocalTranscriptionError: LocalizedError {
    let message: String
    var appleSetupRequired = false
    var errorDescription: String? { message }
}

@MainActor
final class LocalTranscriber {
    func transcribeCloud(audio: URL, configuration: CloudSpeechConfiguration, apiKey: String, locale: String) async throws -> String {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("NoType-cloud-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("audio.wav")
        let conversion = Process()
        conversion.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        conversion.arguments = ["-f", "WAVE", "-d", "LEI16@16000", "-c", "1", audio.path, output.path]
        conversion.standardInput = FileHandle.nullDevice; conversion.standardOutput = FileHandle.nullDevice; conversion.standardError = FileHandle.nullDevice
        let operation = WhisperProcessOperation(process: conversion, timeoutSeconds: 15)
        let status = try await withTaskCancellationHandler { try await operation.run() } onCancel: { Task { @MainActor in operation.cancel() } }
        guard status == 0 else { throw CloudSpeechError("无法将录音转换为云端转写支持的 WAV 文件，原始音频已保留。") }
        try Task.checkCancellation()
        let size = try FileManager.default.attributesOfItem(atPath: output.path)[.size] as? NSNumber
        guard (size?.intValue ?? 0) <= 25 * 1024 * 1024 else { throw CloudSpeechError("云端上传音频不能超过 25 MiB，请缩短录音。") }
        return try await CloudSpeechClient().transcribe(audio: Data(contentsOf: output), configuration: configuration, apiKey: apiKey, language: locale)
    }
    func transcribe(audio: URL, engine: String, locale: String,
                    whisperExecutable: String, whisperModel: String) async throws -> String {
        try Task.checkCancellation()
        guard FileManager.default.fileExists(atPath: audio.path) else {
            throw LocalTranscriptionError(message: "找不到录音文件。")
        }
        switch engine {
        case "apple": return try await transcribeApple(audio: audio, locale: locale)
        case "whisper": return try await transcribeWhisper(audio: audio, locale: locale, executable: whisperExecutable, model: whisperModel)
        default: throw LocalTranscriptionError(message: "未知的本地语音引擎：\(engine)")
        }
    }

    private func transcribeApple(audio: URL, locale: String) async throws -> String {
        let authorization = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        try Task.checkCancellation()
        guard authorization == .authorized else {
            throw LocalTranscriptionError(message: "未获得语音识别权限。请在系统设置 → 隐私与安全性 → 语音识别中允许 NoType。")
        }
        let identifier = locale == "auto" ? Locale.current.identifier : locale
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: identifier)),
              recognizer.supportsOnDeviceRecognition else {
            throw LocalTranscriptionError(message: "系统尚不支持此语言的离线识别。请在系统设置中启用或下载对应听写语言，或选择已安装的 whisper.cpp。NoType 不会回退到云端识别。")
        }
        let request = SFSpeechURLRecognitionRequest(url: audio)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        let operation = AppleRecognitionOperation()
        return try await withTaskCancellationHandler {
            try await operation.run(recognizer: recognizer, request: request)
        } onCancel: {
            Task { @MainActor in operation.cancel() }
        }
    }

    private func transcribeWhisper(audio: URL, locale: String, executable: String, model: String) async throws -> String {
        let executableURL = URL(fileURLWithPath: NSString(string: executable).expandingTildeInPath)
        let modelURL = URL(fileURLWithPath: NSString(string: model).expandingTildeInPath)
        guard !executable.isEmpty, executable.hasPrefix("/") || executable.hasPrefix("~/"),
              FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw LocalTranscriptionError(message: "请在设置中填写已安装 whisper-cli 的绝对路径。NoType 不会自动安装或下载引擎。")
        }
        guard !model.isEmpty, FileManager.default.isReadableFile(atPath: modelURL.path) else {
            throw LocalTranscriptionError(message: "请先选择本机的 whisper.cpp 模型文件。")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("NoType-whisper-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stem = directory.appendingPathComponent("transcript")
        let logURL = directory.appendingPathComponent("process.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: logURL)
        defer { try? log.close() }
        // afconvert is Apple's bundled decoder. Convert only into our private temporary
        // directory; the original WAV/MP3/M4A/AIFF or other supported import is untouched.
        let converted = directory.appendingPathComponent("input.wav")
        let conversion = Process()
        conversion.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        conversion.arguments = ["-f", "WAVE", "-d", "LEI16@16000", "-c", "1", audio.path, converted.path]
        conversion.standardInput = FileHandle.nullDevice
        conversion.standardOutput = log
        conversion.standardError = log
        let converter = WhisperProcessOperation(process: conversion)
        let conversionStatus = try await withTaskCancellationHandler {
            try await converter.run()
        } onCancel: {
            Task { @MainActor in converter.cancel() }
        }
        guard conversionStatus == 0 else {
            throw LocalTranscriptionError(message: "无法解码此音频（退出码 \(conversionStatus)）。请使用系统支持的 WAV、MP3、M4A 或 AIFF 文件。原文件未修改。")
        }
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = executableURL
        let language = locale == "auto" ? "auto" : String(locale.replacingOccurrences(of: "_", with: "-").split(separator: "-").first ?? "auto")
        process.arguments = ["-m", modelURL.path, "-f", converted.path, "-l", language, "-otxt", "-of", stem.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = log
        process.standardError = log
        let operation = WhisperProcessOperation(process: process)
        let status = try await withTaskCancellationHandler {
            try await operation.run()
        } onCancel: {
            Task { @MainActor in operation.cancel() }
        }
        guard status == 0 else {
            throw LocalTranscriptionError(message: "whisper.cpp 识别失败（退出码 \(status)）。请检查模型和引擎版本是否匹配。")
        }
        let result = try String(contentsOf: stem.appendingPathExtension("txt"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw LocalTranscriptionError(message: "未识别到语音，请检查麦克风或音频文件。") }
        return result
    }
}

@MainActor
private final class AppleRecognitionOperation {
    private var continuation: CheckedContinuation<String, Error>?
    private var task: SFSpeechRecognitionTask?
    private var timeout: Task<Void, Never>?
    private var cancelled = false

    func run(recognizer: SFSpeechRecognizer, request: SFSpeechURLRecognitionRequest) async throws -> String {
        if cancelled { throw CancellationError() }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result, result.isFinal {
                        let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                        self.finish(text.isEmpty ? .failure(LocalTranscriptionError(message: "未识别到语音。")) : .success(text))
                    } else if let error {
                        if SpeechFailure.dictationDisabled(error) {
                            self.finish(.failure(LocalTranscriptionError(message: "Apple 语音识别不可用：系统的 Siri 与听写已关闭。请打开“系统设置 → 键盘 → 听写”，开启听写并选择对应语言，然后重试。也可直接使用 Whisper 重试这段录音。", appleSetupRequired: true)))
                        } else {
                            self.finish(.failure(LocalTranscriptionError(message: "Apple 语音识别失败：\(error.localizedDescription)。可保留本段录音并使用 Whisper 重试。")))
                        }
                    }
                }
            }
            timeout = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 120_000_000_000) } catch { return }
                self?.finish(.failure(LocalTranscriptionError(message: "本地识别超时，请尝试较短的录音。")))
            }
        }
    }

    func cancel() { cancelled = true; finish(.failure(CancellationError())) }
    private func finish(_ result: Result<String, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        timeout = nil
        task?.cancel()
        task = nil
        continuation.resume(with: result)
    }
}

@MainActor
private final class WhisperProcessOperation {
    private let process: Process
    private var continuation: CheckedContinuation<Int32, Error>?
    private var timeout: Task<Void, Never>?
    private var failure: Error?
    private var cancelled = false

    private let timeoutSeconds: UInt64
    init(process: Process, timeoutSeconds: UInt64 = 300) { self.process = process; self.timeoutSeconds = timeoutSeconds }
    func run() async throws -> Int32 {
        if cancelled { throw CancellationError() }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            process.terminationHandler = { [weak self] process in
                Task { @MainActor in self?.finished(status: process.terminationStatus) }
            }
            do { try process.run() } catch {
                self.continuation = nil
                continuation.resume(throwing: LocalTranscriptionError(message: "无法启动 whisper-cli：\(error.localizedDescription)"))
                return
            }
            timeout = Task { [weak self] in
                guard let self else { return }
                do { try await Task.sleep(nanoseconds: self.timeoutSeconds * 1_000_000_000) } catch { return }
                self.terminate(with: LocalTranscriptionError(message: "音频处理超时（\(self.timeoutSeconds) 秒），已停止进程。"))
            }
        }
    }
    func cancel() { cancelled = true; terminate(with: CancellationError()) }
    private func terminate(with error: Error) {
        guard continuation != nil else { return }
        failure = error
        if process.isRunning {
            process.terminate()
            let pid = process.processIdentifier
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if let self, self.process.isRunning { kill(pid, SIGKILL) }
            }
        } else { finished(status: -1) }
    }
    private func finished(status: Int32) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        timeout = nil
        process.terminationHandler = nil
        if let failure { continuation.resume(throwing: failure) }
        else { continuation.resume(returning: status) }
    }
}
