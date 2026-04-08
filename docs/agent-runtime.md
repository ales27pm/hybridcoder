# Agent Runtime

This document defines the bytecoding strategy for HybridCoder.

## Terminology

In this repository, **bytecoding runtime** and **agent runtime** refer to the same target subsystem.

- **bytecoding runtime** is the product-facing name
- **agent runtime** is the implementation-facing name

Both terms describe the execution layer that should turn a chat request into real workspace progress.

## Current state

HybridCoder already has a local LLM coding core with:

- chat input handling
- route selection
- semantic retrieval
- code generation
- patch planning
- patch application

The current repository now also has a first agent-runtime milestone:

- workspace context detection
- structured execution plans for guarded patch work
- execution coordination around validation, apply, and workspace diagnostics
- visible runtime reports back into chat

That is meaningful groundwork, but it is not yet a full bytecoding system.

## Missing capability

The missing layer is an agent runtime that can connect the user goal, the execution plan, the workspace actions, the validation step, and the next action.

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
- stay aligned to React Native and Expo as the primary product scope

## Recommended architecture

A realistic first version should add these layers:

- Intent Planner
- Workspace Action Model
- Execution Coordinator
- Validation Loop

### Data flow

The expected flow is:

1. the chat request enters the Intent Planner
2. the planner produces an ordered execution plan made of workspace actions
3. the Execution Coordinator carries out those actions using the existing orchestrator, retrieval, and patching systems
4. the Validation Loop inspects diagnostics and workspace state after each step or milestone
5. if the goal is not reached, control goes back into planning and execution for the next step

This means the planner decides **what should happen**, the coordinator decides **how it is carried out**, and the validation loop decides **whether the system should continue, retry, or stop**.

## Relationship to existing systems

The agent runtime should sit on top of:

- `ChatViewModel`
- `AIOrchestrator`
- `PatchEngine`
- semantic retrieval
- model routing

The current orchestrator should remain the model and context backbone. The new runtime should add sequencing and action execution rather than duplicating retrieval or generation logic.

## Anti-drift rules

The bytecoding runtime should follow these rules:

1. default to React Native and Expo assumptions unless the user explicitly asks for something else
2. prefer the active workspace over generic repo-wide behavior
3. use first-class workspace actions instead of vague free-form edits where possible
4. do not claim completion if only a plan exists and no real workspace progress happened
5. keep the decision path visible enough that future debugging and UI inspection remain possible

## First implementation milestone

The first realistic bytecoding milestone is not full autonomy. It is:

- accept a goal from chat
- produce a structured execution plan
- execute approved file actions through existing patching and workspace services
- surface progress and blockers back into chat

The current implementation now reaches that milestone for guarded patch-plan execution, but it still does not complete the broader create/rename/delete/retry loop for first-class workspace actions.

## Definition of success

The bytecoding runtime is considered real when a user can describe a feature or app change in chat and the system can:

- plan the work
- carry out multiple concrete workspace actions
- keep state across those actions
- make visible progress without requiring every single file edit to be manually orchestrated by the user
