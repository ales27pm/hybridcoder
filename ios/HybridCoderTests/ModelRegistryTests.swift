import Foundation
import Testing
@testable import HybridCoder

@MainActor
struct ModelRegistryTests {

    @Test("Registry keeps orchestration and code-generation model IDs distinct")
    func generationAndCodeGenerationIDsAreDistinct() {
        let registry = ModelRegistry()

        #expect(registry.activeGenerationModelID != registry.activeCodeGenerationModelID)
        #expect(registry.entry(for: registry.activeGenerationModelID)?.capability == .orchestration)
        #expect(registry.entry(for: registry.activeCodeGenerationModelID)?.capability == .codeGeneration)
    }

    @Test("Code generation model defaults to not installed")
    func codeGenerationDefaultsToNotInstalled() {
        let registry = ModelRegistry()
        let modelID = registry.activeCodeGenerationModelID
        #expect(registry.entry(for: modelID)?.installState == .notInstalled)
    }

    @Test("Qwen registry entry points at external GGUF artifact")
    func qwenRegistryIncludesGGUFArtifact() {
        let registry = ModelRegistry()
        let modelID = registry.activeCodeGenerationModelID
        let entry = registry.entry(for: modelID)

        #expect(entry?.remoteBaseURL == nil)
        #expect(entry?.runtime == .llamaCppGGUF)
        #expect(entry?.files.contains(where: {
            $0.localPath == "Qwen2.5-Coder-3B-Instruct-abliterated-Q5_K_M.gguf"
        }) == true)

        let orchestrationEntry = registry.entry(for: registry.activeGenerationModelID)
        #expect(orchestrationEntry?.files == entry?.files)
    }

    @Test("External models folder defaults to Documents/Hybrid Coder/Models and keeps legacy fallbacks")
    func externalModelsFolderPathIsInDocuments() {
        let root = ModelRegistry.externalModelsRoot.path(percentEncoded: false)
        let legacyRoot = ModelRegistry.legacyExternalModelsRoot.path(percentEncoded: false)
        let legacyFlatRoot = ModelRegistry.legacyFlatExternalModelsRoot.path(percentEncoded: false)
        let roots = ModelRegistry.candidateExternalModelsRoots().map { $0.path(percentEncoded: false) }

        #expect(root.contains("Documents"))
        #expect(root.contains("Hybrid Coder"))
        #expect(root.hasSuffix("/Models"))
        #expect(legacyRoot.contains("Documents"))
        #expect(legacyRoot.contains("HybridCoder"))
        #expect(legacyRoot.hasSuffix("/Models"))
        #expect(legacyFlatRoot.contains("Documents"))
        #expect(legacyFlatRoot.hasSuffix("/Models"))
        #expect(roots.contains(root))
        #expect(roots.contains(legacyRoot))
        #expect(roots.contains(legacyFlatRoot))
    }

    @Test("Install marker can be written and cleared")
    func codeGenerationInstallMarkerLifecycle() throws {
        let registry = ModelRegistry()
        let modelID = "test/model-\(UUID().uuidString)"

        registry.clearCodeGenerationInstallMarker(modelID: modelID)
        #expect(registry.isCodeGenerationModelMarkedInstalled(modelID: modelID) == false)

        registry.markCodeGenerationModelInstalled(modelID: modelID)
        #expect(registry.isCodeGenerationModelMarkedInstalled(modelID: modelID))
        #expect(registry.isCodeGenerationModelInstalled(modelID: modelID) == false)

        registry.clearCodeGenerationInstallMarker(modelID: modelID)
        #expect(registry.isCodeGenerationModelMarkedInstalled(modelID: modelID) == false)
    }

    @Test("normalizedModelsRoot normalizes file, Documents, Hybrid Coder, HybridCoder, and Models URLs")
    func normalizedModelsRootVariants() throws {
        let fm = FileManager.default
        let sandboxRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let documents = sandboxRoot.appendingPathComponent("Documents", isDirectory: true)
        let models = documents
            .appendingPathComponent("Hybrid Coder", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
        let hybridCoderSpaced = documents.appendingPathComponent("Hybrid Coder", isDirectory: true)
        let hybridCoder = documents.appendingPathComponent("HybridCoder", isDirectory: true)
        let hybridModels = hybridCoder.appendingPathComponent("Models", isDirectory: true)
        try fm.createDirectory(at: models, withIntermediateDirectories: true)
        try fm.createDirectory(at: hybridModels, withIntermediateDirectories: true)

        let ggufFile = models.appendingPathComponent("sample.gguf", isDirectory: false)
        try Data("gguf".utf8).write(to: ggufFile)

        let fileNormalized = ModelRegistry.normalizedModelsRoot(from: ggufFile)
        let documentsNormalized = ModelRegistry.normalizedModelsRoot(from: documents)
        let hybridSpacedNormalized = ModelRegistry.normalizedModelsRoot(from: hybridCoderSpaced)
        let hybridNormalized = ModelRegistry.normalizedModelsRoot(from: hybridCoder)
        let modelsNormalized = ModelRegistry.normalizedModelsRoot(from: models)

        #expect(fileNormalized?.path(percentEncoded: false) == models.path(percentEncoded: false))
        #expect(documentsNormalized?.path(percentEncoded: false) == models.path(percentEncoded: false))
        #expect(hybridSpacedNormalized?.path(percentEncoded: false) == models.path(percentEncoded: false))
        #expect(hybridNormalized?.path(percentEncoded: false) == hybridModels.path(percentEncoded: false))
        #expect(modelsNormalized?.path(percentEncoded: false) == models.path(percentEncoded: false))

        try? fm.removeItem(at: sandboxRoot)
    }

    @Test("GGUF install detection resolves in preferred, primary, legacy, and flat legacy roots")
    func ggufInstallDetectionAcrossRoots() throws {
        let fm = FileManager.default
        let sandboxRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let primaryRoot = sandboxRoot
            .appendingPathComponent("Primary", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
        let legacyRoot = sandboxRoot
            .appendingPathComponent("Legacy", isDirectory: true)
            .appendingPathComponent("HybridCoder", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
        let legacyFlatRoot = sandboxRoot
            .appendingPathComponent("LegacyFlat", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
        try fm.createDirectory(at: primaryRoot, withIntermediateDirectories: true)
        try fm.createDirectory(at: legacyRoot, withIntermediateDirectories: true)
        try fm.createDirectory(at: legacyFlatRoot, withIntermediateDirectories: true)

        let registry = ModelRegistry(
            externalModelsRootOverride: primaryRoot,
            legacyExternalModelsRootOverride: legacyRoot,
            legacyFlatExternalModelsRootOverride: legacyFlatRoot
        )
        let modelID = registry.activeEmbeddingModelID
        let fileName = registry.resolvedLocalModelName(for: modelID)

        let preferredDocuments = fm.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("Documents", isDirectory: true)
        let preferredRoot = preferredDocuments
            .appendingPathComponent("Hybrid Coder", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
        try fm.createDirectory(at: preferredRoot, withIntermediateDirectories: true)
        let preferredFile = preferredRoot.appendingPathComponent(fileName, isDirectory: false)
        try Data().write(to: preferredFile)

        #expect(
            registry.isModelInstalledInExternalModelsFolder(
                modelID: modelID,
                preferredRoot: preferredDocuments
            )
        )

        try? fm.removeItem(at: preferredFile)
        let primaryFile = primaryRoot.appendingPathComponent(fileName, isDirectory: false)
        try Data().write(to: primaryFile)

        #expect(registry.isModelInstalledInExternalModelsFolder(modelID: modelID))

        try? fm.removeItem(at: primaryFile)
        let legacyFile = legacyRoot.appendingPathComponent(fileName, isDirectory: false)
        try Data().write(to: legacyFile)

        #expect(registry.isModelInstalledInExternalModelsFolder(modelID: modelID))

        try? fm.removeItem(at: legacyFile)
        let legacyFlatFile = legacyFlatRoot.appendingPathComponent(fileName, isDirectory: false)
        try Data().write(to: legacyFlatFile)

        #expect(registry.isModelInstalledInExternalModelsFolder(modelID: modelID))

        try? fm.removeItem(at: preferredDocuments.deletingLastPathComponent())
        try? fm.removeItem(at: sandboxRoot)
    }
}
