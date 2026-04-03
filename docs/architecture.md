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

## Boot flow (selected stack only)

1. App initializes `AIOrchestrator`.
2. `warmUp()` loads the embedding model if downloaded, initializes semantic index + patch engine, and refreshes Foundation Models status.
3. User queries route through Foundation Models when available.
4. If Apple Intelligence is unavailable, orchestrator surfaces a clear no-model-available error for iOS 26+ devices.

## Non-goals

- No MLX runtime/model loading in startup path.
- No MLX package references in Xcode project graph.
