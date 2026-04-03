import Foundation

nonisolated enum BundledEmbeddingAssets: Sendable {

    nonisolated enum AssetError: Error, Sendable, CustomStringConvertible {
        case modelDirectoryNotFound(name: String)
        case compiledModelNotFound(directory: URL)
        case tokenizerDirectoryNotFound(name: String)
        case noTokenizerFilesFound(directory: URL)

        var description: String {
            switch self {
            case .modelDirectoryNotFound(let name):
                return "Embedding model directory '\(name)' not found in app bundle"
            case .compiledModelNotFound(let directory):
                return "No compiled CoreML model (.mlmodelc) found in \(directory.lastPathComponent)"
            case .tokenizerDirectoryNotFound(let name):
                return "Tokenizer directory '\(name)' not found in app bundle"
            case .noTokenizerFilesFound(let directory):
                return "No tokenizer files (tokenizer.json, vocab.txt, or vocab.json) found in \(directory.lastPathComponent)"
            }
        }
    }

    private static let modelDirectoryName = "codebert-base-coreml"
    private static let tokenizerDirectoryName = "codebert-base-tokenizer"
    private static let embeddingModelsFolder = "EmbeddingModels"

    private static let acceptedTokenizerFiles = [
        "tokenizer.json",
        "vocab.txt",
        "vocab.json"
    ]

    private static let compiledModelExtension = "mlmodelc"

    static func locateModelAsset() throws -> URL {
        let bundle = Bundle.main

        let searchPaths: [URL?] = [
            bundle.url(forResource: modelDirectoryName, withExtension: nil, subdirectory: embeddingModelsFolder),
            bundle.url(forResource: modelDirectoryName, withExtension: nil),
            bundle.resourceURL?.appendingPathComponent(embeddingModelsFolder).appendingPathComponent(modelDirectoryName)
        ]

        guard let modelDir = searchPaths.compactMap({ $0 }).first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) else {
            throw AssetError.modelDirectoryNotFound(name: modelDirectoryName)
        }

        let compiledModel = try findCompiledModel(in: modelDir)
        return compiledModel
    }

    static func locateTokenizerAssets() throws -> URL {
        let bundle = Bundle.main

        let searchPaths: [URL?] = [
            bundle.url(forResource: tokenizerDirectoryName, withExtension: nil, subdirectory: embeddingModelsFolder),
            bundle.url(forResource: tokenizerDirectoryName, withExtension: nil),
            bundle.resourceURL?.appendingPathComponent(embeddingModelsFolder).appendingPathComponent(tokenizerDirectoryName)
        ]

        guard let tokenizerDir = searchPaths.compactMap({ $0 }).first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) else {
            throw AssetError.tokenizerDirectoryNotFound(name: tokenizerDirectoryName)
        }

        try validateTokenizerFiles(in: tokenizerDir)
        return tokenizerDir
    }

    static func resolveDescriptor() -> EmbeddingModelDescriptor {
        let modelURL: URL? = try? locateModelAsset()
        return EmbeddingModelDescriptor.codeBERT.withLocalPath(modelURL ?? URL(fileURLWithPath: "/dev/null"))
    }

    static func validateAll() throws -> EmbeddingModelDescriptor {
        let modelURL = try locateModelAsset()
        let _ = try locateTokenizerAssets()
        return EmbeddingModelDescriptor.codeBERT.withLocalPath(modelURL)
    }

    private static func findCompiledModel(in directory: URL) throws -> URL {
        let fm = FileManager.default

        if directory.pathExtension == compiledModelExtension, fm.fileExists(atPath: directory.path) {
            return directory
        }

        let directoryModel = directory.appendingPathComponent("model.\(compiledModelExtension)")
        if fm.fileExists(atPath: directoryModel.path) {
            return directoryModel
        }

        let contents = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        if let compiled = contents.first(where: { $0.pathExtension == compiledModelExtension }) {
            return compiled
        }

        throw AssetError.compiledModelNotFound(directory: directory)
    }

    private static func validateTokenizerFiles(in directory: URL) throws {
        let fm = FileManager.default

        let contents = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        if contents.isEmpty {
            throw AssetError.noTokenizerFilesFound(directory: directory)
        }

        let hasAcceptedFile = acceptedTokenizerFiles.contains { fileName in
            fm.fileExists(atPath: directory.appendingPathComponent(fileName).path)
        }

        guard hasAcceptedFile else {
            throw AssetError.noTokenizerFilesFound(directory: directory)
        }
    }
}
