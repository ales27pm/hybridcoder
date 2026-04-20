#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

MODEL_REGISTRY_PATH = Path("ios") / "HybridCoder" / "Services" / "ModelRegistry.swift"
MODEL_MANAGER_VIEW_PATH = Path("ios") / "HybridCoder" / "Views" / "ModelManagerView.swift"
AI_ORCHESTRATOR_PATH = Path("ios") / "HybridCoder" / "Services" / "AIOrchestrator.swift"
PBXPROJ_PATH = Path("ios") / "HybridCoder.xcodeproj" / "project.pbxproj"

YAMS_PACKAGE_REF = "D0A11E110000000000000001"
YAMS_PRODUCT = "D0A11E110000000000000002"
TOKENIZERS_PRODUCT = "D0A11E110000000000000003"
YAMS_BUILD_FILE = "D0A11E110000000000000004"
TOKENIZERS_BUILD_FILE = "D0A11E110000000000000005"


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def write_text(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")


def ensure_contains(text: str, needle: str, *, label: str) -> None:
    if needle not in text:
        raise RuntimeError(f"Missing expected anchor for {label}: {needle[:120]!r}")


def insert_after(text: str, anchor: str, block: str, *, label: str) -> str:
    if block in text:
        return text
    ensure_contains(text, anchor, label=label)
    return text.replace(anchor, anchor + block, 1)


def replace_once(text: str, before: str, after: str, *, label: str) -> str:
    if after in text:
        return text
    ensure_contains(text, before, label=label)
    return text.replace(before, after, 1)


def patch_model_registry(repo_root: Path) -> None:
    path = repo_root / MODEL_REGISTRY_PATH
    text = read_text(path)

    text = replace_once(
        text,
        "        case coreMLPipelines\n",
        "        case coreMLPipelines\n        case anemll\n",
        label="ModelRegistry.Runtime",
    )
    text = insert_after(
        text,
        '    private let codeGenerationID = "finnvoorhees/coreml-Qwen2.5-Coder-1.5B-Instruct-4bit"\n',
        '    private let anemllCodeGenerationID = "anemll/imported-bundle"\n',
        label="ModelRegistry ids",
    )
    text = replace_once(
        text,
        '            codeGenerationID: Entry(\n                id: codeGenerationID,\n                displayName: "Qwen2.5-Coder 1.5B Instruct (4-bit)",\n                capability: .codeGeneration,\n                provider: .huggingFace,\n                runtime: .coreMLPipelines,\n                remoteBaseURL: "https://huggingface.co/finnvoorhees/coreml-Qwen2.5-Coder-1.5B-Instruct-4bit/resolve/main",\n                files: qwenFiles,\n                isAvailable: true,\n                installState: .notInstalled,\n                loadState: .unloaded\n            )\n',
        '            codeGenerationID: Entry(\n                id: codeGenerationID,\n                displayName: "Qwen2.5-Coder 1.5B Instruct (4-bit)",\n                capability: .codeGeneration,\n                provider: .huggingFace,\n                runtime: .coreMLPipelines,\n                remoteBaseURL: "https://huggingface.co/finnvoorhees/coreml-Qwen2.5-Coder-1.5B-Instruct-4bit/resolve/main",\n                files: qwenFiles,\n                isAvailable: true,\n                installState: .notInstalled,\n                loadState: .unloaded\n            ),\n            anemllCodeGenerationID: Entry(\n                id: anemllCodeGenerationID,\n                displayName: "ANEMLL Imported Bundle",\n                capability: .codeGeneration,\n                provider: .apple,\n                runtime: .anemll,\n                remoteBaseURL: nil,\n                files: [],\n                isAvailable: true,\n                installState: .notInstalled,\n                loadState: .unloaded\n            )\n',
        label="ModelRegistry initialEntries",
    )
    text = replace_once(
        text,
        '        guard let entry = entries[modelID], entry.runtime == .coreMLPipelines, entry.files.isEmpty == false else {\n            return false\n        }\n\n        let snapshotDirectory = codeGenerationSnapshotDirectory(for: modelID)\n',
        '        guard let entry = entries[modelID] else {\n            return false\n        }\n\n        if entry.runtime == .anemll {\n            return ANEMLLBundleImportService.shared.importedBundles().isEmpty == false\n        }\n\n        guard entry.runtime == .coreMLPipelines, entry.files.isEmpty == false else {\n            return false\n        }\n\n        let snapshotDirectory = codeGenerationSnapshotDirectory(for: modelID)\n',
        label="ModelRegistry installed check",
    )

    write_text(path, text)


def patch_model_manager_view(repo_root: Path) -> None:
    path = repo_root / MODEL_MANAGER_VIEW_PATH
    text = read_text(path)

    text = replace_once(
        text,
        '                coreMLModelCard(for: orchestrator.modelRegistry.activeEmbeddingModelID)\n                coreMLModelCard(for: orchestrator.modelRegistry.activeCodeGenerationModelID)\n',
        '                coreMLModelCard(for: orchestrator.modelRegistry.activeEmbeddingModelID)\n                ForEach(orchestrator.modelRegistry.allModels.filter { $0.capability == .codeGeneration }) { model in\n                    coreMLModelCard(for: model.id)\n                }\n',
        label="ModelManagerView code generation list",
    )
    text = insert_after(
        text,
        '        let isEmbedding = model?.capability == .embedding\n        let isCodeGen = model?.capability == .codeGeneration\n',
        '        let isActiveCodeGen = isCodeGen && modelID == orchestrator.modelRegistry.activeCodeGenerationModelID\n',
        label="ModelManagerView active runtime variable",
    )
    text = insert_after(
        text,
        '                if installState == .notInstalled && !isBusy(installState: installState, loadState: loadState) {\n',
        '                if isCodeGen && !isActiveCodeGen {\n                    Button("Use Runtime") {\n                        orchestrator.modelRegistry.setActiveCodeGenerationModel(id: modelID)\n                    }\n                    .font(.caption.weight(.medium))\n                    .buttonStyle(.bordered)\n                    .controlSize(.small)\n                }\n\n',
        label="ModelManagerView runtime switch button",
    )

    write_text(path, text)


def patch_ai_orchestrator(repo_root: Path) -> None:
    path = repo_root / AI_ORCHESTRATOR_PATH
    text = read_text(path)

    text = insert_after(
        text,
        '    private(set) var qwenCoderService: QwenCoderService?\n',
        '    private(set) var anemllCoderService: ANEMLLCoderService?\n',
        label="AIOrchestrator service storage",
    )
    text = replace_once(
        text,
        '        if qwenCoderService == nil {\n            qwenCoderService = makeQwenCoderService(modelID: modelRegistry.activeCodeGenerationModelID)\n            modelRegistry.setLoadState(for: modelRegistry.activeCodeGenerationModelID, .unloaded)\n        }\n',
        '        if qwenCoderService == nil {\n            qwenCoderService = makeQwenCoderService(modelID: modelRegistry.activeCodeGenerationModelID)\n            modelRegistry.setLoadState(for: modelRegistry.activeCodeGenerationModelID, .unloaded)\n        }\n\n        if anemllCoderService == nil {\n            anemllCoderService = makeANEMLLCoderService(modelID: modelRegistry.activeCodeGenerationModelID)\n        }\n',
        label="AIOrchestrator warmUp init",
    )
    text = insert_after(
        text,
        '    private func makeQwenCoderService(modelID: String) -> QwenCoderService {\n        let downloadService = modelDownload\n        let tokenProvider: () -> String? = { [weak downloadService] in\n            guard let downloadService else { return nil }\n            let token = downloadService.huggingFaceToken.trimmingCharacters(in: .whitespacesAndNewlines)\n            return token.isEmpty ? nil : token\n        }\n        return QwenCoderService(\n            modelName: modelID,\n            hubDownloadBase: ModelRegistry.coreMLPipelinesDownloadRoot,\n            accessTokenProvider: tokenProvider\n        )\n    }\n',
        '\n    private func makeANEMLLCoderService(modelID: String) -> ANEMLLCoderService {\n        ANEMLLCoderService(modelName: modelID)\n    }\n\n    private func ensureANEMLLServiceMatchesActiveModel() async -> ANEMLLCoderService {\n        let activeModelID = modelRegistry.activeCodeGenerationModelID\n\n        if let existing = anemllCoderService,\n           existing.modelName == activeModelID {\n            return existing\n        }\n\n        let service = makeANEMLLCoderService(modelID: activeModelID)\n        anemllCoderService = service\n        return service\n    }\n\n    private func activeCodeGenerationRuntime() -> ModelRegistry.Runtime? {\n        modelRegistry.entry(for: modelRegistry.activeCodeGenerationModelID)?.runtime\n    }\n',
        label="AIOrchestrator ANEMLL helpers",
    )
    text = replace_once(
        text,
        '            let service = await ensureQwenServiceMatchesActiveModel()\n            try await service.warmUp { [weak self] progress in\n',
        '            let runtime = activeCodeGenerationRuntime()\n            if runtime == .anemll {\n                let service = await ensureANEMLLServiceMatchesActiveModel()\n                try await service.warmUp { [weak self] progress in\n                    Task { @MainActor [weak self] in\n                        guard let self else { return }\n                        let bounded = min(max(progress, 0.05), 0.99)\n                        self.modelRegistry.setInstallState(for: activeModelID, .downloading(progress: bounded))\n                        onProgress?(bounded)\n                    }\n                }\n                guard codeGenerationLifecycleToken == token else { return }\n                modelRegistry.setInstallState(for: activeModelID, .installed)\n                modelRegistry.setLoadState(for: activeModelID, .loaded)\n                warmUpError = nil\n                return\n            }\n\n            let service = await ensureQwenServiceMatchesActiveModel()\n            try await service.warmUp { [weak self] progress in\n',
        label="AIOrchestrator warmUpCodeGenerationModel branching",
    )
    text = replace_once(
        text,
        '        guard let service = qwenCoderService else {\n            modelRegistry.setLoadState(for: modelRegistry.activeCodeGenerationModelID, .unloaded)\n            return\n        }\n\n        _ = try? await service.unload()\n        modelRegistry.setLoadState(for: modelRegistry.activeCodeGenerationModelID, .unloaded)\n',
        '        if activeCodeGenerationRuntime() == .anemll {\n            if let service = anemllCoderService {\n                _ = try? await service.unload()\n            }\n            modelRegistry.setLoadState(for: modelRegistry.activeCodeGenerationModelID, .unloaded)\n            return\n        }\n\n        guard let service = qwenCoderService else {\n            modelRegistry.setLoadState(for: modelRegistry.activeCodeGenerationModelID, .unloaded)\n            return\n        }\n\n        _ = try? await service.unload()\n        modelRegistry.setLoadState(for: modelRegistry.activeCodeGenerationModelID, .unloaded)\n',
        label="AIOrchestrator unload branch",
    )
    text = replace_once(
        text,
        '        let coder = try await requireQwenCoder()\n        return try await coder.generateCode(prompt: query, context: context)\n',
        '        if activeCodeGenerationRuntime() == .anemll {\n            let coder = try await requireANEMLLCoder()\n            return try await coder.generateCode(prompt: query, context: context)\n        }\n\n        let coder = try await requireQwenCoder()\n        return try await coder.generateCode(prompt: query, context: context)\n',
        label="AIOrchestrator generateCode branch",
    )
    text = replace_once(
        text,
        '            let coder = try await requireQwenCoder()\n            var accumulated = ""\n            let result = try await coder.generateCodeStreaming(prompt: query, context: context) { delta in\n',
        '            if activeCodeGenerationRuntime() == .anemll {\n                let coder = try await requireANEMLLCoder()\n                var accumulated = ""\n                let result = try await coder.generateCodeStreaming(prompt: query, context: context) { delta in\n                    accumulated += delta\n                    onPartial(accumulated)\n                }\n                return result.text\n            }\n\n            let coder = try await requireQwenCoder()\n            var accumulated = ""\n            let result = try await coder.generateCodeStreaming(prompt: query, context: context) { delta in\n',
        label="AIOrchestrator streamText branch",
    )
    text = replace_once(
        text,
        '            do {\n                let coder = try await requireQwenCoder()\n                let text = try await coder.generateCodeExplanation(prompt: query, context: context)\n                return ProviderBackedText(text: text, provider: .qwenCodeAssistant)\n            } catch let error as OrchestratorError {\n',
        '            do {\n                if activeCodeGenerationRuntime() == .anemll {\n                    let coder = try await requireANEMLLCoder()\n                    let text = try await coder.generateCodeExplanation(prompt: query, context: context)\n                    return ProviderBackedText(text: text, provider: .qwenCodeAssistant)\n                }\n                let coder = try await requireQwenCoder()\n                let text = try await coder.generateCodeExplanation(prompt: query, context: context)\n                return ProviderBackedText(text: text, provider: .qwenCodeAssistant)\n            } catch let error as OrchestratorError {\n',
        label="AIOrchestrator explanation branch",
    )
    text = replace_once(
        text,
        '            do {\n                let coder = try await requireQwenCoder()\n                var accumulated = ""\n                let result = try await coder.generateCodeExplanationStreaming(prompt: query, context: context) { delta in\n',
        '            do {\n                if activeCodeGenerationRuntime() == .anemll {\n                    let coder = try await requireANEMLLCoder()\n                    var accumulated = ""\n                    let result = try await coder.generateCodeExplanationStreaming(prompt: query, context: context) { delta in\n                        accumulated += delta\n                        onPartial(accumulated)\n                    }\n                    return ProviderBackedText(text: result.text, provider: .qwenCodeAssistant)\n                }\n                let coder = try await requireQwenCoder()\n                var accumulated = ""\n                let result = try await coder.generateCodeExplanationStreaming(prompt: query, context: context) { delta in\n',
        label="AIOrchestrator streaming explanation branch",
    )
    text = insert_after(
        text,
        '    @available(iOS 26.0, *)\n    private func requireFoundationModel() throws -> FoundationModelService {\n        guard let fm = foundationModel as? FoundationModelService else {\n            throw OrchestratorError.foundationModelNotInitialized\n        }\n        fm.refreshStatus()\n        guard fm.isAvailable else {\n            throw OrchestratorError.noModelAvailable\n        }\n        return fm\n    }\n\n\n',
        '    private func requireANEMLLCoder() async throws -> ANEMLLCoderService {\n        do {\n            let coder = await ensureANEMLLServiceMatchesActiveModel()\n            try await coder.warmUp()\n            modelRegistry.setInstallState(for: modelRegistry.activeCodeGenerationModelID, .installed)\n            modelRegistry.setLoadState(for: modelRegistry.activeCodeGenerationModelID, .loaded)\n            return coder\n        } catch {\n            modelRegistry.setLoadState(for: modelRegistry.activeCodeGenerationModelID, .failed(error.localizedDescription))\n            throw OrchestratorError.codeGenerationModelUnavailable(error.localizedDescription)\n        }\n    }\n\n',
        label="AIOrchestrator requireANEMLLCoder",
    )

    write_text(path, text)


def patch_pbxproj(repo_root: Path) -> None:
    path = repo_root / PBXPROJ_PATH
    text = read_text(path)

    text = insert_after(
        text,
        '/* Begin PBXBuildFile section */\n',
        f'\t\t{YAMS_BUILD_FILE} /* Yams in Frameworks */ = {{isa = PBXBuildFile; productRef = {YAMS_PRODUCT} /* Yams */; }};\n\t\t{TOKENIZERS_BUILD_FILE} /* Tokenizers in Frameworks */ = {{isa = PBXBuildFile; productRef = {TOKENIZERS_PRODUCT} /* Tokenizers */; }};\n',
        label="PBXBuildFile section",
    )
    text = insert_after(
        text,
        '/* Begin XCRemoteSwiftPackageReference section */\n',
        f'\t\t{YAMS_PACKAGE_REF} /* XCRemoteSwiftPackageReference "Yams" */ = {{\n\t\t\tisa = XCRemoteSwiftPackageReference;\n\t\t\trepositoryURL = "https://github.com/jpsim/Yams.git";\n\t\t\trequirement = {{\n\t\t\t\tkind = upToNextMajorVersion;\n\t\t\t\tminimumVersion = 5.0.0;\n\t\t\t}};\n\t\t}};\n',
        label="XCRemoteSwiftPackageReference section",
    )
    text = insert_after(
        text,
        '/* Begin XCSwiftPackageProductDependency section */\n',
        f'\t\t{YAMS_PRODUCT} /* Yams */ = {{\n\t\t\tisa = XCSwiftPackageProductDependency;\n\t\t\tpackage = {YAMS_PACKAGE_REF} /* XCRemoteSwiftPackageReference "Yams" */;\n\t\t\tproductName = Yams;\n\t\t}};\n\t\t{TOKENIZERS_PRODUCT} /* Tokenizers */ = {{\n\t\t\tisa = XCSwiftPackageProductDependency;\n\t\t\tpackage = B1C2D3E4F5A60123456789AC /* XCRemoteSwiftPackageReference "swift-transformers" */;\n\t\t\tproductName = Tokenizers;\n\t\t}};\n',
        label="XCSwiftPackageProductDependency section",
    )
    text = replace_once(
        text,
        '\t\t\tfiles = (\n\t\t\t\tC0DEC0DEC0DEC0DEC0DEC001 /* AppIntents.framework in Frameworks */,\n\t\t\t\tA1B2C3D4E5F60123456789AD /* CoreMLPipelines in Frameworks */,\n\t\t\t\tB1C2D3E4F5A60123456789AB /* Hub in Frameworks */,\n\t\t\t);',
        f'\t\t\tfiles = (\n\t\t\t\tC0DEC0DEC0DEC0DEC0DEC001 /* AppIntents.framework in Frameworks */,\n\t\t\t\tA1B2C3D4E5F60123456789AD /* CoreMLPipelines in Frameworks */,\n\t\t\t\tB1C2D3E4F5A60123456789AB /* Hub in Frameworks */,\n\t\t\t\t{YAMS_BUILD_FILE} /* Yams in Frameworks */,\n\t\t\t\t{TOKENIZERS_BUILD_FILE} /* Tokenizers in Frameworks */,\n\t\t\t);',
        label="HybridCoder frameworks",
    )
    text = replace_once(
        text,
        '\t\t\tpackageProductDependencies = (\n\t\t\t\tA1B2C3D4E5F60123456789AC /* CoreMLPipelines */,\n\t\t\t\tB1C2D3E4F5A60123456789AA /* Hub */,\n\t\t\t);',
        f'\t\t\tpackageProductDependencies = (\n\t\t\t\tA1B2C3D4E5F60123456789AC /* CoreMLPipelines */,\n\t\t\t\tB1C2D3E4F5A60123456789AA /* Hub */,\n\t\t\t\t{YAMS_PRODUCT} /* Yams */,\n\t\t\t\t{TOKENIZERS_PRODUCT} /* Tokenizers */,\n\t\t\t);',
        label="HybridCoder package products",
    )
    text = replace_once(
        text,
        '\t\t\tpackageReferences = (\n\t\t\t\tA1B2C3D4E5F60123456789AB /* XCRemoteSwiftPackageReference "CoreMLPipelines" */,\n\t\t\t\tB1C2D3E4F5A60123456789AC /* XCRemoteSwiftPackageReference "swift-transformers" */,\n\t\t\t);',
        f'\t\t\tpackageReferences = (\n\t\t\t\tA1B2C3D4E5F60123456789AB /* XCRemoteSwiftPackageReference "CoreMLPipelines" */,\n\t\t\t\tB1C2D3E4F5A60123456789AC /* XCRemoteSwiftPackageReference "swift-transformers" */,\n\t\t\t\t{YAMS_PACKAGE_REF} /* XCRemoteSwiftPackageReference "Yams" */,\n\t\t\t);',
        label="PBXProject package references",
    )

    write_text(path, text)


def main() -> int:
    parser = argparse.ArgumentParser(description="Apply ANEMLL runtime patches to a local HybridCoder checkout.")
    parser.add_argument("--repo-root", required=True, type=Path)
    args = parser.parse_args()

    repo_root = args.repo_root.expanduser().resolve()
    patch_model_registry(repo_root)
    patch_model_manager_view(repo_root)
    patch_ai_orchestrator(repo_root)
    patch_pbxproj(repo_root)
    print("Applied ANEMLL runtime patches successfully.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
