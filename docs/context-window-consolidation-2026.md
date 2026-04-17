# Context Window Consolidation for HybridCoder (2026)

This document consolidates the context-window investigation and the practical implementation guidance gathered while analysing HybridCoder's current architecture.

## Current state in HybridCoder

Runtime summary (as of 2026-04-17): the current local runtime stack is SpeziLLM/SpeziLLMLocal + llama.cpp (see `QwenCoderService` and `FoundationModelService`), and runtime model files are expected in `Files > On My iPhone > Hybrid Coder > Models/` via `ModelRegistry.externalModelsRoot`.

HybridCoder now uses a split strategy:

- SpeziLLM/SpeziLLMLocal + llama.cpp power local orchestration and generation paths.
- Qwen 2.5 Coder services handle code generation, repository-grounded explanations, and patch planning flows.
- `PromptContextBudget` currently sets:
  - `foundationContextCap = 2000`
  - `qwenContextCap = 32_000`
  - `downstreamContextCap = 2000`
  - `minimumCodeContextBudget = 1100`
  - `maximumPolicyContextBudget = 350`
  - `maximumConversationContextBudget = 550`
  - `qwenMinimumCodeContextBudget = 26_000`
  - `qwenMaximumPolicyContextBudget = 2_000`
  - `qwenMaximumConversationContextBudget = 2400`
- `ChatViewModel` currently compacts memory aggressively:
  - `maxConversationTokens = 2400`
  - `compactionThreshold = 1200`
  - `preservedRecentTurnCount = 6`

This is a better working baseline than the previous safety-first settings, but there is still room to improve how retained memory, prompt packing, and retrieval interact.

## Consolidated strategy

The best practical path is not a single bigger number. It is a layered system:

1. Keep orchestration prompts compact while staying on the SpeziLLM/SpeziLLMLocal + llama.cpp runtime.
2. Keep Qwen on code-heavy and repository-heavy work.
3. Increase effective context before trying to brute-force raw context.
4. Pack prompts by token budget rather than character count whenever possible.
5. Preserve hot task state separately from older conversation history.
6. Use retrieval and summarisation to select the right code, not the most code.

## Recommended implementation order

### Phase 1 — Low-risk, high-impact budget tuning

Raise chat memory thresholds so HybridCoder stops compacting too early.

`ChatViewModel.maxConversationTokens` controls how much conversation history the app retains before compaction. `PromptContextBudget.maximumConversationContextBudget` and `PromptContextBudget.qwenMaximumConversationContextBudget` in `ios/HybridCoder/Services/AIOrchestrator.swift` control how much of that retained history is actually allowed into each prompt. Those values need to move together or the extra retained memory never reaches the model.

Recommended first-pass values:

- `ChatViewModel.maxConversationTokens`: `1400 -> 2400`
- `ChatViewModel.compactionThreshold`: `600 -> 1200`
- `ChatViewModel.preservedRecentTurnCount`: `4 -> 6`
- `PromptContextBudget.maximumConversationContextBudget`: `400 -> 550`
- `PromptContextBudget.qwenMaximumConversationContextBudget`: `2000 -> 2400`

Notes:

- `550` is the practical orchestration ceiling under the current `foundationContextCap`, `minimumCodeContextBudget`, and `maximumPolicyContextBudget` values.
- Qwen can absorb the full `2400` retained-chat target without starving code context.
- Larger Orchestration conversation slices should wait for Phase 3 token-aware repacking rather than squeezing code budget further with character-based clipping.

Why:

- Current compaction no longer starts as early as before, so multi-step debugging sessions keep more working memory alive.
- The prompt budget now matches the retained-memory intent instead of truncating it back down at dispatch time.
- This is still a relatively safe change because it stays inside the existing downstream caps.

### Phase 2 — Add pinned task memory

Introduce explicit pinned context that survives compaction and outranks older turns.

Suggested `ConversationMemoryContext` additions:

- `activeTaskSummary`
- `activeFiles`
- `activeSymbols`
- `latestBuildOrRuntimeError`
- `pendingPatchSummary`

Rules:

