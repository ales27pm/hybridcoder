import Foundation
import Testing
@testable import HybridCoder

struct HFTokenizerTests {

    private struct Fixture {
        let text: String
        let expectedIDsHead: [Int]
        let expectedMaskHead: [Int]
        let nonPadTokens: Int
    }

    private var fixtures: [Fixture] {
        [
            Fixture(
                text: "hello world",
                expectedIDsHead: [0, 42891, 232, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
                expectedMaskHead: [1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
                nonPadTokens: 4
            ),
            Fixture(
                text: "def add(a, b):\n    return a + b",
                expectedIDsHead: [0, 9232, 1606, 1640, 102, 6, 741, 3256, 50118, 1437, 1437, 1437, 671, 10, 2055, 741],
                expectedMaskHead: [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
                nonPadTokens: 17
            ),
            Fixture(
                text: "HTTPServerError: failed_to_parse JSON payload.",
                expectedIDsHead: [0, 14469, 45796, 39540, 30192, 35, 1447, 1215, 560, 1215, 48778, 47192, 29239, 4, 2, 1],
                expectedMaskHead: [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0],
                nonPadTokens: 15
            )
        ]
    }

    @Test("HF tokenizer parity with known CodeBERT token-id fixtures")
    func tokenizerParity() async throws {
        let tokenizer = HFTokenizer()
        try await tokenizer.load(from: try tokenizerFixtureDirectory())

        for fixture in fixtures {
            let encoded = try await tokenizer.encode(text: fixture.text)
            #expect(Array(encoded.inputIDs.prefix(fixture.expectedIDsHead.count)) == fixture.expectedIDsHead)
            #expect(Array(encoded.attentionMask.prefix(fixture.expectedMaskHead.count)) == fixture.expectedMaskHead)
            #expect(encoded.attentionMask.reduce(0, +) == fixture.nonPadTokens)
            #expect(encoded.inputIDs.count == 512)
        }
    }

    @Test("Load fails loudly when tokenizer.json is missing")
    func missingTokenizerFileFails() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let tokenizer = HFTokenizer()
        do {
            try await tokenizer.load(from: dir)
            Issue.record("Expected missing tokenizer error")
        } catch let error as HFTokenizer.TokenizerError {
            if case .fileNotFound = error {
                #expect(true)
            } else {
                Issue.record("Unexpected tokenizer error: \(error)")
            }
        }
    }

    @Test("Load fails loudly on incompatible tokenizer model type")
    func incompatibleTokenizerFails() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let incompatible = """
        {
          "pre_tokenizer": { "type": "ByteLevel" },
          "model": {
            "type": "WordPiece",
            "vocab": {"<s>":0, "</s>":2, "<pad>":1, "<unk>":3},
            "merges": ["a b"]
          }
        }
        """

        try incompatible.write(to: dir.appendingPathComponent("tokenizer.json"), atomically: true, encoding: .utf8)

        let tokenizer = HFTokenizer()
        do {
            try await tokenizer.load(from: dir)
            Issue.record("Expected incompatible tokenizer error")
        } catch let error as HFTokenizer.TokenizerError {
            if case .incompatibleTokenizer = error {
                #expect(true)
            } else {
                Issue.record("Unexpected tokenizer error: \(error)")
            }
        }
    }

    private func tokenizerFixtureDirectory() throws -> URL {
        let bundle = Bundle(for: HFTokenizerTestsBundleMarker.self)
        let tokenizer = try #require(bundle.url(forResource: "tokenizer", withExtension: "json"))

        guard FileManager.default.fileExists(atPath: tokenizer.path) else {
            throw HFTokenizer.TokenizerError.fileNotFound("Missing test fixture tokenizer.json at \(tokenizer.path)")
        }
        return tokenizer.deletingLastPathComponent()
    }
}

private final class HFTokenizerTestsBundleMarker {}
