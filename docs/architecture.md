# Architecture Decision Record

## Decision

HybridCoder uses **FoundationModels/CoreML on iOS 26+** as the only supported AI runtime path.

## Enforcements applied

1. Xcode project deployment targets raised to `26.0`.
2. `mlx-swift-lm.git` package reference removed from `project.pbxproj`.
3. MLX package product links (`MLXLLM`, `MLXLMCommon`) removed from target dependencies/frameworks.
4. Startup/warm-up orchestration updated so app boot uses only:
   - Foundation model status initialization.
   - CoreML embedding download/load/index setup.
5. `AIOrchestrator` enforces a **single provider policy** for generation + route classification:
   - Provider is always `FoundationModels`.
   - No heuristic/Qwen fallback path is used for route or answer generation.
6. Route/provider telemetry is emitted through `os.Logger` (category: `AIOrchestrator`) for:
   - `route.classifier` (classifier-selected route + confidence)
   - `route.selected` (effective route/provider + mode)

## Boot flow (selected stack only)

1. App initializes `AIOrchestrator`.
2. `warmUp()` loads the embedding model if downloaded, initializes semantic index + patch engine, and refreshes Foundation Models status.
3. User queries route through Foundation Models classifier.
4. If Apple Intelligence is unavailable, orchestrator surfaces a clear no-model-available error for iOS 26+ devices.
5. Routing is deterministic from the Foundation Models classifier output; invalid route outputs are surfaced as route-resolution errors.

## Supported OS / Model Matrix

| Capability | OS baseline | Provider | Behavior when unavailable |
| --- | --- | --- | --- |
| Route decision | iOS 26.0+ | Apple Foundation Models | Request fails (`noModelAvailable` or route-resolution error) |
| Answer generation (streaming + non-streaming) | iOS 26.0+ | Apple Foundation Models | Request fails (`noModelAvailable`) |
| Semantic retrieval embeddings | iOS 26.0+ | CoreML CodeBERT | Warm-up/indexing reports model download/load error |

## Non-goals

- No MLX runtime/model loading in startup path.
- No MLX package references in Xcode project graph.
