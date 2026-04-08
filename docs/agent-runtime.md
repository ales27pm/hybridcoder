# Agent Runtime

This document defines the bytecoding strategy for HybridCoder.

## Current state

HybridCoder already has a local LLM coding core with:

- chat input handling
- route selection
- semantic retrieval
- code generation
- patch planning
- patch application

That is necessary groundwork, but it is not yet a full bytecoding system.

## Missing capability

The missing layer is an agent runtime that can bridge the user goal, the execution plan, the workspace actions, the validation step, and the next action.

Without that layer, the app remains a strong coding assistant, but not yet a system that can carry a project forward through multiple coding actions.

## Target responsibilities

The agent runtime should be responsible for:

1. Intent decomposition
2. Execution planning
3. Workspace actions
4. Guarded execution
5. Iteration loop

## Workspace actions

The runtime should support first-class operations such as:

- create file
- modify file
- rename file
- delete file
- create folder
- move file

## Design constraints

- stay local-first
- build on the existing orchestrator instead of replacing it blindly
- preserve repo grounding and semantic retrieval
- do not pretend preview/runtime capability exists where it does not
- expose its decision trail clearly enough for debugging and future UI inspection

## Recommended architecture

A realistic first version should add these layers:

- Intent Planner
- Workspace Action Model
- Execution Coordinator
- Validation Loop

## Relationship to existing systems

The agent runtime should sit on top of:

- `ChatViewModel`
- `AIOrchestrator`
- `PatchEngine`
- semantic retrieval
- model routing

The current orchestrator should remain the model and context backbone. The new runtime should add autonomous sequencing and action execution rather than duplicating retrieval or generation logic.

## First implementation milestone

The first realistic bytecoding milestone is not full autonomy. It is:

- accept a goal from chat
- produce a structured execution plan
- execute approved file actions through existing patching and workspace services
- surface progress and blockers back into chat

## Definition of success

The bytecoding runtime is considered real when a user can describe a feature or app change in chat and the system can:

- plan the work
- carry out multiple concrete workspace actions
- keep state across those actions
- make visible progress without requiring every single file edit to be manually orchestrated by the user
