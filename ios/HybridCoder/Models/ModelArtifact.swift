import Foundation

nonisolated enum ArtifactKind: String, Codable, Sendable {
    case gguf
    case metadata
    case tokenizer
}

nonisolated enum ArtifactValidationPhase: String, Sendable {
    case availability
}

nonisolated struct ModelArtifact: Identifiable, Sendable {
    let id: String
    let displayName: String
    let modelsRootPath: String
    let remoteBaseURL: String?
    let requiredFiles: [RequiredFile]

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
        requiredFiles.filter { $0.kind == .gguf }
    }

    var tokenizerFiles: [RequiredFile] {
        requiredFiles.filter { $0.kind == .tokenizer }
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
    static func embeddingArtifact() -> ModelArtifact {
        let modelID = "jina-embeddings-v3-Q4_K_M.gguf"

        return ModelArtifact(
            id: modelID,
            displayName: "jina-embeddings-v3 (Q4_K_M)",
            modelsRootPath: "Hybrid Coder/Models",
            remoteBaseURL: nil,
            requiredFiles: [
                .init(remotePath: modelID, localPath: modelID, kind: .gguf)
            ]
        )
    }

    static func foundationModelArtifact() -> ModelArtifact {
        let modelID = ModelRegistry.defaultGenerationModelID

        return ModelArtifact(
            id: modelID,
            displayName: "Qwen2.5-Coder 3B Orchestration (Q5_K_M)",
            modelsRootPath: "Hybrid Coder/Models",
            remoteBaseURL: nil,
            requiredFiles: [
                .init(remotePath: modelID, localPath: modelID, kind: .gguf)
            ]
        )
    }

    static func qwenCoderArtifact() -> ModelArtifact {
        let modelID = "Qwen2.5-Coder-3B-Instruct-abliterated-Q5_K_M.gguf"

        return ModelArtifact(
            id: modelID,
            displayName: "Qwen2.5-Coder 3B Instruct (Q5_K_M)",
            modelsRootPath: "Hybrid Coder/Models",
            remoteBaseURL: nil,
            requiredFiles: [
                .init(remotePath: modelID, localPath: modelID, kind: .gguf)
            ]
        )
    }
}
