import Foundation

nonisolated struct EmbeddingModelDescriptor: Sendable {
    let identifier: String
    let displayName: String
    let embeddingDimension: Int
    let maxTokenLength: Int
    let localPath: URL?

    var isAvailable: Bool {
        guard let path = localPath else { return false }
        return FileManager.default.fileExists(atPath: path.path)
    }

    static let codeBERT = EmbeddingModelDescriptor(
        identifier: "codebert-base",
        displayName: "CodeBERT Base",
        embeddingDimension: 768,
        maxTokenLength: 512,
        localPath: nil
    )

    func withLocalPath(_ url: URL) -> EmbeddingModelDescriptor {
        EmbeddingModelDescriptor(
            identifier: identifier,
            displayName: displayName,
            embeddingDimension: embeddingDimension,
            maxTokenLength: maxTokenLength,
            localPath: url
        )
    }
}
