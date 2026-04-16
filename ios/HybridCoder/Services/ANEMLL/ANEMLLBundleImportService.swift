import Foundation

@MainActor
final class ANEMLLBundleImportService {
    struct ImportedBundle: Sendable {
        let bundleID: String
        let displayName: String
        let modelRoot: URL
        let manifest: ANEMLLModelPackageManifest?
    }

    enum ImportError: Error, LocalizedError {
        case missingMetaYAML
        case invalidSource(String)
        case unreadableManifest(String)

        var errorDescription: String? {
            switch self {
            case .missingMetaYAML:
                return "The imported ANEMLL model package does not contain meta.yaml at its root."
            case .invalidSource(let detail):
                return "The imported ANEMLL package is invalid: \(detail)"
            case .unreadableManifest(let detail):
                return "Could not decode the ANEMLL package manifest: \(detail)"
            }
        }
    }

    static let shared = ANEMLLBundleImportService()

    private let fileManager = FileManager.default
    private let importsRoot: URL

    init(importsRoot: URL? = nil) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.importsRoot = importsRoot
            ?? appSupport
                .appendingPathComponent("HybridCoder", isDirectory: true)
                .appendingPathComponent("ANEMLLBundles", isDirectory: true)
        try? fileManager.createDirectory(at: self.importsRoot, withIntermediateDirectories: true)
    }

    func importedBundles() -> [ImportedBundle] {
        guard let children = try? fileManager.contentsOfDirectory(
            at: importsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return children.compactMap { child in
            guard (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
                return nil
            }
            let manifest = try? loadManifest(at: child)
            return ImportedBundle(
                bundleID: child.lastPathComponent,
                displayName: manifest?.modelName ?? child.lastPathComponent,
                modelRoot: child,
                manifest: manifest
            )
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    @discardableResult
    func importBundle(from source: URL) throws -> ImportedBundle {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path(percentEncoded: false), isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ImportError.invalidSource("Expected a directory that contains an exported ANEMLL model package.")
        }

        let metaYAML = source.appendingPathComponent("meta.yaml")
        guard fileManager.fileExists(atPath: metaYAML.path(percentEncoded: false)) else {
            throw ImportError.missingMetaYAML
        }

        let manifest = try? loadManifest(at: source)
        let bundleID = sanitizeBundleID(manifest?.modelName ?? source.lastPathComponent)
        let destination = importsRoot.appendingPathComponent(bundleID, isDirectory: true)

        if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)

        return ImportedBundle(
            bundleID: bundleID,
            displayName: manifest?.modelName ?? bundleID,
            modelRoot: destination,
            manifest: manifest
        )
    }

    func manifestURL(for modelRoot: URL) -> URL {
        modelRoot.appendingPathComponent("model-package-manifest.json")
    }

    func loadManifest(at modelRoot: URL) throws -> ANEMLLModelPackageManifest? {
        let manifestURL = manifestURL(for: modelRoot)
        guard fileManager.fileExists(atPath: manifestURL.path(percentEncoded: false)) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: manifestURL)
            return try JSONDecoder().decode(ANEMLLModelPackageManifest.self, from: data)
        } catch {
            throw ImportError.unreadableManifest(error.localizedDescription)
        }
    }

    private func sanitizeBundleID(_ raw: String) -> String {
        let lowered = raw.lowercased()
        let mapped = lowered.map { character -> Character in
            if character.isLetter || character.isNumber {
                return character
            }
            return "-"
        }
        let joined = String(mapped)
        let collapsed = joined.replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