- Pinned task memory is always injected before generic older-turn memory.
- Compaction must never discard the current task objective.
- File-operation summaries should remain separate from task state.

Why:

- Coding sessions fail more often from losing the current goal than from losing random old chat turns.
- This increases effective context without needing a bigger model window.

### Phase 3 — Token-aware packing instead of character clipping

Current prompt assembly is mostly character-based. Replace this with model-aware token packing.

Suggested design:

- Add a tokenizer-aware prompt budget service.
- Budget sections in priority order:
  1. system prompt
  2. handler/route markers
  3. pinned task memory
  4. recent turns
  5. policy context
  6. retrieved code chunks
  7. low-priority fallback samples
- Reserve explicit output headroom.

Why:

- Character counts are a crude approximation.
- Token-aware packing uses the real model window more efficiently.
- It reduces accidental over-truncation and keeps hot context intact.

### Phase 4 — Expand retrieval quality before expanding raw prompt size again

Improve code selection rather than simply adding more code to prompts.

Recommended upgrades:

- Symbol-aware retrieval
- Caller/callee expansion for matched functions
- Import-neighbour expansion for matched files
- Route-specific `topK`
- Score blending using:
  - semantic score
  - active-file proximity
  - recent edit recency
  - file importance

Why:

- Bigger prompts with weak selection still waste context.
- Better retrieval usually beats larger raw prompt assembly.

### Phase 5 — Route more large explanation work onto Qwen

HybridCoder already routes repository-grounded explanations to Qwen. Continue that policy.

Extend the provider policy for:

- long debugging questions
- questions mentioning multiple files or multiple symbols
- architecture walkthroughs crossing subsystem boundaries
- explanation requests that include several logs, stack traces, or referenced context sources

Potential future extension:

- add a Qwen-backed large-context patch-planning path for multi-file change proposals

Why:

- The orchestration path remains the right tool for short structured reasoning.
- Qwen excels at large code-context work.
- This preserves stability while raising effective usable context.

### Phase 6 — Add serving/runtime performance features

If the runtime stack supports them, add:

- prefix caching
- KV reuse for repeated long prefixes
- chunked prefill for long repository contexts
- hierarchical KV storage if the execution stack grows beyond simple local inference

Why:

- These features do not increase the theoretical token limit.
- They make long-context behaviour fast enough to use in practice.

## Recommended file targets in HybridCoder

### `ios/HybridCoder/ViewModels/ChatViewModel.swift`

Apply Phase 1 first:

- raise memory thresholds
- keep more recent turns
- keep summary notification behaviour

Then Phase 2:

- track pinned task state separately from generic recent turns
- build `ConversationMemoryContext` from pinned state + recent turns + file operation summaries

### `ios/HybridCoder/Models/ConversationMemoryContext.swift`

Extend the memory model to support:

- pinned task state
- explicit rendering priority
- independent caps for:
  - pinned memory
  - recent turns
  - file operation summaries
  - historical compaction summary

### `ios/HybridCoder/Services/AIOrchestrator.swift`

Apply:

- token-aware prompt packing
- route-specific prompt assembly priorities
- better retrieval scoring and neighbour expansion
- stronger `preferredExplanationProvider` heuristics for multi-file, multi-symbol, architecture, and multi-source debugging prompts
- optional Qwen patch-planning path for large code contexts

### `ios/HybridCoder/Services/PromptBuilder.swift`

Update prompt construction to:

- accept token-budgeted sections
- distinguish hot task context from colder historical memory
- preserve exact wrapper tags after clipping

## What not to do first

Avoid starting by trying to force orchestration prompts to carry much larger repo context.

Refrain from model-level RoPE-extension experiments inside app orchestration code.

Do not assume the advertised long-context length of any model is sufficient on its own.

Raw context length helps, but retrieval quality, memory shape, and packing discipline matter more for a coding assistant.

## Practical recommendation

The next concrete code change should be:

1. tune `ChatViewModel` thresholds upward
2. tune `PromptContextBudget` conversation slices to match that retained-memory strategy
3. add pinned task memory
4. replace character-budget packing with token-budget packing

That sequence gives the best immediate improvement with the lowest architectural risk.
