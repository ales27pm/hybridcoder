import Foundation
import CoreML

actor CoreMLEmbeddingService {

    private let modelID: String
    private let registry: ModelRegistry

    nonisolated enum EmbeddingError: Error, LocalizedError, Sendable {
        case modelNotLoaded
        case tokenizerNotLoaded
        case inferenceFailure(String)
        case outputMissing(String)
        case dimensionMismatch(expected: Int, got: Int)
        case modelArtifactsMissing(cacheRoot: String, compiledPath: String, packagePath: String)
        case modelCompilationFailed(packagePath: String, detail: String)
        case compiledModelPersistenceFailed(compiledPath: String, detail: String)

        nonisolated var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                return "CoreML embedding model is not loaded."
            case .tokenizerNotLoaded:
                return "Tokenizer is not loaded."
            case .inferenceFailure(let detail):
                return "Embedding inference failed: \(detail)"
            case .outputMissing(let name):
                return "Expected output '\(name)' not found in model prediction."
            case .dimensionMismatch(let expected, let got):
                return "Embedding dimension mismatch: expected \(expected), got \(got)."
            case .modelArtifactsMissing(let cacheRoot, let compiledPath, let packagePath):
                return "No model artifacts found for '\(cacheRoot)'. Expected compiled model at '\(compiledPath)' or package at '\(packagePath)'."
            case .modelCompilationFailed(let packagePath, let detail):
                return "Failed to compile model package at '\(packagePath)': \(detail)"
            case .compiledModelPersistenceFailed(let compiledPath, let detail):
                return "Failed to persist compiled model to '\(compiledPath)': \(detail)"
            }
        }
    }

    nonisolated struct ModelInfo: Sendable {
        let inputNames: [String]
        let outputNames: [String]
        let embeddingDimension: Int
        let maxSequenceLength: Int
    }

    private var model: MLModel?
    private let tokenizer = HFTokenizer()
    private var tokenizerLoaded: Bool = false
    private var cachedModelInfo: ModelInfo?

    init(modelID: String, registry: ModelRegistry) {
        self.modelID = modelID
        self.registry = registry
    }

    private let maxSequenceLength = 512
    private let embeddingDimension = 768

    var isLoaded: Bool {
        model != nil && tokenizerLoaded
    }

    var modelInfo: ModelInfo? {
        cachedModelInfo
    }

    func load() async throws {
        await MainActor.run {
            registry.setLoadState(for: modelID, .loading)
        }

        let modelPaths = await MainActor.run {
            let cacheRoot = registry.downloadedModelDirectory(for: modelID)
            let compiled = cacheRoot.appendingPathComponent("model.mlmodelc", isDirectory: true)
            let package = cacheRoot.appendingPathComponent("model.mlpackage", isDirectory: true)
            return (cacheRoot: cacheRoot, compiled: compiled, package: package)
        }
        let tokenizerURL = await MainActor.run {
            registry.downloadedTokenizerDirectory(for: modelID)
        }

        do {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine

            let compiledModelURL = try ensureCompiledModel(
                cacheRoot: modelPaths.cacheRoot,
                compiledURL: modelPaths.compiled,
                packageURL: modelPaths.package
            )

            let loadedModel = try await MLModel.load(contentsOf: compiledModelURL, configuration: config)
            self.model = loadedModel

            try await tokenizer.load(from: tokenizerURL)
            tokenizerLoaded = true

            let inputNames = loadedModel.modelDescription.inputDescriptionsByName.keys.sorted()
            let outputNames = loadedModel.modelDescription.outputDescriptionsByName.keys.sorted()

            var detectedDimension = embeddingDimension
            for (_, desc) in loadedModel.modelDescription.outputDescriptionsByName {
                if let constraint = desc.multiArrayConstraint {
                    let shape = constraint.shape.map { $0.intValue }
                    if let last = shape.last, last > 1 {
                        detectedDimension = last
                        break
                    }
                }
            }

            cachedModelInfo = ModelInfo(
                inputNames: Array(inputNames),
                outputNames: Array(outputNames),
                embeddingDimension: detectedDimension,
                maxSequenceLength: maxSequenceLength
            )

            await MainActor.run {
                registry.setLoadState(for: modelID, .loaded)
            }
        } catch {
            await MainActor.run {
                registry.setLoadState(for: modelID, .failed(error.localizedDescription))
            }
            throw error
        }
    }

    private func ensureCompiledModel(
        cacheRoot: URL,
        compiledURL: URL,
        packageURL: URL
    ) throws -> URL {
        let fm = FileManager.default
        let hasCompiled = fm.fileExists(atPath: compiledURL.path)
        if hasCompiled {
            return compiledURL
        }

        let hasPackage = fm.fileExists(atPath: packageURL.path)
        guard hasPackage else {
            throw EmbeddingError.modelArtifactsMissing(
                cacheRoot: cacheRoot.path,
                compiledPath: compiledURL.path,
                packagePath: packageURL.path
            )
        }

        let compiledTempURL: URL
        do {
            compiledTempURL = try MLModel.compileModel(at: packageURL)
        } catch {
            throw EmbeddingError.modelCompilationFailed(
                packagePath: packageURL.path,
                detail: error.localizedDescription
            )
        }

        do {
            if fm.fileExists(atPath: compiledURL.path) {
                try fm.removeItem(at: compiledURL)
            }
            try fm.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
            try fm.moveItem(at: compiledTempURL, to: compiledURL)
        } catch {
            do {
                if fm.fileExists(atPath: compiledURL.path) {
                    return compiledURL
                }
            }
            throw EmbeddingError.compiledModelPersistenceFailed(
                compiledPath: compiledURL.path,
                detail: error.localizedDescription
            )
        }

        return compiledURL
    }

    func embed(text: String) async throws -> [Float] {
        guard let model else { throw EmbeddingError.modelNotLoaded }
        guard tokenizerLoaded else { throw EmbeddingError.tokenizerNotLoaded }

        let encoded = try await tokenizer.encode(text: text)
        guard !encoded.inputIDs.isEmpty else {
            throw EmbeddingError.inferenceFailure("Tokenizer produced empty input")
        }

        let seqLen = encoded.inputIDs.count

        let inputDict = try buildInputDictionary(
            model: model,
            tokenIDs: encoded.inputIDs,
            attentionMask: encoded.attentionMask,
            tokenTypeIDs: encoded.tokenTypeIDs
        )

        let provider = try MLDictionaryFeatureProvider(dictionary: inputDict)
        let prediction = try await model.prediction(from: provider)
        let hiddenStates = try extractHiddenStates(from: prediction)
        let pooled = maskedMeanPool(hiddenStates: hiddenStates, attentionMask: encoded.attentionMask, sequenceLength: seqLen)
        return l2Normalize(pooled)
    }

    func embedBatch(texts: [String]) async throws -> [[Float]] {
        var results: [[Float]] = []
        results.reserveCapacity(texts.count)
        for text in texts {
            try Task.checkCancellation()
            let vec = try await embed(text: text)
            results.append(vec)
        }
        return results
    }

    func trimTokenizerCache() async {
        await tokenizer.trimCache()
    }

    func unload() async {
        model = nil
        tokenizerLoaded = false
        cachedModelInfo = nil
        await MainActor.run {
            registry.setLoadState(for: modelID, .unloaded)
        }
    }

    // MARK: - Model I/O

    private func buildInputDictionary(
        model: MLModel,
        tokenIDs: [Int],
        attentionMask: [Int],
        tokenTypeIDs: [Int]
    ) throws -> [String: MLFeatureValue] {
        let inputDescs = model.modelDescription.inputDescriptionsByName
        let seqLen = tokenIDs.count

        var dict: [String: MLFeatureValue] = [:]

        let inputIDsKey = inputDescs.keys.first(where: { $0.contains("input_id") }) ?? "input_ids"
        let attentionKey = inputDescs.keys.first(where: { $0.contains("attention") }) ?? "attention_mask"
        let tokenTypeKey = inputDescs.keys.first(where: { $0.contains("token_type") })

        let dataType = detectMultiArrayDataType(for: inputIDsKey, in: inputDescs)

        dict[inputIDsKey] = MLFeatureValue(multiArray: try makeMultiArray(tokenIDs, shape: [1, seqLen], dataType: dataType))
        dict[attentionKey] = MLFeatureValue(multiArray: try makeMultiArray(attentionMask, shape: [1, seqLen], dataType: dataType))

        if let ttKey = tokenTypeKey {
            dict[ttKey] = MLFeatureValue(multiArray: try makeMultiArray(tokenTypeIDs, shape: [1, seqLen], dataType: dataType))
        }

        return dict
    }

    private func detectMultiArrayDataType(
        for key: String,
        in descriptions: [String: MLFeatureDescription]
    ) -> MLMultiArrayDataType {
        if let desc = descriptions[key],
           let constraint = desc.multiArrayConstraint {
            return constraint.dataType
        }
        return .int32
    }

    private func makeMultiArray(
        _ values: [Int],
        shape: [Int],
        dataType: MLMultiArrayDataType
    ) throws -> MLMultiArray {
        let nsShape = shape.map { NSNumber(value: $0) }
        let array = try MLMultiArray(shape: nsShape, dataType: dataType)
        let count = values.count

        switch dataType {
        case .int32:
            let ptr = array.dataPointer.bindMemory(to: Int32.self, capacity: count)
            for (i, v) in values.enumerated() {
                ptr[i] = Int32(v)
            }
        case .float32:
            let ptr = array.dataPointer.bindMemory(to: Float.self, capacity: count)
            for (i, v) in values.enumerated() {
                ptr[i] = Float(v)
            }
        default:
            for (i, v) in values.enumerated() {
                array[i] = NSNumber(value: v)
            }
        }

        return array
    }

    // MARK: - Output Extraction

    private func extractHiddenStates(
        from prediction: MLFeatureProvider
    ) throws -> MLMultiArray {
        let outputNames = Set(prediction.featureNames)

        let candidateKeys = [
            "last_hidden_state",
            "output",
            "hidden_states",
            "token_embeddings",
            "output_0",
            "embeddings",
            "output_logits"
        ]

        var selectedKey: String?
        for key in candidateKeys {
            if outputNames.contains(key) {
                selectedKey = key
                break
            }
        }

        if selectedKey == nil {
            selectedKey = outputNames.first(where: { name in
                guard let feat = prediction.featureValue(for: name),
                      let arr = feat.multiArrayValue else { return false }
                return arr.shape.count >= 2
            })
        }

        guard let key = selectedKey,
              let feat = prediction.featureValue(for: key),
              let hiddenStates = feat.multiArrayValue else {
            throw EmbeddingError.outputMissing("No suitable hidden state output found. Available: \(outputNames)")
        }

        return hiddenStates
    }

    // MARK: - Pooling

    private func maskedMeanPool(
        hiddenStates: MLMultiArray,
        attentionMask: [Int],
        sequenceLength: Int
    ) -> [Float] {
        let shape = hiddenStates.shape.map { $0.intValue }
        let is3D = shape.count == 3

        let dim: Int
        if is3D {
            dim = shape[2]
        } else if shape.count == 2 {
            dim = shape[1]
        } else {
            dim = embeddingDimension
        }

        let seqLen = min(sequenceLength, attentionMask.count)
        let totalElements = hiddenStates.count

        var summed = [Float](repeating: 0, count: dim)
        var maskSum: Float = 0

        let strides: [Int]
        if is3D {
            strides = hiddenStates.strides.map { $0.intValue }
        } else {
            strides = hiddenStates.strides.map { $0.intValue }
        }

        if hiddenStates.dataType == .float32 {
            let ptr = hiddenStates.dataPointer.bindMemory(to: Float.self, capacity: totalElements)
            for t in 0..<seqLen {
                let m = Float(attentionMask[t])
                guard m > 0 else { continue }
                maskSum += m
                let baseOffset: Int
                if is3D {
                    baseOffset = strides[1] * t
                } else {
                    baseOffset = strides[0] * t
                }
                for d in 0..<dim {
                    summed[d] += ptr[baseOffset + d] * m
                }
            }
        } else {
            for t in 0..<seqLen {
                let m = Float(attentionMask[t])
                guard m > 0 else { continue }
                maskSum += m
                for d in 0..<dim {
                    let idx: [NSNumber]
                    if is3D {
                        idx = [0, NSNumber(value: t), NSNumber(value: d)]
                    } else {
                        idx = [NSNumber(value: t), NSNumber(value: d)]
                    }
                    summed[d] += hiddenStates[idx].floatValue * m
                }
            }
        }

        guard maskSum > 0 else { return [Float](repeating: 0, count: dim) }

        for d in 0..<dim {
            summed[d] /= maskSum
        }

        return summed
    }

    // MARK: - Normalization

    private func l2Normalize(_ vector: [Float]) -> [Float] {
        var sumSq: Float = 0
        for v in vector {
            sumSq += v * v
        }
        let norm = sqrtf(sumSq)
        guard norm > 1e-12 else { return vector }
        return vector.map { $0 / norm }
    }
}
