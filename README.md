# HybridCoder

HybridCoder is an on-device AI coding assistant for iOS.

## Chosen Architecture Path

This repository is now standardized on **FoundationModels + CoreML (iOS 26+)**.

- **Routing/explanations/patch planning:** Apple Foundation Models (`FoundationModels` framework).
- **Code generation:** Qwen coder via `CoreMLPipelines`.
- **Semantic search embeddings:** downloaded CoreML embedding model.
- **No MLX runtime:** MLX package and product links are removed from the Xcode project.

## Platform Baseline

- Minimum deployment target: **iOS 26.0** for all app and test targets.
- Apple Intelligence availability is required for model-backed assistant responses.

## Supported OS / Model Matrix

| Runtime capability | Supported OS | Provider | Fallback |
| --- | --- | --- | --- |
| Route classification | iOS 26.0+ | Apple Foundation Models | None |
| Explanation + patch planning | iOS 26.0+ | Apple Foundation Models | None |
| Code generation | iOS 26.0+ | Qwen via CoreMLPipelines | None |
| Semantic embeddings / search index | iOS 26.0+ | CoreML CodeBERT | None (user must download embedding model) |

HybridCoder is **Foundation Models first** for routing and structured reasoning, with a local Qwen code-generation path for `codeGeneration` requests. If Apple Intelligence is unavailable at runtime, route classification and Foundation-backed flows fail with a deterministic "no model available" error instead of falling back to alternate providers.

## Why this path

- Single Apple-native stack for inference + orchestration.
- Reduced dependency surface (no third-party LLM runtime integration in project wiring).
- Simpler boot flow and status model for users.

See `docs/architecture.md` for implementation details.

## Prompt templates (slash commands)

HybridCoder supports reusable prompt templates loaded from your repository at:

- `.hybridcoder/prompts/*.md`

Each markdown file can include optional YAML frontmatter keys:

- `name` (template display name)
- `description` (optional help text)
- `route` (`explanation`, `codeGeneration`, `patchPlanning`, or `search`)

Invoke templates in chat with slash commands:

- `/refactor "ViewController.swift" fix unused variable`

Interpolation syntax in template bodies:

- `$1`, `$2`, ... for positional arguments
- `${@}` for all arguments joined by spaces
- `${@:N}` for arguments from position `N` onward

If a template declares a `route` value, that route overrides automatic route classification for that query.
