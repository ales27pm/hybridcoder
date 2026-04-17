# HybridCoder

HybridCoder is an on-device iOS coding studio that is being refocused into a React Native and Expo builder.

## At a glance

- SwiftUI host app
- local workspace and project state
- chat-driven local coding workflow
- SpeziLLM/SpeziLLMLocal orchestration over llama.cpp GGUF runtimes
- semantic retrieval backed by local embedding models
- Qwen 2.5 Coder generation and explanation services
- patch planning and editing flows
- imported repository and prototype handling

## What already exists

HybridCoder runtime summary (as of 2026-04-17): the app routes local LLM orchestration through `FoundationModelService` and `QwenCoderService`, both backed by SpeziLLM/SpeziLLMLocal + llama.cpp, with models resolved from `Files > On My iPhone > Hybrid Coder > Models/` via `ModelRegistry.externalModelsRoot`.

The repository already contains a real local LLM coding core:

- chat-driven route selection
- semantic retrieval over indexed code
- code generation and code explanation
- structured patch planning
- patch application to the active workspace

## What is still missing

The repository does not yet have a finished bytecoding runtime.

That means there is still no fully implemented agent layer that can autonomously:

- interpret a user goal as a multi-step coding plan
- choose and sequence coding sub-tasks
- create, modify, rename, and delete files as first-class actions
- iterate until the requested feature or app milestone is actually brought to life

## Source of truth

Start with `docs/architecture.md`.

That file is the canonical source for:

- the current implementation
- the target builder architecture
- the bytecoding / agent-runtime gap
- the non-drift rules that should keep the product aligned

Then use:

- `docs/product-vision.md` for goals and non-goals
- `docs/agent-runtime.md` for the bytecoding strategy
- `docs/roadmap.md` for the phased refactor plan
