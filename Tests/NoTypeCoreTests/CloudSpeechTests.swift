import XCTest
@testable import NoTypeCore

final class CloudSpeechTests: XCTestCase {
    func testQwenRequestEmbedsAudioAndUsesCorrectRoute() throws {
        let config = CloudSpeechConfiguration()
        let audio = Data("RIFF-test-audio".utf8)
        let request = try CloudSpeechClient.request(audio: audio, configuration: config, apiKey: "test-key", language: "zh-CN")
        XCTAssertEqual(request.url?.absoluteString, "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "qwen3-asr-flash")
        XCTAssertEqual(body["stream"] as? Bool, false)
        XCTAssertEqual((body["asr_options"] as? [String: Any])?["language"] as? String, "zh")
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
        let data = try XCTUnwrap((content.first?["input_audio"] as? [String: Any])?["data"] as? String)
        XCTAssertEqual(data, "data:audio/wav;base64," + audio.base64EncodedString())
        XCTAssertFalse(String(decoding: request.httpBody!, as: UTF8.self).contains("test-key"))
    }
    func testGenericMultipartAndAutomaticLanguage() throws {
        var config = CloudSpeechConfiguration(); config.apiProtocol = .multipart
        config.baseURL = "https://speech.example/v1"; config.model = "custom-asr"
        let request = try CloudSpeechClient.request(audio: Data([1, 2, 3]), configuration: config, apiKey: "fake", language: "auto")
        XCTAssertEqual(request.url?.path, "/v1/audio/transcriptions")
        let body = String(decoding: request.httpBody!, as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"model\"\r\n\r\ncustom-asr"))
        XCTAssertTrue(body.contains("filename=\"recording.wav\""))
        XCTAssertFalse(body.contains("name=\"language\""))
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")!.hasPrefix("multipart/form-data; boundary="))
    }
    func testValidationPreventsSendingToInsecureOrCredentialURLs() throws {
        for address in ["http://speech.example/v1", "https://key:secret@speech.example/v1", "https://speech.example/v1?key=secret", "not-a-url"] {
            var config = CloudSpeechConfiguration(); config.baseURL = address
            XCTAssertThrowsError(try config.endpoint())
        }
        let config = CloudSpeechConfiguration()
        XCTAssertThrowsError(try CloudSpeechClient.request(audio: Data([1]), configuration: config, apiKey: "", language: "auto"))
        XCTAssertThrowsError(try CloudSpeechClient.request(audio: Data(), configuration: config, apiKey: "fake", language: "auto"))
        var filetrans = config; filetrans.model = "qwen3-asr-flash-filetrans"
        XCTAssertThrowsError(try CloudSpeechClient.request(audio: Data([1]), configuration: filetrans, apiKey: "fake", language: "auto"))
    }
    func testFullEndpointAndCredentialsAreBoundToDestination() throws {
        var config = CloudSpeechConfiguration()
        let initial = config.credentialAccount
        config.baseURL += "/chat/completions"
        XCTAssertEqual(config.credentialAccount, initial)
        XCTAssertEqual(try config.endpoint().path, "/compatible-mode/v1/chat/completions")
        config.baseURL = "https://speech.example/v1"
        XCTAssertNotEqual(config.credentialAccount, initial)
        let encoded = String(decoding: try JSONEncoder().encode(config), as: UTF8.self)
        XCTAssertFalse(encoded.contains("apiKey"))
    }
    func testParsesBothProtocolsAndRejectsEmptyOrMalformedResults() throws {
        XCTAssertEqual(try CloudSpeechClient.parse(data: Data(#"{"choices":[{"message":{"content":"你好，NoType。"}}]}"#.utf8), status: 200, apiProtocol: .qwen), "你好，NoType。")
        XCTAssertEqual(try CloudSpeechClient.parse(data: Data(#"{"text":"hello"}"#.utf8), status: 200, apiProtocol: .multipart), "hello")
        XCTAssertThrowsError(try CloudSpeechClient.parse(data: Data(#"{"text":""}"#.utf8), status: 200, apiProtocol: .multipart))
        XCTAssertThrowsError(try CloudSpeechClient.parse(data: Data("<html>error</html>".utf8), status: 200, apiProtocol: .qwen))
        for status in [302, 400, 401, 403, 413, 429, 500] {
            do { _ = try CloudSpeechClient.parse(data: Data("private-key-echo".utf8), status: status, apiProtocol: .qwen); XCTFail() }
            catch { XCTAssertFalse(error.localizedDescription.contains("private-key-echo")) }
        }
    }
    func testClientRoundTripUsesInjectedTransportWithoutPublicNetwork() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockSpeechProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let result = try await CloudSpeechClient().transcribe(audio: Data([1]), configuration: CloudSpeechConfiguration(), apiKey: "test-only", language: "auto", session: session)
        XCTAssertEqual(result, "测试成功")
    }
    func testTransportTimeoutHasActionableMessage() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TimeoutSpeechProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        do {
            _ = try await CloudSpeechClient().transcribe(audio: Data([1]), configuration: CloudSpeechConfiguration(), apiKey: "test-only", language: "auto", session: session)
            XCTFail("Expected timeout")
        } catch { XCTAssertTrue(error.localizedDescription.contains("超时")) }
    }
    func testCancellationDoesNotPublishAnEmptySuccess() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PendingSpeechProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let task = Task { try await CloudSpeechClient().transcribe(audio: Data([1]), configuration: CloudSpeechConfiguration(), apiKey: "test-only", language: "auto", session: session) }
        try await Task.sleep(nanoseconds: 30_000_000)
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
    func testTotalDeadlineStopsAConnectionThatNeverCompletes() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PendingSpeechProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let started = Date()
        do {
            _ = try await CloudSpeechClient(timeout: 0.05).transcribe(audio: Data([1]), configuration: CloudSpeechConfiguration(), apiKey: "test-only", language: "auto", session: session)
            XCTFail("Expected deadline")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("已停止等待"))
            XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        }
    }
}

private final class TimeoutSpeechProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.timedOut)) }
    override func stopLoading() {}
}
private final class PendingSpeechProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {}
    override func stopLoading() {}
}

private final class MockSpeechProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"choices":[{"message":{"content":"测试成功"}}]}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
