import Foundation

public enum SpeechAPIProtocol: String, Codable, CaseIterable, Sendable {
    case qwen, multipart
}

public struct CloudSpeechConfiguration: Codable, Equatable, Sendable {
    public var apiProtocol: SpeechAPIProtocol = .qwen
    public var baseURL = "https://dashscope.aliyuncs.com/compatible-mode/v1"
    public var model = "qwen3-asr-flash"
    public init() {}
    public func endpoint() throws -> URL {
        let address = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: address),
              url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw CloudSpeechError("请填写有效的 HTTPS API 地址，不要在地址中填写 Key、查询参数或账号密码。")
        }
        let suffix = apiProtocol == .qwen ? "/chat/completions" : "/audio/transcriptions"
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if ("/" + path).hasSuffix(suffix) { return url }
        return url.appendingPathComponent(String(suffix.dropFirst()))
    }
    public var credentialAccount: String? { try? apiProtocol.rawValue + "|" + endpoint().absoluteString }
}

public struct CloudSpeechError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public final class CloudSpeechClient: Sendable {
    private let timeout: TimeInterval
    public init(timeout: TimeInterval = 45) { self.timeout = max(0.01, timeout) }
    public func transcribe(audio: Data, configuration: CloudSpeechConfiguration, apiKey: String,
                           language: String, session: URLSession? = nil) async throws -> String {
        let request = try Self.request(audio: audio, configuration: configuration, apiKey: apiKey, language: language)
        let transport = URLSessionConfiguration.ephemeral
        transport.timeoutIntervalForRequest = timeout
        transport.timeoutIntervalForResource = timeout
        let activeSession = session ?? URLSession(configuration: transport, delegate: NoSpeechRedirects(), delegateQueue: nil)
        defer { if session == nil { activeSession.invalidateAndCancel() } }
        do {
            // A total deadline also covers a server that keeps the connection alive
            // without ever completing its response. Cancellation stops the upload.
            let (data, response) = try await withThrowingTaskGroup(of: (Data, URLResponse).self) { group in
                group.addTask { try await activeSession.data(for: request) }
                group.addTask { [timeout] in
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    throw CloudSpeechError("云端语音识别超过 \(Int(timeout)) 秒，已停止等待。本段录音已保留，可重试或改用 Whisper。")
                }
                defer { group.cancelAll() }
                return try await group.next()!
            }
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw CloudSpeechError("语音服务未返回有效 HTTP 响应。") }
            return try Self.parse(data: data, status: http.statusCode, apiProtocol: configuration.apiProtocol)
        } catch is CancellationError { throw CancellationError() }
        catch let error as CloudSpeechError { throw error }
        catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            if error.code == .timedOut { throw CloudSpeechError("云端语音识别超时，录音已保留，可重试或改用 Whisper。") }
            throw CloudSpeechError("无法连接语音服务，请检查网络与 API 地址（网络错误 \(error.code.rawValue)）。")
        }
    }
    public static func request(audio: Data, configuration: CloudSpeechConfiguration, apiKey: String, language: String) throws -> URLRequest {
        let endpoint = try configuration.endpoint()
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.contains(where: { $0.isNewline }) else { throw CloudSpeechError("请先在云端语音设置中保存有效的 API Key。") }
        let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty, !model.contains(where: { $0.isNewline }) else { throw CloudSpeechError("请填写有效的语音识别模型名称。") }
        guard !audio.isEmpty, audio.count <= 25 * 1024 * 1024 else { throw CloudSpeechError("云端上传音频须为非空且不超过 25 MiB；服务商可能有更小的时长或大小限制。") }
        var request = URLRequest(url: endpoint, timeoutInterval: 45)
        request.httpMethod = "POST"
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let lang = language == "auto" ? nil : language.replacingOccurrences(of: "_", with: "-").split(separator: "-").first.map(String.init)
        if configuration.apiProtocol == .qwen {
            guard !model.contains("filetrans") else { throw CloudSpeechError("此协议用于 qwen3-asr-flash 系列，不能使用需要公网文件 URL 和异步轮询的 filetrans 模型。") }
            var options: [String: Any] = ["enable_itn": true]
            if let lang { options["language"] = lang }
            let body: [String: Any] = ["model": model, "stream": false, "asr_options": options,
                "messages": [["role": "user", "content": [["type": "input_audio", "input_audio": ["data": "data:audio/wav;base64," + audio.base64EncodedString()]]]]]]
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } else {
            let boundary = "NoType-" + UUID().uuidString
            var body = Data()
            func append(_ text: String) { body.append(Data(text.utf8)) }
            func field(_ name: String, _ value: String) {
                append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
            }
            field("model", model); field("response_format", "json")
            if let lang { field("language", lang) }
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"recording.wav\"\r\nContent-Type: audio/wav\r\n\r\n")
            body.append(audio); append("\r\n--\(boundary)--\r\n")
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        return request
    }
    public static func parse(data: Data, status: Int, apiProtocol: SpeechAPIProtocol) throws -> String {
        // Never echo raw server bodies: errors can contain echoed keys or audio.
        guard (200..<300).contains(status) else {
            switch status {
            case 401, 403: throw CloudSpeechError("语音 API 鉴权失败（\(status)）：请检查 Key、地域与模型权限。")
            case 429: throw CloudSpeechError("语音服务限流或余额不足（429），请检查服务商额度后重试。")
            case 400, 404, 413, 422: throw CloudSpeechError("语音请求被拒绝（\(status)）：请检查协议、地址、模型及服务商的音频大小/时长限制。")
            case 300..<400: throw CloudSpeechError("语音 API 返回重定向，未转发音频与 Key。请填写最终 HTTPS 接口地址。")
            default: throw CloudSpeechError("语音服务错误（HTTP \(status)），请稍后重试。")
            }
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CloudSpeechError("语音 API 返回的内容不是有效 JSON。") }
        var text: String?
        if apiProtocol == .multipart { text = object["text"] as? String }
        else if let choices = object["choices"] as? [[String: Any]], let message = choices.first?["message"] as? [String: Any] {
            text = message["content"] as? String
            if text == nil, let blocks = message["content"] as? [[String: Any]] { text = blocks.compactMap { $0["text"] as? String }.joined(separator: "\n") }
        }
        guard let result = text?.trimmingCharacters(in: .whitespacesAndNewlines), !result.isEmpty else { throw CloudSpeechError("语音 API 没有返回转写文字，请检查接口协议与模型是否匹配。") }
        return result
    }
}

private final class NoSpeechRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
