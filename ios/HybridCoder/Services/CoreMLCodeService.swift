import Foundation
import CoreML

@Observable
@MainActor
final class CoreMLCodeService {
    var isModelLoaded: Bool = false
    var isGenerating: Bool = false
    private var qwenModel: MLModel?
    private var codeBERTModel: MLModel?

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

    func loadCodeBERTModel() async {
        let modelPath = downloadService.modelPath(for: "codebert-base")
        guard FileManager.default.fileExists(atPath: modelPath.path) else { return }

        do {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine
            codeBERTModel = try await MLModel.load(contentsOf: modelPath, configuration: config)
        } catch {
            // CodeBERT load failure is non-fatal
        }
    }

    func generateCode(prompt: String, context: String) async -> String? {
        guard qwenModel != nil else { return nil }
        isGenerating = true
        defer { isGenerating = false }

        // Placeholder for actual CoreML inference pipeline
        // The real implementation will tokenize the prompt,
        // run inference on the Qwen model, and decode the output
        return nil
    }

    func computeEmbedding(for text: String) async -> [Float]? {
        guard codeBERTModel != nil else { return nil }

        // Placeholder for actual CodeBERT inference
        // The real implementation will tokenize the text,
        // run through CodeBERT, and return the [CLS] token embedding
        return nil
    }

    func computeSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        return denom > 0 ? dot / denom : 0
    }
}
