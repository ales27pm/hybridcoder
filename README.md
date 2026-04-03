# HybridCoder

HybridCoder is an on-device AI coding assistant for iOS.

## Chosen Architecture Path

This repository is now standardized on **FoundationModels + CoreML (iOS 26+)**.

- **Generation/routing/planning:** Apple Foundation Models (`FoundationModels` framework).
- **Semantic search embeddings:** downloaded CoreML embedding model.
- **No MLX runtime:** MLX package and product links are removed from the Xcode project.

## Platform Baseline

- Minimum deployment target: **iOS 26.0** for all app and test targets.
- Apple Intelligence availability is required for model-backed assistant responses.

## Why this path

- Single Apple-native stack for inference + orchestration.
- Reduced dependency surface (no third-party LLM runtime integration in project wiring).
- Simpler boot flow and status model for users.

See `docs/architecture.md` for implementation details.
