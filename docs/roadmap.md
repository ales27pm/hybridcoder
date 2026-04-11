# Roadmap

## Phase 1
Split app-wide state from workspace state and lock the product identity around Expo and React Native.

## Phase 2
Replace the project model and template layer.

## Phase 3
Specialize orchestration for React Native and Expo.

## Phase 4
Replace the old sandbox with a preview coordinator and diagnostics flow.

## Phase 5
Treat imported Expo repositories as first-class projects.

## Phase 6
Implement the bytecoding runtime: introduce an agent layer that can turn user intent into a sequence of guarded coding actions.

### Phase 6 target capabilities

- intent decomposition
- execution planning
- first-class file actions
- iterative apply, validate, and retry loops
- transition from chat request to real workspace progress

### Phase 6 exit criteria (shared contract)

Phase 6 is done only when both capability and measurement bars are met:

- functional bars:
  - runtime executes ordered multi-step workspace actions as the default path for goal-oriented tasks
  - first-class create/modify/rename/delete/move actions are available in runtime execution
  - validate -> replan -> retry is implemented for incomplete or blocked goals
  - runtime reporting is visible and debuggable for each execution step
- KPI and acceptance bars:

| KPI | Baseline | Target | Acceptance bar |
| --- | --- | --- | --- |
| Time to first scaffold output | Not instrumented | <= 120s | For a valid chat scaffold request, first coherent multi-file Expo output is produced within target time. |
| Goal-to-plan latency (p50) | Not instrumented | <= 15s | Runtime emits an ordered action plan within target latency for Phase 6 scenario inputs. |
| Multi-step task completion without manual file edits | Not instrumented | >= 70% (Phase 6 scenario set) | Scenario finishes with runtime-executed workspace actions and no required manual file intervention. |
| Preview truthfulness | Not instrumented | 0 false runtime claims in validation suite | Diagnostic/preview surfaces never claim full RN runtime capability where not implemented. |
| Workspace safety | Not instrumented | 0 out-of-bound file actions | Validation suite records no file create/modify/rename/delete/move escaping workspace boundaries. |

### Phase 6 current status (as of April 11, 2026)

- classification: less patch-centric but still partial
- main `.patchPlanning` chat entry now runs a goal-first runtime path (`goal -> action plan -> execute -> validate -> report`)
- runtime execution now prefers goal-derived workspace actions first and falls back to patch-backed writes only when needed
- primary chat flow now receives and stores agent-runtime reports directly
- the runtime is still not fully agentic: patch-backed write strategies remain central for many create/update edits, `PatchResult` is still a first-class output, and no iterative validate -> replan -> retry loop exists yet

## Phase 7
Delete obsolete files and finish the documentation and code alignment.

## Anti-drift note

At every phase, `docs/architecture.md` should remain the canonical source for:

- what is already implemented
- what is still missing
- what the product is supposed to become

## Status note

The repository now has partial progress inside several phases:

- Phase 2 is underway through `StudioProject` and manifest-driven Expo scaffolds
- Phase 4 is underway through structural preview coordination and diagnostics
- Phase 5 is underway through an Expo-first imported workspace path with generic repo fallback
- Phase 6 is underway through goal-first runtime entry in the main chat path, action-sequenced execution, and guarded patch fallback

Those phase starts should not be mistaken for completion. The remaining gaps are still the full builder project migration, richer scaffold breadth, stronger preview/runtime truthfulness in every screen, direct create/update action generation beyond patch fallback, and a validate -> replan -> retry loop for the bytecoding runtime.
