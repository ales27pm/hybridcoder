import Foundation
import Testing
@testable import HybridCoder

struct HybridCoderTests {

    @Test func patchEngineQueuesSameCanonicalFileAndRunsDifferentFilesConcurrently() async throws {
        let repoRoot = try makeTempRepoRoot()
        defer { try? FileManager.default.removeItem(at: repoRoot) }

        let fileA = repoRoot.appending(path: "alpha.txt")
        let fileB = repoRoot.appending(path: "beta.txt")
        try "A\n".write(to: fileA, atomically: true, encoding: .utf8)
        try "X\n".write(to: fileB, atomically: true, encoding: .utf8)

        let operationA1 = PatchOperation(filePath: "./alpha.txt", searchText: "A", replaceText: "B")
        let operationB1 = PatchOperation(filePath: "beta.txt", searchText: "X", replaceText: "Y")
        let operationA2 = PatchOperation(filePath: "alpha.txt", searchText: "B", replaceText: "C")

        let recorder = EventRecorder()
        let plan = PatchPlan(summary: "mixed", operations: [operationA1, operationB1, operationA2])
        let engine = PatchEngine(repoAccess: RepoAccessService()) { operation, content in
            await recorder.record(.start(operationID: operation.id, time: Date()))
            try await Task.sleep(for: .milliseconds(200))
            let matchCount = countLiteralOccurrences(of: operation.searchText, in: content)
            if matchCount == 0 {
                throw PatchEngine.PatchError.searchTextNotFound(operation.filePath)
            }
            if matchCount > 1 {
                throw PatchEngine.PatchError.multipleMatches(operation.filePath, matchCount)
            }
            let updated = content.replacingOccurrences(of: operation.searchText, with: operation.replaceText)
            await recorder.record(.end(operationID: operation.id, time: Date()))
            return updated
        }

        let startedAt = Date()
        let result = await engine.apply(plan, repoRoot: repoRoot)
        let elapsed = Date().timeIntervalSince(startedAt)

        #expect(result.failures.isEmpty)
        #expect(result.updatedPlan.operations.allSatisfy { $0.status == .applied })
        #expect(elapsed < 0.55)

        let events = await recorder.snapshot()
        let markers = Dictionary(uniqueKeysWithValues: events.map { ($0.key, $0.value) })

        let a1Start = try #require(markers[.start(operationID: operationA1.id)])
        let a1End = try #require(markers[.end(operationID: operationA1.id)])
        let a2Start = try #require(markers[.start(operationID: operationA2.id)])
        let b1Start = try #require(markers[.start(operationID: operationB1.id)])

        #expect(a2Start >= a1End)
        #expect(b1Start < a1End)
        #expect(a1Start <= a1End)

        let alphaContents = try String(contentsOf: fileA, encoding: .utf8)
        let betaContents = try String(contentsOf: fileB, encoding: .utf8)
        #expect(alphaContents.contains("C"))
        #expect(betaContents.contains("Y"))
    }

    @Test func patchEngineFailureOrderingRemainsDeterministicAcrossConcurrentGroups() async throws {
        let repoRoot = try makeTempRepoRoot()
        defer { try? FileManager.default.removeItem(at: repoRoot) }

        let first = repoRoot.appending(path: "first.txt")
        let second = repoRoot.appending(path: "second.txt")
        try "one".write(to: first, atomically: true, encoding: .utf8)
        try "two".write(to: second, atomically: true, encoding: .utf8)

        let op0 = PatchOperation(filePath: "first.txt", searchText: "missing-a", replaceText: "x")
        let op1 = PatchOperation(filePath: "second.txt", searchText: "missing-b", replaceText: "y")
        let plan = PatchPlan(summary: "failures", operations: [op0, op1])

        let result = await PatchEngine(repoAccess: RepoAccessService()).apply(plan, repoRoot: repoRoot)

        #expect(result.failures.count == 2)
        #expect(result.failures.map(\.operationID) == [op0.id, op1.id])
        #expect(result.updatedPlan.operations.map(\.status) == [.failed, .failed])
    }
}

private actor EventRecorder {
    private var events: [(EventKey, Date)] = []

    func record(_ event: Event) {
        events.append((event.key, event.time))
    }

    func snapshot() -> [(key: EventKey, value: Date)] {
        events
    }
}

private enum Event {
    case start(operationID: UUID, time: Date)
    case end(operationID: UUID, time: Date)

    var key: EventKey {
        switch self {
        case .start(let operationID, _):
            return .start(operationID: operationID)
        case .end(let operationID, _):
            return .end(operationID: operationID)
        }
    }

    var time: Date {
        switch self {
        case .start(_, let time), .end(_, let time):
            return time
        }
    }
}

private enum EventKey: Hashable {
    case start(operationID: UUID)
    case end(operationID: UUID)
}

private func makeTempRepoRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func countLiteralOccurrences(of needle: String, in haystack: String) -> Int {
    guard !needle.isEmpty else { return 0 }
    var count = 0
    var searchRange = haystack.startIndex..<haystack.endIndex

    while let range = haystack.range(of: needle, options: .literal, range: searchRange) {
        count += 1
        searchRange = range.upperBound..<haystack.endIndex
    }

    return count
}
