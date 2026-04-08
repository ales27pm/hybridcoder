# Architecture

This document is the canonical source for the split between the **current implementation** and the **target architecture**.

## Current implementation

HybridCoder is currently a SwiftUI iOS app with:

- local orchestration
- semantic retrieval
- patch planning and application
- project and workspace persistence
- imported repository handling
- a prototype-oriented editing flow

## What is already implemented in the LLM coding core

The current repo already has a meaningful local coding stack:

1. chat-driven route selection
2. semantic retrieval over indexed code
3. Qwen-based code generation and code explanation
4. Foundation Models-based explanation and patch planning
5. exact-match patch application to the active workspace

This means the repo is already beyond placeholders for the LLM coding core.

## What is still missing

The missing subsystem is the **agent runtime** — the bytecoding layer that can turn a user goal into a sequence of coding actions.

Today, the repo does not yet implement a full autonomous loop for:

- planning multi-step coding work
- selecting sub-tasks and execution order
- creating, renaming, deleting, and restructuring files as first-class actions
- validating progress and iterating until the requested feature is actually brought to life

## Target architecture

The target product is a local-first React Native and Expo builder with these core subsystems:

1. Studio shell
2. Project studio
3. React Native workspace analysis
4. AI orchestration
5. Template system
6. Preview system
7. Agent runtime / bytecoding system

## Agent runtime responsibilities

The bytecoding layer should sit on top of the existing LLM core and provide:

- intent decomposition
- execution planning
- guarded file-system actions
- iterative validation and retry loops
- explicit transition from chat request to concrete workspace changes

## How these docs fit together

- `docs/product-vision.md` — product goals, non-goals, and scope
- `docs/project-structure.md` — target repository layout and migration boundaries
- `docs/template-system.md` — template and scaffold strategy
- `docs/preview-system.md` — preview constraints and staged preview plan
- `docs/agent-runtime.md` — bytecoding strategy and agent-runtime scope
- `docs/roadmap.md` — phased refactor order

Read this file first, then use the linked docs to go deeper into each subsystem.

## Documentation rule

Preview should not be described as solved until the runtime story is genuinely strong enough to support that claim.
