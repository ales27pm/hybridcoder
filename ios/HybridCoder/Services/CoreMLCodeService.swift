import Foundation
import CoreML

@Observable
@MainActor
final class CoreMLCodeService {
    var isModelLoaded: Bool = false
    var isGenerating: Bool = false
    private var qwenModel: MLModel?

    private let downloadService: ModelDownloadService

    init(downloadService: ModelDownloadService) {
        self.downloadService = downloadService
    }

    func loadQwenModel() async {
        let modelPath = downloadService.modelPath(for: "qwen2.5-coder-1.5b")
        guard FileManager.default.fileExists(atPath: modelPath.path) else { return }

        do {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine
            qwenModel = try await MLModel.load(contentsOf: modelPath, configuration: config)
            isModelLoaded = true
        } catch {
            isModelLoaded = false
        }
    }

    func generateCode(prompt: String, context: String) async -> String? {
        guard qwenModel != nil else { return nil }
        isGenerating = true
        defer { isGenerating = false }
        return nil
    }
}
