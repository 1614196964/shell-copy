import Foundation
import XCTest
@testable import ShellCopyCore

final class SystemOneNormalizerTests: XCTestCase {
    func testListWrapsJoinLocallyInBothCloudModesWithoutSendingText() async throws {
        let first = "  • **KR3：**建立创编与 Oncall 场景的效果评测和发布回归机制，沉淀不少于 50 条真实需求及历史失败用例，覆盖正确性、任务完成率和执行耗时，核心 Skill 与"
        let next = "模型配置变更均完成回归验收。"
        for provider in CloudProvider.allCases {
            let session = makeSession { _ in
                XCTFail("Recognized list wraps should be resolved locally")
                throw URLError(.badURL)
            }
            defer { session.invalidateAndCancel() }
            let result = try await SystemOneNormalizer(provider: provider, session: session)
                .normalize("O3：技术优化\n\n" + first + "\n\t\t    " + next, apiKey: "synthetic-key")
            XCTAssertEqual(result, "O3：技术优化\n\n" + first + next)
        }
    }

    func testReportedLongParagraphJoinsLocallyBeforeAnUncertainCloudJudgment() async throws {
        let first = "密钥已导入应用钥匙串，处理方式已设为 bjev，48 项回归测试通过，新版也已打包。原来的自动合行设置"
        let second = "仍然开启，本地兜底默认开启。当前旧进程还在运行，需要重新打开新版，才能加载新菜单和配置。"
        for provider in CloudProvider.allCases {
            let session = makeSession { _ in
                XCTFail("A wrap covered by the local rules must not need a cloud judgment")
                return (200, try JSONSerialization.data(withJSONObject: [
                    "model": provider.model,
                    "answers": ["join_1": ["type": "noul", "noul": 0.6753]]
                ]))
            }
            defer { session.invalidateAndCancel() }
            let result = try await SystemOneNormalizer(provider: provider, session: session)
                .normalize(first + "\n  " + second, apiKey: "synthetic-key")
            XCTAssertEqual(result, first + second)
        }
    }

