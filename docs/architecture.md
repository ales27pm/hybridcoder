# Architecture Decision Record

## Decision

HybridCoder uses a **FoundationModels/CoreML split runtime on iOS 26+**.

## Enforcements applied

1. Xcode project deployment targets raised to `26.0`.
2. `mlx-swift-lm.git` package reference removed from `project.pbxproj`.
3. MLX package product links (`MLXLLM`, `MLXLMCommon`) removed from target dependencies/frameworks.
4. Startup/warm-up orchestration initializes:
   - Foundation model status for routing + structured reasoning.
   - CoreML embedding download/load/index setup.
   - Qwen/CoreMLPipelines state for code generation and codebase-heavy explanations.
5. `AIOrchestrator` enforces deterministic provider selection by route:
   - `FoundationModels` for route classification, simple explanations, and patch planning.
   - `QwenCoreMLPipelines` for `codeGeneration` and repository-grounded explanation requests.
   - No heuristic route fallback path is used.
6. Route/provider telemetry is emitted through `os.Logger` (category: `AIOrchestrator`) for:
   - `route.classifier` (classifier-selected route + confidence)
   - `route.selected` (effective route/provider + mode)

## Boot flow (selected stack only)

1. App initializes `AIOrchestrator`.
2. `warmUp()` loads the embedding model if downloaded, initializes semantic index + patch engine, and refreshes Foundation Models status.
3. User queries route through the Foundation Models classifier.
4. The orchestrator gathers semantic context, policy files, and conversation memory.
5. Requests dispatch to Foundation Models or Qwen based on the chosen route.
6. If Apple Intelligence is unavailable, route classification and Foundation-backed flows surface a clear no-model-available error for iOS 26+ devices.

## Supported OS / Model Matrix

| Capability | OS baseline | Provider | Behavior when unavailable |
| --- | --- | --- | --- |
| Route decision | iOS 26.0+ | Apple Foundation Models | Request fails (`noModelAvailable` or route-resolution error) |
| Simple explanations + patch planning | iOS 26.0+ | Apple Foundation Models | Request fails (`noModelAvailable`) |
| Code generation + codebase-heavy explanations | iOS 26.0+ | Qwen via CoreMLPipelines | Code generation fails (`codeGenerationModelUnavailable`); explanations fall back to Foundation Models if Qwen is unavailable before generation starts |
| Semantic retrieval embeddings | iOS 26.0+ | CoreML CodeBERT | Warm-up/indexing reports model download/load error |

## Non-goals

- No MLX runtime/model loading in startup path.
- No MLX package references in Xcode project graph.
