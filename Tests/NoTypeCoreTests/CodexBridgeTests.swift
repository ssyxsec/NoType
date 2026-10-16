import XCTest
@testable import NoTypeCore

final class CodexBridgeTests: XCTestCase {
    func testShortTextRecommendationUsesAvailableTextModels() {
        func model(_ name: String, _ modalities: [String] = ["text"], default isDefault: Bool = false) -> CodexModel {
            CodexModel(id: name, model: name, displayName: name, inputModalities: modalities, isDefault: isDefault)
        }
        let models = [model("sol", default: true), model("mini"), model("luna")]
        XCTAssertEqual(CodexModel.recommendedForShortText(in: models)?.model, "luna")
        XCTAssertEqual(CodexModel.recommendedForShortText(in: [model("luna", ["audio"]), models[0]])?.model, "sol")
        XCTAssertNil(CodexModel.recommendedForShortText(in: []))
    }
    func testExplicitCatalogRefreshBypassesCache() async throws {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: log) }
        let tracked = server.replacingOccurrences(of: "*'\"method\":\"model/list\"'*)", with: "*'\"method\":\"model/list\"'*) echo listed >> '" + log.path + "';")
        let executable = try mockCLI(tracked)
        let bridge = CodexBridge(timeout: 5)
        defer { bridge.shutdown() }
        _ = try await bridge.discoverModels(executable: executable.path)
        _ = try await bridge.discoverModels(executable: executable.path)
        _ = try await bridge.discoverModels(executable: executable.path, refresh: true)
        XCTAssertEqual(try String(contentsOf: log).split(separator: "\n").count, 2)
    }
    private func mockCLI(_ body: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("codex")
        try ("#!/bin/zsh\n" + body).write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return executable
    }
    private var server: String {
        """
        while IFS= read -r line; do
          [[ $line =~ '"id":([0-9]+)' ]]
          rpcid=$match[1]
          case "$line" in
            *'"method":"initialize"'*) echo '{"id":'"$rpcid"',"result":{}}' ;;
            *'"method":"account/read"'*) echo '{"id":'"$rpcid"',"result":{"account":{"type":"chatgpt","email":null,"planType":"plus"},"requiresOpenaiAuth":true}}' ;;
            *'"method":"model/list"'*) echo '{"id":'"$rpcid"',"result":{"data":[{"id":"available","model":"available","displayName":"Available","inputModalities":["text","image"],"isDefault":true}],"nextCursor":null}}' ;;
            *'"method":"mcpServerStatus/list"'*) echo '{"id":'"$rpcid"',"result":{"data":[],"nextCursor":null}}' ;;
            *'"method":"thread/start"'*) echo '{"id":'"$rpcid"',"result":{"thread":{"id":"thread"}}}' ;;
            *'"method":"turn/start"'*)
              echo '{"id":'"$rpcid"',"result":{"turn":{"id":"turn"}}}'
              echo '{"method":"item/completed","params":{"threadId":"thread","turnId":"turn","item":{"type":"agentMessage","id":"message","text":"整理后的文字。"}}}'
              echo '{"method":"turn/completed","params":{"threadId":"thread","turn":{"id":"turn","status":"completed","items":[]}}}' ;;
          esac
        done
        """
    }
    func testCatalogAndTextRefinement() async throws {
        let executable = try mockCLI(server)
        let bridge = CodexBridge(timeout: 5)
        let models = try await bridge.discoverModels(executable: executable.path)
        XCTAssertEqual(models.map(\.model), ["available"])
        XCTAssertFalse(models[0].supportsAudio)
        let result = try await bridge.refine(text: "原始文字", instruction: "整理", glossary: [], executable: executable.path, model: nil)
        XCTAssertEqual(result.text, "整理后的文字。")
        XCTAssertEqual(result.model, "available")
    }
    func testWarmConnectionReusedAcrossIndependentRefinements() async throws {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: log) }
        let executable = try mockCLI("echo started >> '" + log.path + "'\n" + server)
        let bridge = CodexBridge(timeout: 5)
        defer { bridge.shutdown() }
        _ = try await bridge.discoverModels(executable: executable.path)
        for _ in 0..<2 { _ = try await bridge.refine(text: "test", instruction: "", glossary: [], executable: executable.path, model: nil) }
        XCTAssertEqual(try String(contentsOf: log).split(separator: "\n").count, 1)
    }
    func testCancelledWarmTurnReconnectsForNextCall() async throws {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: log) }
        let blocking = server.replacingOccurrences(of: "echo '{\"id\":'\"$rpcid\"',\"result\":{\"turn\":{\"id\":\"turn\"}}}'", with: "sleep 20")
        let executable = try mockCLI("echo started >> '" + log.path + "'\n" + blocking)
        let bridge = CodexBridge(timeout: 5)
        defer { bridge.shutdown() }
        _ = try await bridge.discoverModels(executable: executable.path)
        let task = Task { try await bridge.refine(text: "test", instruction: "", glossary: [], executable: executable.path, model: nil) }
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        do { _ = try await task.value; XCTFail() } catch is CancellationError {}
        _ = try await bridge.discoverModels(executable: executable.path)
        XCTAssertEqual(try String(contentsOf: log).split(separator: "\n").count, 2)
    }
    func testAudioRejectedBeforeSubmittingTurn() async throws {
        let executable = try mockCLI(server)
        do {
            _ = try await CodexBridge(timeout: 5).transcribe(audio: URL(fileURLWithPath: "/tmp/example.wav"), executable: executable.path)
            XCTFail("Text/image catalog must never be treated as audio support")
        } catch CodexBridgeError.unsupportedAudio { }
    }
    func testInvalidSelectedModelIsNotSilentlyReplaced() async throws {
        let executable = try mockCLI(server)
        do {
            _ = try await CodexBridge(timeout: 5).refine(text: "test", instruction: "", glossary: [], executable: executable.path, model: "missing")
            XCTFail("An explicit invalid model must be reported")
        } catch CodexBridgeError.unavailableModel(let model) { XCTAssertEqual(model, "missing") }
    }
    func testHungProcessTimesOut() async throws {
        let executable = try mockCLI("read line\nsleep 20\n")
        let start = Date()
        do {
            _ = try await CodexBridge(timeout: 0.2).discoverModels(executable: executable.path)
            XCTFail("Expected deadline")
        } catch CodexBridgeError.timeout { }
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }
    func testCancellationStopsWaitingForHungCLI() async throws {
        let executable = try mockCLI("read line\nsleep 20\n")
        let task = Task { try await CodexBridge(timeout: 30).discoverModels(executable: executable.path) }
        try await Task.sleep(nanoseconds: 100_000_000)
        let start = Date()
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError { }
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }
    func testFailedTurnDoesNotReturnPartialOutputAsSuccess() async throws {
        let executable = try mockCLI(server.replacingOccurrences(of: "\"status\":\"completed\"", with: "\"status\":\"failed\""))
        do {
            _ = try await CodexBridge(timeout: 5).refine(text: "test", instruction: "", glossary: [], executable: executable.path, model: nil)
            XCTFail("A failed turn must never return partial text as success")
        } catch CodexBridgeError.protocolFailure { }
    }

    func testBlankInputRejectedWithoutLaunchingCLI() async throws {
        do {
            _ = try await CodexBridge().refine(text: " \n ", instruction: "", glossary: [], executable: "/does/not/exist", model: nil)
            XCTFail("Expected empty input error before process launch")
        } catch CodexBridgeError.emptyInput { }
    }
    func testCommentaryIsNotIncludedInFinalText() async throws {
        let commentary = "echo '{\"method\":\"item/completed\",\"params\":{\"threadId\":\"thread\",\"turnId\":\"turn\",\"item\":{\"type\":\"agentMessage\",\"id\":\"commentary\",\"phase\":\"commentary\",\"text\":\"Working on it\"}}}'\n"
        let executable = try mockCLI(server.replacingOccurrences(of: "              echo '{\"method\":\"item/completed\"", with: "              " + commentary + "              echo '{\"method\":\"item/completed\""))
        let result = try await CodexBridge(timeout: 5).refine(text: "test", instruction: "", glossary: [], executable: executable.path, model: nil)
        XCTAssertEqual(result.text, "整理后的文字。")
    }
    func testMCPToolsFailClosedBeforeSendingTranscript() async throws {
        let inventory = "\"data\":[],\"nextCursor\":null"
        let exposed = "\"data\":[{\"name\":\"unexpected\",\"tools\":{\"send_email\":{}}}],\"nextCursor\":null"
        let executable = try mockCLI(server.replacingOccurrences(of: inventory, with: exposed))
        do {
            _ = try await CodexBridge(timeout: 5).refine(text: "private text", instruction: "", glossary: [], executable: executable.path, model: nil)
            XCTFail("Expected MCP isolation failure")
        } catch CodexBridgeError.protocolFailure(let reason) { XCTAssertTrue(reason.contains("MCP")) }
    }

    func testAPIKeyAuthenticationRejectedBeforeAnyModelRequest() async throws {
        let executable = try mockCLI(server.replacingOccurrences(of: "\"type\":\"chatgpt\"", with: "\"type\":\"apiKey\""))
        do {
            _ = try await CodexBridge(timeout: 5).discoverModels(executable: executable.path)
            XCTFail("NoType must not silently use separately billed API authentication")
        } catch CodexBridgeError.subscriptionRequired { }
    }

}
