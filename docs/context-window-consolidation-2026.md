# Context Window Consolidation for HybridCoder (2026)

This document consolidates the context-window investigation and the practical implementation guidance gathered while analysing HybridCoder's current architecture.

## Current state in HybridCoder

HybridCoder now uses a split strategy:

- Apple Foundation Models stay on small, context-sensitive orchestration paths.
- Qwen via CoreMLPipelines handles code generation and repository-grounded explanations.
- `PromptContextBudget` currently sets:
  - `foundationContextCap = 2000`
  - `qwenContextCap = 32000`
  - `maximumConversationContextBudget = 400`
  - `qwenMaximumConversationContextBudget = 2000`
- `ChatViewModel` currently compacts memory aggressively:
  - `maxConversationTokens = 1400`
  - `compactionThreshold = 600`
  - `preservedRecentTurnCount = 4`

This is a good safety-first baseline, but it still leaves a lot of effective context capacity unused during coding sessions.

## Consolidated strategy

The best practical path is not a single bigger number. It is a layered system:

1. Keep Foundation Models on the smallest orchestration paths.
2. Keep Qwen on code-heavy and repository-heavy work.
3. Increase effective context before trying to brute-force raw context.
4. Pack prompts by token budget rather than character count whenever possible.
5. Preserve hot task state separately from older conversation history.
6. Use retrieval and summarisation to select the right code, not the most code.

## Recommended implementation order

### Phase 1 — Low-risk, high-impact budget tuning

Raise chat memory thresholds so HybridCoder stops compacting too early.

Recommended first-pass values:

- `ChatViewModel.maxConversationTokens`: `1400 -> 2200` or `2400`
- `ChatViewModel.compactionThreshold`: `600 -> 1000` or `1200`
- `ChatViewModel.preservedRecentTurnCount`: `4 -> 6`

Why:

- Current compaction starts before the chat has consumed most of the practical budget.
- The assistant loses working memory too early during debugging and multi-step edits.
- This is the safest immediate quality improvement.

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
- questions mentioning multiple files/symbols
- architecture walkthroughs crossing subsystem boundaries
- explanation requests with many context sources

Potential future extension:

- add a Qwen-backed large-context patch-planning path for multi-file change proposals

Why:

- Foundation remains the right tool for short structured reasoning.
- Qwen remains the right tool for large code-context work.
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
- optional Qwen patch-planning path for large code contexts

### `ios/HybridCoder/Services/PromptBuilder.swift`

Update prompt construction to:

- accept token-budgeted sections
- distinguish hot task context from colder historical memory
- preserve exact wrapper tags after clipping

## What not to do first

Do not start by trying to force Foundation Models to carry much larger repo context.

Do not start with model-level RoPE-extension experiments inside app orchestration code.

Do not assume the advertised long-context length of any model is enough on its own.

Raw context length helps, but retrieval quality, memory shape, and packing discipline matter more for a coding assistant.

## Practical recommendation

The next concrete code change should be:

1. tune `ChatViewModel` thresholds upward
2. add pinned task memory
3. replace character-budget packing with token-budget packing

That sequence gives the best immediate improvement with the lowest architectural risk.
