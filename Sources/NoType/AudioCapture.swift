import AVFoundation
import Combine
import Foundation

enum AudioCaptureError: LocalizedError {
    case denied, alreadyRecording, failed
    var errorDescription: String? {
        switch self {
        case .denied: return "未获得麦克风权限。请在系统设置 → 隐私与安全性 → 麦克风中允许 NoType。"
        case .alreadyRecording: return "正在录音，请先停止当前录音。"
        case .failed: return "无法开始录音，请检查麦克风是否可用。"
        }
    }
}

@MainActor
final class AudioCapture: ObservableObject {
    @Published var level: Double = 0
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var requesting = false

    func start() async throws -> URL {
        guard recorder == nil, !requesting else { throw AudioCaptureError.alreadyRecording }
        requesting = true
        defer { requesting = false }
        let allowed = await AVCaptureDevice.requestAccess(for: .audio)
        guard allowed else { throw AudioCaptureError.denied }
        try Task.checkCancellation()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("NoType-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let newRecorder = try AVAudioRecorder(url: url, settings: settings)
        newRecorder.isMeteringEnabled = true
        guard newRecorder.prepareToRecord(), newRecorder.record() else {
            try? FileManager.default.removeItem(at: url)
            throw AudioCaptureError.failed
        }
        recorder = newRecorder
        timer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let recorder = self.recorder else { return }
                recorder.updateMeters()
                self.level = min(1, max(0, pow(10, Double(recorder.averagePower(forChannel: 0)) / 30)))
            }
        }
        return url
    }

    func stop() -> URL? {
        timer?.invalidate()
        timer = nil
        let url = recorder?.url
        recorder?.stop()
        recorder = nil
        level = 0
        return url
    }

    func cancel() {
        if let url = stop() { try? FileManager.default.removeItem(at: url) }
    }
}