    func testCloudStillJudgesRemainingBoundariesAfterLocalJoins() async throws {
        let first = "This detailed garden journal explains how the new flowers started to"
        let localBlock = first + "\n  grow."
        let locallyJoined = first + " grow."
        for probability in [0.1, 0.99] {
            var requests = 0
            let session = makeSession { request in
                requests += 1
                let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: Self.body(of: request)) as? [String: Any])
                let state = try XCTUnwrap(body["state"] as? [String: Any])
                let lines = try XCTUnwrap(state["lines"] as? [[String: String]])
                XCTAssertEqual(lines[0]["text"], locallyJoined)
                let questions = try XCTUnwrap(body["questions"] as? [String: Any])
                XCTAssertEqual(Set(questions.keys), ["join_3"])
                return (200, try JSONSerialization.data(withJSONObject: [
                    "model": "bjev", "answers": ["join_3": ["type": "noul", "noul": probability]]
                ]))
            }
            defer { session.invalidateAndCancel() }
            let result = try await SystemOneNormalizer(provider: .bjev, session: session)
                .normalize(localBlock + "\n\nWe need\nmore flowers.", apiKey: "synthetic-key")
            XCTAssertEqual(requests, 1)
            XCTAssertEqual(result, locallyJoined + (probability > 0.8 ? "\n\nWe need more flowers." : "\n\nWe need\nmore flowers."))
        }
    }

    func testProviderThresholdsJoinBjevWrapsWithoutChangingJevPolicy() async throws {
        for provider in CloudProvider.allCases {
            for probability in [0.7999, 0.8, 0.8848, 0.98] {
                let session = makeSession { _ in
                    (200, try JSONSerialization.data(withJSONObject: [
                        "model": provider.model,
                        "answers": ["join_1": ["type": "noul", "noul": probability]]
                    ]))
                }
                let result = try await SystemOneNormalizer(provider: provider, session: session)
                    .normalize("我们准备沿着花园的小路\n  继续向前散步。", apiKey: "synthetic-key")
                let shouldJoin = provider == .bjev ? probability >= 0.8 : probability >= 0.98
                XCTAssertEqual(result, shouldJoin ? "我们准备沿着花园的小路继续向前散步。" : "我们准备沿着花园的小路\n  继续向前散步。")
                session.invalidateAndCancel()
            }
        }
    }

    func testBjevUsesItsOwnEndpointKeyAndModelWithSharedBoundaryValidation() async throws {
        let session = makeSession { request in
            XCTAssertEqual(request.url?.absoluteString, "https://bjev.bytedance.net/v1/systemone")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer bjev-test-key")
            let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: Self.body(of: request)) as? [String: Any])
            XCTAssertEqual(body["model"] as? String, "bjev")
            return (200, Data(#"{"model":"bjev","answers":{"join_1":{"type":"noul","noul":0.99},"join_2":{"type":"noul","noul":0.1}},"usage":{"input_tokens":95,"output_tokens":197},"latency_ms":111.0}"#.utf8))
        }
        defer { session.invalidateAndCancel() }
        let output = try await SystemOneNormalizer(provider: .bjev, session: session)
            .normalize("本轮需要\n继续核对\n  等待确认。", apiKey: "bjev-test-key")
        XCTAssertEqual(output, "本轮需要继续核对\n  等待确认。")
    }

    func testBjevRejectsResponsesFromAnotherModel() async {
        let session = makeSession { _ in
            (200, Data(#"{"model":"jev-1.13.0","answers":{"join_1":{"type":"noul","noul":1}}}"#.utf8))
        }
        defer { session.invalidateAndCancel() }
        do {
            _ = try await SystemOneNormalizer(provider: .bjev, session: session).normalize("We need\nmore checks.", apiKey: "test-key")
            XCTFail("Accepted the wrong provider model")
        } catch JudgmentError.invalidResponse {} catch { XCTFail("Unexpected error: \(error)") }
    }

    private func answer(_ probability: Double) -> SystemOneResponse.Answer {
        .init(type: "noul", noul: probability)
    }

    func testReportedShellCopyTextHasAJoinableBoundary() throws {
        let first = "直接执行：已修复并重新打包。请退出旧版，再打开新版 Shell Copy (build/Shell Copy.app)，即可使用"
        let next = "Command-V 粘贴、Command-A 全选。"
        let plan = try XCTUnwrap(LineJoinPlan(first + "\n  " + next))
        XCTAssertEqual(plan.boundaries, [1])
        XCTAssertEqual(try plan.applying(["join_1": answer(0.99)]), first + next)
    }

    func testRegionRestrictionHasActionableError() async throws {
        let session = makeSession { _ in
            (451, Data(#"{"title":"Typesafe is not available in your region.","status":451}"#.utf8))
        }
        defer { session.invalidateAndCancel() }
        do {
            _ = try await SystemOneNormalizer(session: session).normalize("We need\nmore checks.", apiKey: "test-key")
            XCTFail("Region restriction accepted")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("region"), error.localizedDescription)
            XCTAssertTrue(error.localizedDescription.contains("451"), error.localizedDescription)
        }
    }

    func testShortUnindentedChineseCanJoinAndLowProbabilityBoundaryStaysExact() throws {
        let input = "本轮需要  继续\r\n核对历史数据\n  等待确认。\r\n \r\n另一段。"
        let plan = try XCTUnwrap(LineJoinPlan(input))
        XCTAssertEqual(plan.boundaries, [1, 2])
        XCTAssertEqual(try plan.applying(["join_1": answer(0.99), "join_2": answer(0.7)]),
                       "本轮需要  继续核对历史数据\n  等待确认。\r\n \r\n另一段。")
    }

    func testEnglishChainPreservesLeadingIndentAndInternalColumns() throws {
        let input = "    We  need\n        more checks\n before release.\n"
        let plan = try XCTUnwrap(LineJoinPlan(input))
        XCTAssertEqual(try plan.applying(["join_1": answer(1), "join_2": answer(0.98)]),
                       "    We  need more checks before release.\n")
        XCTAssertEqual(try plan.applying(["join_1": answer(0.979), "join_2": answer(0)]), input)
    }

    func testStructuredContentAndExplicitBreaksAreNeverCandidates() throws {
        for text in [
            "```\nWe need\nmore checks\n```", "~~~text\na\nb\n~~~",
            "- We need\n  more checks", "1. We need\nmore checks",
            "# Release\nchecklist", "We need\n\tmore checks",
            "echo this command\nkeeps its break", "INFO release\nmore checks",
            "description: We need\nmore checks", "We need\n{more checks}",
            "We need\n\nmore checks", "We need.\nMore checks.", "We need\nmore checks\0",
            "x", "", String(repeating: "a", count: 12_289) + "\nb",
            Array(repeating: "some words", count: 66).joined(separator: "\n")
        ] {
            XCTAssertNil(LineJoinPlan(text), text.prefix(100).description)
        }
        let input = "- Keep this list\n  and its wrap\n\nWe need\nmore checks."
        let plan = try XCTUnwrap(LineJoinPlan(input))
        XCTAssertEqual(plan.boundaries, [4])
        XCTAssertEqual(try plan.applying(["join_4": answer(1), "join_1": answer(1)]),
                       "- Keep this list\n  and its wrap\n\nWe need more checks.")
    }

    func testIncompleteOrInvalidAnswersNeverPartiallyApply() throws {
        let plan = try XCTUnwrap(LineJoinPlan("We need\nmore checks\nbefore release."))
        for answers in [
            ["join_1": answer(1)],
            ["join_1": answer(1), "join_2": answer(1.01)],
            ["join_1": answer(1), "join_2": answer(-0.1)],
            ["join_1": answer(1), "join_2": answer(.nan)],
            ["join_1": answer(1), "join_2": .init(type: "choice", noul: 1)]
        ] {
            XCTAssertThrowsError(try plan.applying(answers))
        }
    }

    func testHTTPContractAndMixedLanguageResult() async throws {
        let session = makeSession { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.typesafe.ai/v1/systemone")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.timeoutInterval, 2)
            let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: Self.body(of: request)) as? [String: Any])
            XCTAssertEqual(body["model"] as? String, "jev-1.13.0")
            let state = try XCTUnwrap(body["state"] as? [String: Any])
            let lines = try XCTUnwrap(state["lines"] as? [[String: String]])
            XCTAssertEqual(lines[0], ["id": "L0", "text": "Hive 校验需要"])
            let questions = try XCTUnwrap(body["questions"] as? [String: [String: Any]])
            XCTAssertEqual(Set(questions.keys), ["join_1", "join_2"])
            XCTAssertEqual(questions["join_1"]?["type"] as? String, "noul")
            XCTAssertTrue((questions["join_1"]?["instructions"] as? String)?.contains("L0") == true)
            return (200, Data(#"{"model":"jev-1.13.0","answers":{"join_1":{"type":"noul","noul":0.99},"join_2":{"type":"noul","noul":0.99}}}"#.utf8))
        }
        defer { session.invalidateAndCancel() }
        let result = try await SystemOneNormalizer(session: session).normalize("Hive 校验需要\n继续核对\n结果。", apiKey: "test-key")
        XCTAssertEqual(result, "Hive 校验需要继续核对结果。")
    }

    func testIneligibleTextAndMissingKeyDoNotSendRequests() async throws {
        let session = makeSession { _ in
            XCTFail("Ineligible text or missing keys must not send requests")
            throw URLError(.badURL)
        }
        defer { session.invalidateAndCancel() }
        let client = SystemOneNormalizer(session: session)
        let original = "- List\n  continuation"
        let result = try await client.normalize(original, apiKey: "test-key")
        XCTAssertEqual(result, original)
        do {
            _ = try await client.normalize("We need\nmore checks.", apiKey: "")
            XCTFail("Missing key accepted")
        } catch JudgmentError.missingAPIKey {} catch { XCTFail("Unexpected error: \(error)") }
    }

    func testServiceErrorsAndMalformedResponsesAreRejected() async throws {
        let cases: [(Int, String, JudgmentError)] = [
            (401, "secret server body", .unauthorized), (429, "secret", .rateLimited),
            (529, "secret", .rateLimited), (500, "secret", .httpFailure(500)),
            (302, "secret", .httpFailure(302)), (422, "secret", .httpFailure(422)),
            (200, "not json", .invalidResponse),
            (200, #"{"model":"jev-1.13.0","answers":{}}"#, .invalidResponse),
            (200, #"{"model":"other","answers":{"join_1":{"type":"noul","noul":1}}}"#, .invalidResponse)
        ]
        for (status, body, expected) in cases {
            let session = makeSession { _ in (status, Data(body.utf8)) }
            do {
                _ = try await SystemOneNormalizer(session: session).normalize("We need\nmore checks.", apiKey: "test-key")
                XCTFail("Invalid response accepted: \(status)")
            } catch {
                XCTAssertEqual(error.localizedDescription, expected.localizedDescription)
                XCTAssertFalse(error.localizedDescription.contains("secret"))
            }
            session.invalidateAndCancel()
        }
    }

    func testNetworkTimeoutKeepsAControlledError() async {
        let session = makeSession { _ in throw URLError(.timedOut) }
        defer { session.invalidateAndCancel() }
        do {
            _ = try await SystemOneNormalizer(session: session).normalize("We need\nmore checks.", apiKey: "test-key")
            XCTFail("Timeout accepted")
        } catch {
            XCTAssertEqual(error.localizedDescription, JudgmentError.timedOut.localizedDescription)
        }
    }

    private func makeSession(_ handler: @escaping (URLRequest) throws -> (Int, Data)) -> URLSession {
        StubURLProtocol.setHandler(handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func body(of request: URLRequest) throws -> Data {
        if let data = request.httpBody { return data }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            result.append(contentsOf: buffer.prefix(count))
        }
        return result
    }
}

private final class StubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var handler: ((URLRequest) throws -> (Int, Data))?

    static func setHandler(_ handler: @escaping (URLRequest) throws -> (Int, Data)) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let handler = Self.handler!
        Self.lock.unlock()
        do {
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
