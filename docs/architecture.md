# Architecture

This document is the canonical source for the split between the current implementation and the target architecture.

## Current implementation

HybridCoder is currently a SwiftUI iOS app with:

- local orchestration
- semantic retrieval
- patch planning and application
- project and workspace persistence
- imported repository handling with an Expo-first builder path
- a builder-oriented `StudioProject` model bridged to the legacy sandbox store
- manifest-driven Expo scaffolds for new multi-file projects
- structural preview coordination and diagnostics
- a transitional prototype-oriented editing flow that still remains in compatibility seams

## What is already implemented in the LLM coding core

The current repo already has a meaningful local coding stack:

1. chat-driven route selection
2. semantic retrieval over indexed code
3. Qwen-based code generation and code explanation
4. Foundation Models-based explanation and patch planning
5. exact-match patch application to the active workspace

This means the repo is already beyond placeholders for the LLM coding core.

## What is still missing

The missing subsystem is the bytecoding runtime, also referred to in the docs as the agent runtime.

In this repository, those two terms mean the same target subsystem:

- bytecoding runtime emphasizes the product behavior: conversation that turns into real coding progress
- agent runtime emphasizes the implementation shape: an execution layer that can plan and carry out workspace actions

Today, the repo does not yet implement a full execution loop for:

- fully autonomous multi-step coding work across all scenarios
- robust sub-task decomposition beyond goal-derived file intents and patch-backed plans
- complete first-class workspace coverage across file and folder actions in every execution path (for example, goal-derived non-patch modify generation still remains incomplete for most update scenarios)
- durable validate/replan/retry behavior that can carry a project to completion without patch-centric fallback in most cases

The current codebase now includes planner/coordinator execution with bounded validate -> replan -> retry, but it is still patch-plan centric rather than a finished autonomous runtime.

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

## Conversation-aligned commitments

The docs and implementation should stay aligned to these commitments:

- the product is a chat-first builder, not only a file browser
- the primary stack is React Native and Expo
- imported Expo repositories should become first-class projects
- templates should evolve toward real multi-file project scaffolds
- preview must be documented honestly and must not be overstated
- the LLM coding core that already exists must not be described as placeholder-only
- the missing bytecoding runtime must not be described as already implemented

## Non-drift rules

To avoid product drift, strategy and implementation should keep these rules visible:

1. Default to React Native and Expo assumptions unless the user explicitly asks for something else.
2. Do not let generic repository-assistant behavior become the product center again.
3. Do not describe preview as solved until the runtime story is genuinely strong enough.
4. Do not describe bytecoding or agent autonomy as solved until the execution loop actually exists.
5. Prefer phased refactors that preserve the real LLM core already present in the repo.

## How these docs fit together

- `docs/product-vision.md` — product goals, non-goals, and scope
- `docs/project-structure.md` — target repository layout and migration boundaries
- `docs/template-system.md` — template and scaffold strategy
- `docs/preview-system.md` — preview constraints and staged preview plan
- `docs/agent-runtime.md` — bytecoding strategy, agent-runtime scope, and execution model
- `docs/roadmap.md` — phased refactor order

Read this file first, then use the linked docs to go deeper into each subsystem.

## Execution contract source

`docs/product-vision.md` is the canonical execution contract for:

- target users and primary jobs
- must-win workflows
- KPI targets and acceptance bars

This extends planning precision but does not change the current-state capability claims in this architecture document.

## Documentation rule

Preview should not be described as solved until the runtime story is genuinely strong enough to support that claim.
