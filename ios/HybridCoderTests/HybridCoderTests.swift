import Foundation
import Testing
@testable import HybridCoder

struct HybridCoderTests {
    @MainActor
    @Test func bookmarkedExternalModelsFolderIsRecognizedAsReady() async throws {
        let fm = FileManager.default
        let sandboxRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let canonicalRoot = sandboxRoot
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
        let externalBookmarkedRoot = sandboxRoot
            .appendingPathComponent("ExternalDrive", isDirectory: true)
            .appendingPathComponent("Hybrid Coder", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
        try fm.createDirectory(at: canonicalRoot, withIntermediateDirectories: true)
        try fm.createDirectory(at: externalBookmarkedRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: sandboxRoot) }

        let registry = ModelRegistry(externalModelsRootOverride: canonicalRoot)
        let defaultsSuite = "com.hybridcoder.tests.external-models.defaults.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: defaultsSuite)!
        testDefaults.removePersistentDomain(forName: defaultsSuite)
        defer { testDefaults.removePersistentDomain(forName: defaultsSuite) }

        let bookmarkService = BookmarkService(
            secureStore: SecureStoreService(serviceName: "com.hybridcoder.tests.external-models.bookmarks.\(UUID().uuidString)"),
            userDefaults: testDefaults
        )
        try await bookmarkService.saveModelsFolderBookmark(for: externalBookmarkedRoot)
        let downloadService = ModelDownloadService(registry: registry, bookmarkService: bookmarkService)

        let preferredRoot = await bookmarkService.resolveModelsFolderBookmark()
        let codeModelID = registry.activeCodeGenerationModelID
        let generationModelID = registry.activeGenerationModelID
        let sharedFileName = try #require(registry.entry(for: codeModelID)?.files.first?.localPath)
        let modelURL = externalBookmarkedRoot.appendingPathComponent(sharedFileName, isDirectory: false)
        try Data("gguf".utf8).write(to: modelURL, options: .atomic)

        await downloadService.refreshInstallState(modelID: codeModelID)
        await downloadService.refreshInstallState(modelID: generationModelID)

        let resolver = ModelLocationResolver(registry: registry)
        let codeReadiness = resolver.readiness(modelID: codeModelID, preferredRoot: preferredRoot)
        let generationReadiness = resolver.readiness(modelID: generationModelID, preferredRoot: preferredRoot)
        let foundationService = FoundationModelService(
            registry: registry,
            modelID: generationModelID,
            bookmarkService: bookmarkService
        )
        await foundationService.refreshStatusFromBookmark()

        #expect(codeReadiness.isReady)
        #expect(generationReadiness.isReady)
        #expect(foundationService.isAvailable)
        #expect(foundationService.statusText == "Ready")
        #expect(registry.entry(for: codeModelID)?.installState == .installed)
        #expect(registry.entry(for: generationModelID)?.installState == .installed)
    }

    @MainActor
    @Test func readinessRequiresAllRegisteredFilesAndReportsMissingFilename() async throws {
        let fm = FileManager.default
        let sandboxRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let modelsRoot = sandboxRoot
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
        try fm.createDirectory(at: modelsRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: sandboxRoot) }

        let registry = ModelRegistry(externalModelsRootOverride: modelsRoot)
        let modelID = "custom-multifile"
        registry.registerCustomModel(ModelRegistry.Entry(
            id: modelID,
            displayName: "Custom Multi File",
            capability: .codeGeneration,
            provider: .customURL,
            runtime: .llamaCppGGUF,
            remoteBaseURL: "https://example.com/models",
            files: [
                ModelRegistry.ModelFile(remotePath: "present.gguf", localPath: "present.gguf"),
                ModelRegistry.ModelFile(remotePath: "missing.gguf", localPath: "missing.gguf")
            ],
            isAvailable: true,
            installState: .notInstalled,
            loadState: .unloaded
        ))

        try Data("gguf".utf8).write(
            to: modelsRoot.appendingPathComponent("present.gguf", isDirectory: false),
            options: .atomic
        )

        let readiness = ModelLocationResolver(registry: registry).readiness(modelID: modelID)
        #expect(!readiness.isReady)
        #expect(readiness.expectedFilename == "missing.gguf")
        #expect(readiness.failureReason?.contains("missing.gguf") == true)
    }

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

        let result = await engine.apply(plan, repoRoot: repoRoot)

        #expect(result.failures.isEmpty)
        #expect(result.updatedPlan.operations.allSatisfy { $0.status == .applied })

        let events = await recorder.snapshot()
        let markers = Dictionary(
            events.map { ($0.key, $0.value) },
            uniquingKeysWith: { first, _ in first }
        )

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

    @Test func patchEngineRejectsTraversalOutsideRepoRoot() async throws {
        let repoRoot = try makeTempRepoRoot()
        defer { try? FileManager.default.removeItem(at: repoRoot) }

        let operation = PatchOperation(filePath: "../outside.txt", searchText: "x", replaceText: "y")
        let plan = PatchPlan(summary: "traversal", operations: [operation])

        let result = await PatchEngine(repoAccess: RepoAccessService()).apply(plan, repoRoot: repoRoot)

        #expect(result.changedFiles.isEmpty)
        #expect(result.updatedPlan.operations.map(\.status) == [.failed])
        #expect(result.failures.count == 1)
        #expect(result.failures[0].reason.contains("Path escapes repository root"))
    }

    @Test func patchEngineReportsCanonicalChangedFilePathOnce() async throws {
        let repoRoot = try makeTempRepoRoot()
        defer { try? FileManager.default.removeItem(at: repoRoot) }

        let target = repoRoot.appending(path: "alpha.txt")
        try "A\n".write(to: target, atomically: true, encoding: .utf8)

        let op1 = PatchOperation(filePath: "./alpha.txt", searchText: "A", replaceText: "B")
        let op2 = PatchOperation(filePath: "alpha.txt", searchText: "B", replaceText: "C")
        let plan = PatchPlan(summary: "dedupe", operations: [op1, op2])

        let result = await PatchEngine(repoAccess: RepoAccessService()).apply(plan, repoRoot: repoRoot)

        #expect(result.failures.isEmpty)
        #expect(result.changedFiles == ["alpha.txt"])
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
