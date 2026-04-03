import Foundation

@Observable
@MainActor
final class ModelDownloadService {
    var models: [ModelInfo] = [.qwenCoder, .codeBERT]
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]

    private var modelsDirectory: URL {
        let docs = URL.documentsDirectory
        let dir = docs.appendingPathComponent("CoreMLModels", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func modelPath(for modelId: String) -> URL {
        modelsDirectory.appendingPathComponent(modelId + ".mlmodelc", isDirectory: true)
    }

    func isModelDownloaded(_ modelId: String) -> Bool {
        FileManager.default.fileExists(atPath: modelPath(for: modelId).path)
    }

    func checkDownloadedModels() {
        for i in models.indices {
            if isModelDownloaded(models[i].id) {
                models[i].status = .downloaded
                models[i].progress = 1.0
            }
        }
    }

    func setDownloadURL(for modelId: String, url: URL) {
        guard let index = models.firstIndex(where: { $0.id == modelId }) else { return }
        models[index].downloadURL = url
    }

    func downloadModel(_ modelId: String) async {
        guard let index = models.firstIndex(where: { $0.id == modelId }),
              let downloadURL = models[index].downloadURL else { return }

        models[index].status = .downloading
        models[index].progress = 0

        do {
            let delegate = DownloadProgressDelegate { [weak self] progress in
                Task { @MainActor in
                    guard let self,
                          let idx = self.models.firstIndex(where: { $0.id == modelId }) else { return }
                    self.models[idx].progress = progress
                }
            }

            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            let (tempURL, response) = try await session.download(from: downloadURL)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                models[index].status = .failed
                return
            }

            models[index].status = .extracting

            let destination = modelPath(for: modelId)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: tempURL, to: destination)

            models[index].status = .downloaded
            models[index].progress = 1.0
        } catch {
            if let idx = models.firstIndex(where: { $0.id == modelId }) {
                models[idx].status = .failed
            }
        }
    }

    func cancelDownload(_ modelId: String) {
        downloadTasks[modelId]?.cancel()
        downloadTasks.removeValue(forKey: modelId)
        if let index = models.firstIndex(where: { $0.id == modelId }) {
            models[index].status = .notDownloaded
            models[index].progress = 0
        }
    }

    func deleteModel(_ modelId: String) {
        let path = modelPath(for: modelId)
        try? FileManager.default.removeItem(at: path)
        if let index = models.firstIndex(where: { $0.id == modelId }) {
            models[index].status = .notDownloaded
            models[index].progress = 0
        }
    }
}

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let onProgress: (Double) -> Void

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        onProgress(progress)
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {}
}
