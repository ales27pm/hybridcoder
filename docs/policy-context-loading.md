# Hierarchical Policy Context Loading

HybridCoder automatically discovers repository policy files and injects them into model prompts as a dedicated `<policy_context>` block.

## Supported policy files

The policy loader currently reads these exact file names:

- `AGENTS.md`
- `CLAUDE.md`

## Discovery rules

1. The orchestrator chooses a **working context directory**:
   - repo root by default, or
   - a subdirectory derived from the active file/folder via `setPolicyWorkingContext(_:)`.
2. `ContextPolicyLoader` crawls upward from that directory to the repository root boundary.
3. At each directory level, files are loaded in deterministic order (`AGENTS.md`, then `CLAUDE.md`).
4. Files are rendered root-to-leaf so broader policies appear before deeper, more specific policies.

## Prompt injection behavior

- Loaded policies are stored in `ContextPolicySnapshot`.
- `renderForPrompt(maxCharacters:)` formats each file as:
  - `--- POLICY FILE: <relative path> ---`
  - followed by the file contents.
- Prompt assembly wraps the rendered policy text inside:

```xml
<policy_context>
...
</policy_context>
```

## Budgeting and truncation

Budget values are defined in one source-of-truth enum, `PromptContextBudget`, in `ios/HybridCoder/Services/AIOrchestrator.swift`.

Current values:

- `foundationContextCap = 2000`
- `qwenContextCap = 32000`
- `downstreamContextCap = foundationContextCap`
- `minimumCodeContextBudget = 1100`
- `maximumPolicyContextBudget = 350`
- `maximumConversationContextBudget = 400`
- `qwenMinimumCodeContextBudget = 26000`
- `qwenMaximumPolicyContextBudget = 2000`
- `qwenMaximumConversationContextBudget = 2000`

When all sections are present, code reservation is enforced first, then policy and conversation are clipped to the remaining non-code budget. Foundation Models use the smaller `foundationContextCap` to avoid context-limit failures. Qwen-backed code generation and codebase explanation prompts use the larger `qwenContextCap`.

## Diagnostics and safety

Policy discovery warnings are surfaced as `DiscoveryDiagnostic.warning` and shown in Settings.

Warnings are emitted when:

- a policy file resolves outside the repository boundary (for example, symlink escapes), or
- a discovered policy file cannot be read.

The loader also logs warnings via `Logger` with the policy file name and reason.
