import Foundation

struct ModelInfo: Identifiable {
    let id: String
    let name: String
    let description: String
    var status: DownloadStatus
    var progress: Double
    var downloadURL: URL?
    let sizeDescription: String

    enum DownloadStatus: String {
        case notDownloaded
        case downloading
        case downloaded
        case failed
        case extracting
    }

    static let qwenCoder = ModelInfo(
        id: "qwen2.5-coder-1.5b",
        name: "Qwen2.5-Coder 1.5B",
        description: "Code generation model for writing and completing code",
        status: .notDownloaded,
        progress: 0,
        downloadURL: nil,
        sizeDescription: "~1.2 GB"
    )

    static let codeBERT = ModelInfo(
        id: "codebert-base",
        name: "CodeBERT Base",
        description: "Code embeddings for semantic search over your repository",
        status: .notDownloaded,
        progress: 0,
        downloadURL: nil,
        sizeDescription: "~500 MB"
    )
}
