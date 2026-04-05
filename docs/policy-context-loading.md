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

During context assembly, HybridCoder applies these limits:

- **2,500 chars total** downstream context cap
- **at least 1,600 chars reserved for code context**
- **up to 700 chars for policy context**
- **up to 1,000 chars for conversation memory**

When all sections are present, code reservation is enforced first, then policy and conversation are clipped to the remaining non-code budget.

## Diagnostics and safety

Policy discovery warnings are surfaced as `DiscoveryDiagnostic.warning` and shown in Settings.

Warnings are emitted when:

- a policy file resolves outside the repository boundary (for example, symlink escapes), or
- a discovered policy file cannot be read.

The loader also logs warnings via `Logger` with the policy file name and reason.
