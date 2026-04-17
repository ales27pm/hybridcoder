# pi-mono `packages/coding-agent` adoption analysis for HybridCoder

Date: 2026-04-03

Runtime summary (as of 2026-04-17): HybridCoder runtime calls map to `QwenCoderService` and `FoundationModelService`, both backed by SpeziLLM/SpeziLLMLocal + llama.cpp, with model discovery anchored to `Files > On My iPhone > Hybrid Coder > Models/` (`ModelRegistry.externalModelsRoot`).

## Scope reviewed

I reviewed the following upstream sources from `badlogic/pi-mono`:

- Package overview and capabilities: `packages/coding-agent/README.md`
- Skill system behavior/spec alignment: `packages/coding-agent/docs/skills.md` and `src/core/skills.ts`
- Prompt template behavior: `packages/coding-agent/docs/prompt-templates.md` and `src/core/prompt-templates.ts`
- Context/resource loading: `src/core/resource-loader.ts`
- Session memory management: `docs/compaction.md` and `src/core/compaction/compaction.ts`
- Operational reliability patterns: `src/core/tools/file-mutation-queue.ts`, `src/core/event-bus.ts`, `src/core/diagnostics.ts`

## What is directly reusable for HybridCoder

HybridCoder is an iOS-first Swift app using SpeziLLM/SpeziLLMLocal + llama.cpp services for local orchestration and generation. We should reuse **patterns and algorithms**, not TypeScript runtime internals.

### 1) Hierarchical context-file loading (high value, low-medium effort)

**Upstream idea:** `resource-loader.ts` walks from CWD to filesystem root and loads context files (`AGENTS.md`, `CLAUDE.md`) in deterministic order. It also keeps global+project scope separation.

**Why it fits HybridCoder:** We already depend on repo context quality when building prompts (`PromptBuilder`) and routing (`AIOrchestrator.gatherContext`). Adding hierarchical instruction loading can materially improve correctness for repo-specific coding conventions.

**Recommended adaptation:**
- Add a Swift `ContextPolicyLoader` service that:
  - starts from selected repo root;
  - traverses ancestors up to root;
  - loads `AGENTS.md` (and optionally `CLAUDE.md`) in precedence order;
  - returns normalized blocks with source path metadata.
- Inject the resulting policy blocks into system prompts assembled by `PromptBuilder`.

### 2) Prompt-template command system (high value, medium effort)

**Upstream idea:** prompt templates are Markdown files with frontmatter metadata and argument interpolation (`$1`, `$@`, `${@:N}`).

**Why it fits HybridCoder:** Users repeat prompt patterns (e.g., “review file”, “generate patch plan”). A lightweight template layer would improve UX and reduce repetitive typing while preserving current architecture.

**Recommended adaptation:**
- Add project-level templates directory (for example `.hybridcoder/prompts/`).
- Implement argument substitution semantics compatible with the upstream template syntax.
- Surface templates in chat composer quick actions (future UI enhancement).

### 3) Per-file mutation serialization (medium value, low effort)

**Upstream idea:** `withFileMutationQueue()` serializes mutations per canonical file path while allowing parallel writes across different files.

**Why it fits HybridCoder:** Our patch flow can apply multiple operations and then rebuild the index. Serializing writes per file would reduce race-condition risk if we parallelize patch application later.

**Recommended adaptation:**
- Add an actor-based mutation queue keyed by canonical file URL in `PatchEngine`.
- Wrap file write/replace operations so same-file edits are strictly ordered.

### 4) Structured diagnostics model for extension/resource collisions (medium value, low effort)

**Upstream idea:** a typed diagnostics model (`warning`, `error`, `collision`) for loaded resources.

**Why it fits HybridCoder:** As we add templates/context policies/plugins, we will need deterministic, user-visible diagnostics in Settings.

**Recommended adaptation:**
- Create `ResourceDiagnostic`/`ResourceCollision` Swift models.
- Emit diagnostics from context/template discovery and show them in Settings.

### 5) Context compaction strategy (medium-high value, medium-high effort)

**Upstream idea:** when token budgets are exceeded, summarize old conversation segments and preserve recent messages, including file-operation summaries.

**Why it fits HybridCoder:** long iOS sessions will eventually hit context limits. This is a robust pattern for preserving continuity without sending full history.

**Recommended adaptation:**
- Add a conversation transcript manager with token budget checks.
- Summarize older turns into a `CompactionEntry` equivalent using the local Qwen runtime services.
- Preserve recent turns and include a compacted summary segment in future prompts.

## What we should *not* directly port

- Terminal/TUI command stack, slash-command router, and CLI-specific runtime lifecycle.
- Provider/account abstractions not needed for our current SpeziLLM/SpeziLLMLocal + llama.cpp design.
- Package-manager-driven extension discovery at npm scale (too heavy for current app scope).

## Suggested implementation order for HybridCoder

1. **Context policy loading** integrated into `PromptBuilder`/`AIOrchestrator`.
2. **Prompt template loader + parser** for reusable prompts.
3. **PatchEngine per-file mutation queue** for write safety.
4. **Diagnostics surface** in Settings.
5. **Conversation compaction** once message history persistence expands.

## Licensing note

`pi-mono` is MIT licensed. Reusing concepts and small adapted implementations is compatible if we preserve attribution and keep copied code sections clearly tracked during import.

## Bottom line

Yes—there are multiple parts we can productively use in HybridCoder right now. The best immediate wins are:

- hierarchical context-file loading,
- prompt-template expansion,
- file-mutation serialization,
- typed resource diagnostics.

Compaction is also a strong follow-up once long-session memory becomes a bigger concern.
