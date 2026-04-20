import Foundation

nonisolated struct CustomModelManifestEntry: Codable, Sendable, Identifiable {
    var id: String
    var displayName: String
    var capability: String
    var sourceKind: String
    var sourceURL: String
    var filename: String
    var huggingFaceRepo: String?
    var huggingFaceRevision: String?
    var sizeBytes: Int64?
    var downloadedAt: Date?
}

nonisolated struct CustomModelManifest: Codable, Sendable {
    var version: Int
    var entries: [CustomModelManifestEntry]
}

@MainActor
final class CustomModelStore {
    static let shared = CustomModelStore()

    private let manifestFilename = ".hybridcoder-models-manifest.json"

    private var manifestURL: URL {
        ModelRegistry.externalModelsRoot.appendingPathComponent(manifestFilename, isDirectory: false)
    }

    func load() -> CustomModelManifest {
        let url = manifestURL
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(CustomModelManifest.self, from: data) else {
            return CustomModelManifest(version: 1, entries: [])
        }
        return manifest
    }

    func save(_ manifest: CustomModelManifest) {
        let url = manifestURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(manifest) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func upsert(_ entry: CustomModelManifestEntry) {
        var manifest = load()
        if let idx = manifest.entries.firstIndex(where: { $0.id == entry.id }) {
            manifest.entries[idx] = entry
        } else {
            manifest.entries.append(entry)
        }
        save(manifest)
    }

    func remove(id: String) {
        var manifest = load()
        manifest.entries.removeAll { $0.id == id }
        save(manifest)
    }

    func buildRegistryEntry(from manifest: CustomModelManifestEntry) -> ModelRegistry.Entry? {
        guard let capability = ModelRegistry.Capability(rawValue: manifest.capability) else {
            return nil
        }
        let provider: ModelRegistry.Provider = manifest.huggingFaceRepo != nil ? .huggingFace : .customURL
        let file = ModelRegistry.ModelFile(remotePath: manifest.filename, localPath: manifest.filename)
        let baseURL: String? = {
            if manifest.huggingFaceRepo != nil {
                return URL(string: manifest.sourceURL)?.deletingLastPathComponent().absoluteString
            }
            return URL(string: manifest.sourceURL)?.deletingLastPathComponent().absoluteString
        }()
        return ModelRegistry.Entry(
            id: manifest.id,
            displayName: manifest.displayName,
            capability: capability,
            provider: provider,
            runtime: .llamaCppGGUF,
            remoteBaseURL: baseURL,
            files: [file],
            isAvailable: true,
            installState: .notInstalled,
            loadState: .unloaded
        )
    }

    func registerAll(into registry: ModelRegistry) {
        let manifest = load()
        for manifestEntry in manifest.entries {
            guard let entry = buildRegistryEntry(from: manifestEntry) else { continue }
            registry.registerCustomModel(entry)
        }
    }
}

nonisolated enum CustomModelInputParser {
    struct Resolved {
        let filename: String
        let downloadURL: String
        let repoID: String?
        let revision: String?
    }

    static func resolveDirectURL(_ raw: String) -> Resolved? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let host = url.host else { return nil }
        let filename = url.lastPathComponent
        guard !filename.isEmpty else { return nil }

        if host.contains("huggingface.co"),
           let parsed = parseHuggingFaceResolveURL(url) {
            return Resolved(
                filename: parsed.filename,
                downloadURL: trimmed,
                repoID: parsed.repoID,
                revision: parsed.revision
            )
        }

        return Resolved(filename: filename, downloadURL: trimmed, repoID: nil, revision: nil)
    }

    static func resolveHuggingFaceRepo(repoID: String, filename: String, revision: String?) -> Resolved? {
        let cleanedRepo = repoID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedFile = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedRevision = (revision?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "main"
        guard !cleanedRepo.isEmpty, !cleanedFile.isEmpty, cleanedRepo.contains("/") else { return nil }
        let url = "https://huggingface.co/\(cleanedRepo)/resolve/\(cleanedRevision)/\(cleanedFile)"
        return Resolved(
            filename: cleanedFile,
            downloadURL: url,
            repoID: cleanedRepo,
            revision: cleanedRevision
        )
    }

    private static func parseHuggingFaceResolveURL(_ url: URL) -> (repoID: String, revision: String, filename: String)? {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let resolveIdx = parts.firstIndex(of: "resolve"),
              resolveIdx >= 2,
              resolveIdx + 1 < parts.count else { return nil }
        let repo = "\(parts[resolveIdx - 2])/\(parts[resolveIdx - 1])"
        let revision = parts[resolveIdx + 1]
        let filename = parts.last ?? ""
        return (repo, revision, filename)
    }
}
