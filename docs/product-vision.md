# Product Vision

HybridCoder should become a local-first mobile app builder for React Native and Expo, hosted inside a native SwiftUI iOS app.

## Product goals

- local execution first
- strong Expo and React Native alignment
- project continuity
- template-driven starts
- useful diagnostics and preview feedback
- chat-first creation workflow
- bytecoding: transform user intent into working code through an agent runtime

## Bytecoding definition

Bytecoding is the ability for the system to:

- translate a user request into a structured plan
- execute that plan through workspace actions
- keep iterating until the result is functionally closer to the requested outcome

## Product commitments

HybridCoder should behave like:

- a React Native and Expo-focused builder
- a chat-first coding studio
- a project-oriented workspace, not just a snippet toy
- a system that can eventually move from conversation to real workspace progress

## What it should not be

- a generic multi-language IDE
- a broad repository assistant for every stack
- a cloud-first coding product
- a fake preview app that only runs JavaScript snippets
- a product that claims agent autonomy before the runtime actually exists

## Target users and primary jobs

- Solo builders who need to create coherent Expo workspaces from chat without dropping into manual setup for every file.
- Maintainers of imported Expo repositories who need a reliable goal -> action -> validation loop for real workspace progress.
- Mobile-first developers who need truthful preview diagnostics and clear runtime limits instead of fake execution claims.

## Top 3 must-win workflows

1. Chat-to-Expo scaffold
   - User describes a new app in chat.
   - System plans and writes a coherent multi-file Expo workspace (config, entrypoint, navigation, dependencies).
   - Output is directly usable for continued edits.
2. Imported Expo repo improvement loop
   - User imports an existing Expo project and asks for a change.
   - System decomposes intent into ordered workspace actions and executes them with guarded file operations.
   - System validates progress and reports blockers or next actions.
3. Honest preview and diagnostics loop
   - User requests preview feedback.
   - System runs structural and diagnostic checks, explicitly stating what is validated versus not yet runtime-backed.
   - UI messaging remains truthful about current preview capability.

## Capability maturity (current vs target)

| Capability | Current state (as of April 11, 2026) | Target state |
| --- | --- | --- |
| Orchestration | Local route selection, retrieval, generation, and guarded patch application are real and integrated. | Goal-first orchestration with stable multi-step execution as the default path for coding tasks. |
| Bytecoding runtime | Partial milestone only: planner/coordinator exists, still patch-centric, no full validate -> replan -> retry loop. | Full agent-runtime loop with intent decomposition, first-class actions, iterative validation, and retry. |
| Workspace actions | Modify flow is strongest; create/rename/delete/move are not yet uniformly first-class across all execution paths. | First-class create/modify/rename/delete/move actions available consistently in runtime execution. |
| Preview | Structural preview and diagnostics are real; not a full in-app RN runtime. | Stronger runtime bridge while preserving truthful diagnostics and clear capability boundaries. |

## Success metrics and acceptance bars

| KPI | Baseline | Target | Acceptance bar |
| --- | --- | --- | --- |
| Time to first scaffold output | Not instrumented | <= 120s | For a valid chat scaffold request, first coherent multi-file Expo output is produced within target time. |
| Goal-to-plan latency (p50) | Not instrumented | <= 15s | Runtime emits an ordered action plan within target latency for Phase 6 scenario inputs. |
| Multi-step task completion without manual file edits | Not instrumented | >= 70% (Phase 6 scenario set) | Scenario finishes with runtime-executed workspace actions and no required manual file intervention. |
| Preview truthfulness | Not instrumented | 0 false runtime claims in validation suite | Diagnostic/preview surfaces never claim full RN runtime capability where not implemented. |
| Workspace safety | Not instrumented | 0 out-of-bound file actions | Validation suite records no file create/modify/rename/delete/move escaping workspace boundaries. |

## Workflow to KPI traceability

| Must-win workflow | Primary KPI | Acceptance bar |
| --- | --- | --- |
| Chat-to-Expo scaffold | Time to first scaffold output | Coherent multi-file Expo workspace generated within target time. |
| Imported Expo repo improvement loop | Multi-step task completion without manual file edits | Runtime completes scenario changes with ordered guarded actions and validation. |
| Honest preview and diagnostics loop | Preview truthfulness | No false runtime claims in diagnostic/preview validation suite. |

## Phase alignment (Roadmap Phase 6 and 7)

- Phase 6 implements the bytecoding runtime as a real execution loop and is considered complete only when:
  - intent decomposition, ordered execution planning, first-class workspace actions, and validate -> replan -> retry are operational,
  - the KPI targets and acceptance bars above are met or explicitly tracked against baseline instrumentation.
- Phase 7 focuses on cleanup and alignment:
  - remove obsolete files and compatibility seams where replacement paths are already stable,
  - keep docs and implementation claims synchronized with actual shipped capability.
