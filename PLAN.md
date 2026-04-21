# Refactor AI stack: split orchestrator, structured router, rename FM service, unify model storage, agent-centered mutations

## Goal

Five coordinated refactors across the AI stack. `AIOrchestrator` stays as a deprecated thin facade so no call sites break, but real logic moves into focused services. The weakest seams — keyword-based route classification, naming of the "Foundation" model, the overlapping model storage worlds, and patching as the conceptual backbone — all get cleaned up.

## 1. Split `AIOrchestrator` into four services

New services, each with a single responsibility:

- `**WorkspaceLifecycleService**` — owns `repoRoot`, `repoFiles`, `activeWorkspaceSource`, `activePrototypeProject`, indexing (`SemanticSearchIndex`), context policies, template diagnostics, prototype materialization, and all `importRepo` / `closeRepo` / `openPrototypeWorkspace` flows.
- `**ContextAssemblyService**` — owns `gatherContextWithSources`, `buildPromptContext`, `matchRelevantFiles`, `buildRetrievalQuery`, doc RAG integration, and all budget math (`PromptContextBudget`). Pure assembly — no workspace I/O beyond what the lifecycle service exposes via a small read-only protocol.
- `**RuntimeExecutionService**` — owns the agent runtime loop: `executeGoalWithAgentRuntime`, `executePatchPlanWithAgentRuntime`, phase execution, retry planning, workspace file mutation callbacks, validation hookup, and KPI recording. This becomes the single mutation entry (see §5).
- `**ModelRuntimeCoordinator**` — owns model lifecycles: warm-up/unload/reset of embedding + code-generation models, memory pressure eviction, Qwen idle timers, and bridging to the renamed orchestration model (see §4).

`AIOrchestrator` is kept but marked deprecated:

- Internally it holds all four services and forwards every existing public method/property.
- Each forwarded method carries a `// TODO(orchestrator-split):` marker pointing to the owning service.
- Doc comment on the class explains it exists only for call-site migration and will be removed.
- Tests that reach into `AIOrchestrator.*` static helpers continue to work because those statics move onto the new services and `AIOrchestrator` re-exposes them as `@available(*, deprecated)` typealiases/forwarders.

## 2. Structured route classifier with scored heuristic impl

Replace `FoundationModelService.classifyRoute`'s keyword switch with:

- `**RouteClassifier` protocol** — `func classify(query:, fileList:) async throws -> RouteDecision`. Single contract every classifier must satisfy (heuristic today, FoundationModels / on-device LLM later).
- `**ScoredIntentRouteClassifier**` — the default implementation. For each candidate route it computes a weighted score from multiple independent signals:
  - verb/intent signals (write/edit/apply vs. read/explain vs. locate)
  - object signals (file paths, symbol-like tokens, `.swift`/`.ts` extensions)
  - structural signals (query length, imperative mood, presence of code fences)
  - workspace signals (file hints that match repo paths)
  - negative signals (questions starting with "why/how/what" penalize write routes)
  Winning route must beat runner-up by a configurable margin — otherwise falls back to `.explanation`. Confidence = normalized margin.
- The old keyword `if/else` chain is deleted. `RuntimeExecutionService` and `ContextAssemblyService` consume the protocol, not the implementation.
- Full unit tests for the scorer covering each signal class and the tie-break/fallback behavior.

## 3. Rename `FoundationModelService` → `LocalOrchestrationModel`

- File renamed to `LocalOrchestrationModel.swift`.
- Class renamed. Logger category updated. Tests updated.
- Doc comment at the top states plainly: *"Local orchestration LLM. Backed by the Qwen runtime (`QwenCoderService`); runs answer generation, patch-plan generation, conversation summarization, and hosts the route-classifier contract. Name deliberately does not reference Apple FoundationModels — this is a local model."*
- Session IDs (`fm-route-classifier`, `fm-explanation`, etc.) renamed to `local-orch-*` to match.
- `AIOrchestrator.foundationModel` property kept as a deprecated alias returning the renamed type so existing views compile; a new `localOrchestrationModel` property is added as the canonical accessor.
- All references across `ChatView`, `SettingsView`, tests, etc. updated to the new name; the deprecated alias covers anything missed.

## 4. Unify model storage with one canonical resolver

New `**ModelLocationResolver**` service:

- Single public method: `func locate(modelID:) -> ResolvedModelLocation?` returning `{ url, sizeBytes, lastVerified }`. Callers never have to know whether the file was downloaded by the app or placed manually in Files.
- Internally consults one canonical manifest (`Documents/Models/.manifest.json`) that tracks every known `.gguf` the app is aware of — entries added both by `ModelDownloadService` (after successful download) and by a new "scan on launch" step that catalogs any user-placed files in `Documents/Models/`.
- All existing call sites migrate:
  - `ModelRegistry.isModelInstalledInExternalModelsFolder(modelID:)` and `resolvedLocalModelName(for:)` become thin wrappers over the resolver, marked deprecated.
  - `LocalOrchestrationModel.refreshStatus` uses the resolver.
  - `ModelDownloadService` writes to the resolver's manifest after a completed download instead of maintaining its own state.
  - `QwenCoderService` receives a resolved URL from the coordinator instead of building its own path.
- Old layouts (Application Support, `EmbeddingModels/`, scoped subfolders) are migrated and then removed on first launch — already partially in place, extended so the resolver owns it end-to-end.
- Tests: resolver returns the same `ResolvedModelLocation` regardless of whether the file arrived via download flow or was dropped into Files, with both paths exercised.

## 5. Agent runtime as the center; patching as one action strategy

- New `**AgentActionStrategy` protocol** with variants implemented as concrete strategies: `CreateFileStrategy`, `UpdateFileStrategy`, `RenameStrategy`, `DeleteStrategy`, `PatchStrategy`. Each strategy knows how to execute its action against the workspace through a shared mutation context.
- `PatchEngine` becomes the backend of `PatchStrategy` only — it is no longer called directly from `AIOrchestrator`/`RuntimeExecutionService`. Every workspace mutation funnels through `AgentRuntime` → strategy dispatch.
- `applyPatch(_:)` on the facade is rewritten to build a single-action `AgentExecutionPlan` containing one `PatchStrategy` invocation and run it through `AgentRuntime`, preserving the existing public API and return type.
- `IntentPlanner` is updated so it produces `AgentPlannedAction`s tied to strategies rather than selecting "patch vs. goal-driven" at the top level; patch-backed flows become a mode of `PatchStrategy` selection.
- Execution traces updated: `.patchEngine` provider remains in telemetry but is emitted by `PatchStrategy`, not the orchestrator.

## Test coverage

- `AIOrchestratorContextAssemblyTests`, `WorkflowDiagnosticsTests`, `AgentRuntimeTests`, `ContextPolicyLoaderTests`, `ImportedWorkspaceFlowTests` — all keep passing via facade forwarders.
- New test files:
  - `ScoredIntentRouteClassifierTests` — signal-by-signal and tie-break coverage.
  - `ModelLocationResolverTests` — downloaded vs. user-placed equivalence, manifest round-trip, migration from old layouts.
  - `AgentActionStrategyTests` — each strategy executes correctly through `AgentRuntime`; patch strategy produces identical results to the previous direct `PatchEngine` call.
  - `LocalOrchestrationModelTests` (renamed from FM tests) — session IDs, status refresh via resolver.

## Out of scope

- No UI/UX changes.
- No change to model download UI, HuggingFace flows, or the Models screen.
- No change to public SwiftUI view APIs beyond property renames covered by deprecated aliases.
- No new external dependencies.

