import Foundation
import OSLog

@Observable
@MainActor
final class ModelDownloadService {
    private enum TokenStore {
        static let huggingFaceTokenKey = "models.huggingface.token"
    }

    struct ProgressSnapshot: Sendable, Equatable {
        var progress: Double
        var bytesReceived: Int64
        var totalBytes: Int64
        var bytesPerSecond: Double
    }

    private(set) var isDownloading: Bool = false
    private(set) var downloadProgress: Double = 0
    private(set) var downloadError: String?
    private(set) var downloadErrorModelID: String?
    private(set) var shouldSuggestTokenInput: Bool = false

    private(set) var progressByModel: [String: ProgressSnapshot] = [:]
    private(set) var errorsByModel: [String: String] = [:]

    private var activeTasks: [String: URLSessionDownloadTask] = [:]
    private var taskDelegates: [String: DownloadTaskDelegate] = [:]
    private var resumeDataByModel: [String: Data] = [:]
    private var resolvedModelsRootOverride: URL?

    private let registry: ModelRegistry
    private let bookmarkService: BookmarkService
    private let locationResolver: ModelLocationResolver
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.hybridcoder",
        category: "ModelDownloadService"
    )

    init(registry: ModelRegistry, bookmarkService: BookmarkService = BookmarkService()) {
        self.registry = registry
        self.bookmarkService = bookmarkService
        self.locationResolver = ModelLocationResolver(registry: registry)
        BundledEmbeddingAssets.migrateFromDocumentsIfNeeded()
        try? registry.ensureExternalModelsDirectoryExists()
        try? registry.migrateLegacyExternalModelsIfNeeded()
        CustomModelStore.shared.registerAll(into: registry)
        Task { [weak self] in
            guard let self else { return }
            await self.refreshResolvedModelsRoot()
            await self.refreshAllInstallStates()
        }
    }

    var activeEmbeddingModelID: String {
        registry.activeEmbeddingModelID
    }

    var isModelReady: Bool {
        locationResolver.readiness(modelID: activeEmbeddingModelID, preferredRoot: resolvedModelsRootOverride).isReady
    }

    var huggingFaceToken: String {
        UserDefaults.standard.string(forKey: TokenStore.huggingFaceTokenKey) ?? ""
    }

    func setHuggingFaceToken(_ token: String) {
        let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            UserDefaults.standard.removeObject(forKey: TokenStore.huggingFaceTokenKey)
        } else {
            UserDefaults.standard.set(cleaned, forKey: TokenStore.huggingFaceTokenKey)
        }
        shouldSuggestTokenInput = false
        downloadError = nil
        downloadErrorModelID = nil
    }

    func totalDiskUsageBytes() -> Int64 {
        let fm = FileManager.default
        let root = resolvedModelsRoot()
        guard let contents = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for url in contents where url.pathExtension.lowercased() == "gguf" {
            if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    func fileSizeBytes(for modelID: String) -> Int64? {
        guard let entry = registry.entry(for: modelID),
              let file = entry.files.first else { return nil }
        let root = resolvedModelsRoot()
        guard let url = ModelRegistry.resolveInstalledFile(
            named: file.localPath,
            roots: ModelRegistry.candidateExternalModelsRoots(preferredRoot: root)
        ) else { return nil }
        return (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map { Int64($0) } ?? nil
    }

    func refreshAllInstallStates() async {
        for id in registry.entries.keys {
            await refreshInstallState(modelID: id)
        }
    }

    func refreshInstallState(modelID: String) async {
        do {
            try registry.ensureExternalModelsDirectoryExists()
        } catch {
            logger.error("Failed to prepare Models folder: \(error.localizedDescription, privacy: .private)")
        }
        let preferredRoot = await refreshResolvedModelsRoot()
        let readiness = locationResolver.readiness(modelID: modelID, preferredRoot: preferredRoot)
        let isReady = readiness.isReady
        registry.setInstallState(for: modelID, isReady ? .installed : .notInstalled)
        if isReady {
            errorsByModel[modelID] = nil
            if downloadErrorModelID == modelID {
                downloadError = nil
                downloadErrorModelID = nil
            }
        }
    }

    func downloadIfNeeded() async {
        if isModelReady { return }
        await download(modelID: activeEmbeddingModelID)
    }

    func download(modelID: String? = nil) async {
        let modelID = modelID ?? activeEmbeddingModelID
        guard let entry = registry.entry(for: modelID) else { return }
        guard activeTasks[modelID] == nil else { return }
        guard let file = entry.files.first else {
            errorsByModel[modelID] = "No remote download URL configured for this model."
            return
        }

        isDownloading = true
        downloadErrorModelID = nil
        downloadError = nil
        errorsByModel[modelID] = nil
        shouldSuggestTokenInput = false
        progressByModel[modelID] = ProgressSnapshot(progress: 0, bytesReceived: 0, totalBytes: 0, bytesPerSecond: 0)
        registry.setInstallState(for: modelID, .downloading(progress: 0))

        do {
            let targetRoot = try await withModelsFolderAccess { targetRoot in
                try self.registry.ensureExternalModelsDirectoryExists()
                let targetURL = targetRoot.appendingPathComponent(file.localPath, isDirectory: false)

                if FileManager.default.fileExists(atPath: targetURL.path(percentEncoded: false)) {
                    return targetRoot
                }

                let remoteURL = try await self.resolveRemoteDownloadURL(
                    modelID: modelID,
                    file: file,
                    preflightCheck: self.performAvailabilityCheck
                )

                try await self.performDownload(
                    modelID: modelID,
                    remoteURL: remoteURL,
                    targetURL: targetURL
                )

                return targetRoot
            }

            if registry.entry(for: modelID)?.installState != .installed {
                try await Self.validateDownloadedAssetsOrThrow(modelID: modelID, registry: registry, preferredRoot: targetRoot)
            }
            registry.setInstallState(for: modelID, .installed)
            errorsByModel[modelID] = nil

            if let manifest = CustomModelStore.shared.load().entries.first(where: { $0.id == modelID }) {
                var updated = manifest
                updated.sizeBytes = fileSizeBytes(for: modelID)
                updated.downloadedAt = Date()
                CustomModelStore.shared.upsert(updated)
            }
        } catch is CancellationError {
            errorsByModel[modelID] = "Download was cancelled."
            registry.setInstallState(for: modelID, .notInstalled)
        } catch let error as DownloadError {
            let message = error.localizedDescription
            errorsByModel[modelID] = message
            downloadError = message
            downloadErrorModelID = modelID
            shouldSuggestTokenInput = error.shouldSuggestHuggingFaceTokenInput
            registry.setInstallState(for: modelID, .notInstalled)
            logger.error("DownloadError modelID=\(modelID, privacy: .public) details=\(error.triageSummary, privacy: .private)")
        } catch {
            let message = error.localizedDescription
            errorsByModel[modelID] = message
            downloadError = message
            downloadErrorModelID = modelID
            registry.setInstallState(for: modelID, .notInstalled)
        }

        activeTasks[modelID] = nil
        taskDelegates[modelID] = nil
        isDownloading = !activeTasks.isEmpty
    }

    func pause(modelID: String) {
        guard let task = activeTasks[modelID] else { return }
        task.cancel { [weak self] data in
            guard let self else { return }
            Task { @MainActor in
                if let data {
                    self.resumeDataByModel[modelID] = data
                }
                self.activeTasks[modelID] = nil
                self.taskDelegates[modelID] = nil
                self.isDownloading = !self.activeTasks.isEmpty
                self.registry.setInstallState(for: modelID, .notInstalled)
            }
        }
    }

    func cancel(modelID: String) {
        activeTasks[modelID]?.cancel()
        activeTasks[modelID] = nil
        taskDelegates[modelID] = nil
        resumeDataByModel[modelID] = nil
        progressByModel[modelID] = nil
        registry.setInstallState(for: modelID, .notInstalled)
        isDownloading = !activeTasks.isEmpty
    }


    func resolveRemoteDownloadURL(
        modelID: String,
        file: ModelRegistry.ModelFile,
        preflightCheck: @Sendable (URL) async throws -> Void
    ) async throws -> URL {
        let candidateURLs = registry.remoteBaseURLCandidates(for: modelID).compactMap { baseURL -> URL? in
            URL(string: "\(baseURL)/\(file.remotePath)")
        }
        guard candidateURLs.isEmpty == false else {
            throw DownloadError.modelNotDownloaded("No remote download URL configured for this model.")
        }

        var lastError: DownloadError?
        for candidate in candidateURLs {
            do {
                try await preflightCheck(candidate)
                return candidate
            } catch let error as DownloadError {
                if case .httpError(statusCode: 404, _, _, _) = error {
                    lastError = error
                    continue
                }
                throw error
            } catch {
                throw DownloadError.networkFailure(error.localizedDescription)
            }
        }

        throw lastError ?? DownloadError.modelNotDownloaded("No remote download URL configured for this model.")
    }

    private func performAvailabilityCheck(remoteURL: URL) async throws {
        var request = URLRequest(url: remoteURL)
        request.httpMethod = "HEAD"
        if remoteURL.host?.contains("huggingface.co") == true {
            let token = huggingFaceToken.trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        }

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DownloadError.networkFailure("Invalid server response")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw DownloadError.httpError(
                statusCode: httpResponse.statusCode,
                remotePath: remoteURL.absoluteString,
                modelID: nil,
                repoBaseURL: remoteURL.deletingLastPathComponent().absoluteString
            )
        }
    }

    private func performDownload(modelID: String, remoteURL: URL, targetURL: URL) async throws {
        let session = URLSession(configuration: .default)
        defer { session.finishTasksAndInvalidate() }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let delegate = DownloadTaskDelegate(
                modelID: modelID,
                targetURL: targetURL,
                securityScopedDirectoryURL: nil,
                continuation: continuation
            ) { [weak self] snapshot in
                guard let self else { return }
                Task { @MainActor in
                    self.progressByModel[modelID] = snapshot
                    self.registry.setInstallState(for: modelID, .downloading(progress: snapshot.progress))
                }
            }

            self.taskDelegates[modelID] = delegate

            let delegateSession = URLSession(
                configuration: .default,
                delegate: delegate,
                delegateQueue: nil
            )

            let task: URLSessionDownloadTask
            if let resumeData = self.resumeDataByModel[modelID] {
                task = delegateSession.downloadTask(withResumeData: resumeData)
                self.resumeDataByModel[modelID] = nil
            } else {
                var request = URLRequest(url: remoteURL)
                if remoteURL.host?.contains("huggingface.co") == true {
                    let token = huggingFaceToken.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !token.isEmpty {
                        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    }
                }
                task = delegateSession.downloadTask(with: request)
            }

            delegate.session = delegateSession
            self.activeTasks[modelID] = task
            task.resume()
        }
    }

    func deleteDownloadedModels(modelID: String? = nil) async {
        let modelID = modelID ?? activeEmbeddingModelID
        cancel(modelID: modelID)
        guard let entry = registry.entry(for: modelID), let file = entry.files.first else {
            registry.setInstallState(for: modelID, .notInstalled)
            registry.setLoadState(for: modelID, .unloaded)
            return
        }
        await withModelsFolderAccess { targetRoot in
            let url = targetRoot.appendingPathComponent(file.localPath, isDirectory: false)
            try? FileManager.default.removeItem(at: url)
        }
        registry.deleteCodeGenerationModelAssets(modelID: modelID)
        registry.setInstallState(for: modelID, .notInstalled)
        registry.setLoadState(for: modelID, .unloaded)
        progressByModel[modelID] = nil
        errorsByModel[modelID] = nil
        if downloadErrorModelID == modelID {
            downloadError = nil
            downloadErrorModelID = nil
        }
    }

    func downloadError(for modelID: String) -> String? {
        errorsByModel[modelID]
    }

    func progressSnapshot(for modelID: String) -> ProgressSnapshot? {
        progressByModel[modelID]
    }

    func isActivelyDownloading(modelID: String) -> Bool {
        activeTasks[modelID] != nil
    }

    // MARK: - Custom models

    @discardableResult
    func addCustomModel(
        displayName: String,
        capability: ModelRegistry.Capability,
        resolved: CustomModelInputParser.Resolved
    ) -> ModelRegistry.Entry? {
        let id = resolved.filename
        guard URL(string: resolved.downloadURL) != nil else { return nil }
        let baseURL = URL(string: resolved.downloadURL)?.deletingLastPathComponent().absoluteString
        let provider: ModelRegistry.Provider = resolved.repoID != nil ? .huggingFace : .customURL
        let entry = ModelRegistry.Entry(
            id: id,
            displayName: displayName.isEmpty ? resolved.filename : displayName,
            capability: capability,
            provider: provider,
            runtime: .llamaCppGGUF,
            remoteBaseURL: baseURL,
            files: [ModelRegistry.ModelFile(remotePath: resolved.filename, localPath: resolved.filename)],
            isAvailable: true,
            installState: .notInstalled,
            loadState: .unloaded
        )
        registry.registerCustomModel(entry)

        CustomModelStore.shared.upsert(CustomModelManifestEntry(
            id: id,
            displayName: entry.displayName,
            capability: capability.rawValue,
            sourceKind: resolved.repoID != nil ? "huggingface" : "directURL",
            sourceURL: resolved.downloadURL,
            filename: resolved.filename,
            huggingFaceRepo: resolved.repoID,
            huggingFaceRevision: resolved.revision,
            sizeBytes: nil,
            downloadedAt: nil
        ))
        Task { await refreshInstallState(modelID: id) }
        return entry
    }

    func removeCustomModel(id: String) async {
        await deleteDownloadedModels(modelID: id)
        CustomModelStore.shared.remove(id: id)
        registry.removeCustomModel(id: id)
        progressByModel[id] = nil
        errorsByModel[id] = nil
    }

    func isBuiltIn(modelID: String) -> Bool {
        modelID == ModelRegistry.defaultEmbeddingModelID ||
        modelID == ModelRegistry.sharedQwenArtifactFilename ||
        modelID == ModelRegistry.defaultCodeGenerationModelID ||
        modelID == ModelRegistry.defaultGenerationModelID
    }

    private static func isInvalidGGUFPayload(at url: URL) async -> Bool {
        await Task.detached(priority: .utility) {
            guard let handle = try? FileHandle(forReadingFrom: url) else { return true }
            defer { try? handle.close() }
            guard let prefix = try? handle.read(upToCount: 1024), !prefix.isEmpty else { return true }

            if let text = String(data: prefix, encoding: .utf8)?.lowercased(),
               text.contains("<html") || text.contains("<!doctype html") {
                return true
            }

            let ggufMagic = Data([0x47, 0x47, 0x55, 0x46])
            guard prefix.count >= ggufMagic.count else { return true }
            return !prefix.starts(with: ggufMagic)
        }.value
    }

    static func validateDownloadedAssets(modelID: String, registry: ModelRegistry) async -> Bool {
        do {
            try await validateDownloadedAssetsOrThrow(modelID: modelID, registry: registry)
            return true
        } catch {
            return false
        }
    }

    private static func validateDownloadedAssetsOrThrow(
        modelID: String,
        registry: ModelRegistry,
        preferredRoot: URL? = nil
    ) async throws {
        guard let entry = registry.entry(for: modelID) else {
            throw DownloadError.fileCorrupt("Missing model registry entry for \(modelID)")
        }
        let fm = FileManager.default
        for expectedFile in entry.files {
            guard let url = ModelRegistry.resolveInstalledFile(
                named: expectedFile.localPath,
                roots: ModelRegistry.candidateExternalModelsRoots(preferredRoot: preferredRoot)
            ),
            fm.fileExists(atPath: url.path(percentEncoded: false)) else {
                throw DownloadError.fileCorrupt(expectedFile.localPath)
            }
            if await isInvalidGGUFPayload(at: url) {
                try? fm.removeItem(at: url)
                throw DownloadError.fileCorrupt("Invalid GGUF artifact: \(expectedFile.localPath)")
            }
        }
    }

    private func resolvedModelsRoot() -> URL {
        registry.preferredExternalModelsRoot(preferredRoot: resolvedModelsRootOverride)
    }

    private func withModelsFolderAccess<T>(
        _ operation: (URL) async throws -> T
    ) async rethrows -> T {
        let preferredRoot = await refreshResolvedModelsRoot()
        let didAccessScopedResource = preferredRoot.startAccessingSecurityScopedResource()
        defer {
            if didAccessScopedResource {
                preferredRoot.stopAccessingSecurityScopedResource()
            }
        }
        return try await operation(preferredRoot)
    }

    private func refreshResolvedModelsRoot() async -> URL {
        let preferredRoot = await bookmarkService.resolveModelsFolderBookmark()
        resolvedModelsRootOverride = preferredRoot
        return registry.preferredExternalModelsRoot(preferredRoot: preferredRoot)
    }

    nonisolated enum DownloadError: Error, LocalizedError, Sendable {
        case modelNotDownloaded(String)
        case httpError(statusCode: Int, remotePath: String, modelID: String?, repoBaseURL: String?)
        case fileCorrupt(String)
        case networkFailure(String)

        nonisolated var isAuthorizationError: Bool {
            if case .httpError(statusCode: let code, _, _, _) = self {
                return code == 401 || code == 403
            }
            return false
        }

        nonisolated var shouldSuggestHuggingFaceTokenInput: Bool {
            isAuthorizationError && isHuggingFaceRepository
        }

        nonisolated var isHuggingFaceRepository: Bool {
            guard case .httpError(_, _, _, let repoBaseURL) = self,
                  let repoBaseURL,
                  let host = URL(string: repoBaseURL)?.host?.lowercased() else {
                return false
            }
            return host == "huggingface.co" || host.hasSuffix(".huggingface.co")
        }

        nonisolated var triageSummary: String {
            switch self {
            case .modelNotDownloaded(let details):
                return "modelNotDownloaded: \(details)"
            case .httpError(let code, let remotePath, let modelID, let repoBaseURL):
                return "httpError status=\(code) remotePath=\(remotePath) modelID=\(modelID ?? "nil") repoBaseURL=\(repoBaseURL ?? "nil")"
            case .fileCorrupt(let file):
                return "fileCorrupt: \(file)"
            case .networkFailure(let details):
                return "networkFailure: \(details)"
            }
        }

        nonisolated var errorDescription: String? {
            switch self {
            case .modelNotDownloaded(let details):
                return details
            case .httpError(let code, let file, _, _):
                if code == 404 {
                    return "File not found (HTTP 404): \(file). Double-check the URL or filename."
                }
                if code == 401 || code == 403 {
                    if shouldSuggestHuggingFaceTokenInput {
                        return "Access denied (HTTP \(code)). Add a valid Hugging Face token and retry."
                    }
                    return "Access denied (HTTP \(code)) downloading \(file)."
                }
                if (500...599).contains(code) {
                    return "Server error (HTTP \(code)) downloading \(file). Try again in a moment."
                }
                return "HTTP \(code) downloading \(file)."
            case .fileCorrupt(let file):
                return "Downloaded file '\(file)' appears corrupt and was removed. Tap Retry to download again."
            case .networkFailure(let message):
                return "Network error: \(message)"
            }
        }
    }
}

