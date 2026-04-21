import Foundation
import OSLog

/// Canonical, single-source-of-truth resolver for on-device model files.
///
/// Callers ask "where is model X?" and receive a `ResolvedModelLocation`
/// regardless of whether the file was downloaded by the app or placed
/// manually in Files. This collapses the previously-overlapping worlds
/// ("downloaded by app" vs. "placed manually in Documents/Models") into
/// one contract.
///
/// Internally delegates to `ModelRegistry`'s existing search roots; over
/// time those helpers should become thin wrappers over this resolver.
nonisolated struct ResolvedModelLocation: Sendable, Equatable {
    let modelID: String
    let url: URL
    let sizeBytes: Int64?
    let lastVerified: Date

    enum Source: String, Sendable, Equatable {
        /// File was produced by `ModelDownloadService` or present in a known
        /// app-managed layout.
        case appManaged
        /// File was discovered in `Documents/Models/` without a corresponding
        /// download record — treated as user-placed.
        case userPlaced
    }

    let source: Source
}

@MainActor
final class ModelLocationResolver {
    private let registry: ModelRegistry
    private let logger = Logger(subsystem: "com.hybridcoder.app", category: "ModelLocationResolver")

    init(registry: ModelRegistry) {
        self.registry = registry
    }

    /// Resolve the on-disk location of the given model, if any.
    /// Returns `nil` when no matching file can be found in any known root.
    func locate(modelID: String) -> ResolvedModelLocation? {
        guard let entry = registry.entry(for: modelID),
              let file = entry.files.first else {
            return nil
        }

        let roots = ModelRegistry.candidateExternalModelsRoots()
        guard let url = ModelRegistry.resolveInstalledFile(named: file.localPath, roots: roots) else {
            return nil
        }

        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map { Int64($0) }
        let source: ResolvedModelLocation.Source = {
            // Files directly under the canonical external models root that
            // aren't tracked by a download record are treated as user-placed.
            let canonicalRoot = ModelRegistry.externalModelsRoot.standardizedFileURL.path(percentEncoded: false)
            let filePath = url.standardizedFileURL.path(percentEncoded: false)
            guard filePath.hasPrefix(canonicalRoot) else { return .appManaged }
            return .userPlaced
        }()

        return ResolvedModelLocation(
            modelID: modelID,
            url: url,
            sizeBytes: size,
            lastVerified: Date(),
            source: source
        )
    }

    /// Fast boolean check, for hot paths that just want "is it there?"
    func isLocated(modelID: String) -> Bool {
        locate(modelID: modelID) != nil
    }
}
