import Foundation

nonisolated enum ArtifactKind: String, Codable, Sendable {
    case mlpackage
    case mlmodelc
    case tokenizer
}

nonisolated enum ArtifactValidationPhase: String, Sendable {
    case preCompile
    case postCompile
}

nonisolated struct ModelArtifact: Identifiable, Sendable {
    let id: String
    let displayName: String
    let packageRootPath: String
    let tokenizerRootPath: String
    let remoteBaseURL: String?
    let requiredFiles: [RequiredFile]
    let supportsLocalCompilation: Bool

    nonisolated struct RequiredFile: Hashable, Sendable {
        let remotePath: String
        let localPath: String
        let kind: ArtifactKind
        let isValidatable: Bool

        init(remotePath: String, localPath: String, kind: ArtifactKind, isValidatable: Bool = false) {
            self.remotePath = remotePath
            self.localPath = localPath
            self.kind = kind
            self.isValidatable = isValidatable
        }
    }

    var modelFiles: [RequiredFile] {
        requiredFiles.filter { $0.kind == .mlpackage || $0.kind == .mlmodelc }
    }

    var tokenizerFiles: [RequiredFile] {
        requiredFiles.filter { $0.kind == .tokenizer }
    }

    var hasPackageSource: Bool {
        requiredFiles.contains { $0.kind == .mlpackage }
    }
}

nonisolated struct ArtifactValidationResult: Sendable {
    let phase: ArtifactValidationPhase
    let isValid: Bool
    let missingFiles: [String]
    let corruptFiles: [String]

    var summary: String {
        if isValid { return "Validation passed (\(phase.rawValue))" }
        var parts: [String] = []
        if !missingFiles.isEmpty { parts.append("Missing: \(missingFiles.joined(separator: ", "))") }
        if !corruptFiles.isEmpty { parts.append("Corrupt: \(corruptFiles.joined(separator: ", "))") }
        return "\(phase.rawValue) failed — \(parts.joined(separator: "; "))"
    }
}

nonisolated enum ModelArtifactFactory {
    static func codeBERTArtifact(remoteBaseURL: String) -> ModelArtifact {
        return ModelArtifact(
            id: "microsoft/codebert-base",
            displayName: "CodeBERT (rsvalerio/codebert-base-coreml)",
            packageRootPath: "model.mlpackage",
            tokenizerRootPath: "tokenizer",
            remoteBaseURL: remoteBaseURL,
            requiredFiles: [
                .init(remotePath: "model.mlpackage/Manifest.json", localPath: "model.mlpackage/Manifest.json", kind: .mlpackage, isValidatable: true),
                .init(remotePath: "model.mlpackage/Data/com.apple.CoreML/model.mlmodel", localPath: "model.mlpackage/Data/com.apple.CoreML/model.mlmodel", kind: .mlpackage),
                .init(remotePath: "model.mlpackage/Data/com.apple.CoreML/weights/weight.bin", localPath: "model.mlpackage/Data/com.apple.CoreML/weights/weight.bin", kind: .mlpackage),
                .init(remotePath: "tokenizer.json", localPath: "tokenizer.json", kind: .tokenizer, isValidatable: true),
                .init(remotePath: "tokenizer_config.json", localPath: "tokenizer_config.json", kind: .tokenizer, isValidatable: true),
                .init(remotePath: "special_tokens_map.json", localPath: "special_tokens_map.json", kind: .tokenizer, isValidatable: true),
            ],
            supportsLocalCompilation: true
        )
    }

    static func foundationModelArtifact() -> ModelArtifact {
        return ModelArtifact(
            id: "apple/foundation-language-model",
            displayName: "Apple Foundation Models",
            packageRootPath: "",
            tokenizerRootPath: "",
            remoteBaseURL: nil,
            requiredFiles: [],
            supportsLocalCompilation: false
        )
    }

    static func qwenCoderArtifact() -> ModelArtifact {
        let compiledModelFolder = "Qwen2.5-Coder-1.5B-Instruct-4bit.mlmodelc"

        return ModelArtifact(
            id: "finnvoorhees/coreml-Qwen2.5-Coder-1.5B-Instruct-4bit",
            displayName: "Qwen2.5-Coder 1.5B Instruct (4-bit)",
            packageRootPath: compiledModelFolder,
            tokenizerRootPath: "",
            remoteBaseURL: "https://huggingface.co/finnvoorhees/coreml-Qwen2.5-Coder-1.5B-Instruct-4bit/resolve/main",
            requiredFiles: [
                .init(remotePath: "\(compiledModelFolder)/analytics/coremldata.bin", localPath: "\(compiledModelFolder)/analytics/coremldata.bin", kind: .mlmodelc),
                .init(remotePath: "\(compiledModelFolder)/coremldata.bin", localPath: "\(compiledModelFolder)/coremldata.bin", kind: .mlmodelc),
                .init(remotePath: "\(compiledModelFolder)/metadata.json", localPath: "\(compiledModelFolder)/metadata.json", kind: .mlmodelc, isValidatable: true),
                .init(remotePath: "\(compiledModelFolder)/model.mil", localPath: "\(compiledModelFolder)/model.mil", kind: .mlmodelc),
                .init(remotePath: "\(compiledModelFolder)/weights/weight.bin", localPath: "\(compiledModelFolder)/weights/weight.bin", kind: .mlmodelc),
                .init(remotePath: "config.json", localPath: "config.json", kind: .tokenizer, isValidatable: true),
                .init(remotePath: "tokenizer.json", localPath: "tokenizer.json", kind: .tokenizer, isValidatable: true),
                .init(remotePath: "tokenizer_config.json", localPath: "tokenizer_config.json", kind: .tokenizer, isValidatable: true),
            ],
            supportsLocalCompilation: false
        )
    }
}