// MARK: - URLSession delegate

private final class DownloadTaskDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let modelID: String
    let targetURL: URL
    let securityScopedDirectoryURL: URL?
    private let continuation: CheckedContinuation<Void, Error>
    private let onProgress: @Sendable (ModelDownloadService.ProgressSnapshot) -> Void
    private var didFinish = false
    private var startedAt: Date = Date()
    weak var session: URLSession?

    init(
        modelID: String,
        targetURL: URL,
        securityScopedDirectoryURL: URL?,
        continuation: CheckedContinuation<Void, Error>,
        onProgress: @escaping @Sendable (ModelDownloadService.ProgressSnapshot) -> Void
    ) {
        self.modelID = modelID
        self.targetURL = targetURL
        self.securityScopedDirectoryURL = securityScopedDirectoryURL
        self.continuation = continuation
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let progress: Double
        if totalBytesExpectedToWrite > 0 {
            progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        } else {
            progress = 0
        }
        let elapsed = max(Date().timeIntervalSince(startedAt), 0.001)
        let bps = Double(totalBytesWritten) / elapsed
        onProgress(ModelDownloadService.ProgressSnapshot(
            progress: progress,
            bytesReceived: totalBytesWritten,
            totalBytes: totalBytesExpectedToWrite,
            bytesPerSecond: bps
        ))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard !didFinish else { return }
        didFinish = true

        if let httpResponse = downloadTask.response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            let remote = downloadTask.originalRequest?.url?.absoluteString ?? ""
            let baseURL = downloadTask.originalRequest?.url?.deletingLastPathComponent().absoluteString
            continuation.resume(throwing: ModelDownloadService.DownloadError.httpError(
                statusCode: httpResponse.statusCode,
                remotePath: remote,
                modelID: modelID,
                repoBaseURL: baseURL
            ))
            session.finishTasksAndInvalidate()
            return
        }

        do {
            let finalizedURL = try finalizeDownload(tempURL: location, fileName: targetURL.lastPathComponent)
            if finalizedURL.standardizedFileURL != targetURL.standardizedFileURL {
                continuation.resume(throwing: ModelDownloadService.DownloadError.networkFailure("Model destination mismatch during finalization."))
            } else {
                continuation.resume(returning: ())
            }
        } catch {
            continuation.resume(throwing: ModelDownloadService.DownloadError.networkFailure(error.localizedDescription))
        }
        session.finishTasksAndInvalidate()
    }

    private func finalizeDownload(tempURL: URL, fileName: String) throws -> URL {
        let destination = ModelPaths.root.appendingPathComponent(fileName, isDirectory: false)
        let fm = FileManager.default

        if let scopedURL = securityScopedDirectoryURL {
            let didAccess = scopedURL.startAccessingSecurityScopedResource()
            defer {
                if didAccess { scopedURL.stopAccessingSecurityScopedResource() }
            }
            try fm.createDirectory(at: ModelPaths.root, withIntermediateDirectories: true)
            if fm.fileExists(atPath: destination.path(percentEncoded: false)) {
                try fm.removeItem(at: destination)
            }
            try fm.copyItem(at: tempURL, to: destination)
            return destination
        }

        try fm.createDirectory(at: ModelPaths.root, withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path(percentEncoded: false)) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: tempURL, to: destination)
        return destination
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !didFinish, let error else { return }
        didFinish = true
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            continuation.resume(throwing: CancellationError())
        } else {
            continuation.resume(throwing: ModelDownloadService.DownloadError.networkFailure(error.localizedDescription))
        }
        session.finishTasksAndInvalidate()
    }
}
