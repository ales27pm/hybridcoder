# Fix Critical Gaps: Model Pipeline, Semantic Search, Patch Preview, Context Sources & Syntax Highlighting

## Summary

Address the critical/blocking issues identified in the codebase audit: fix the model download pipeline, wire true semantic search with CodeBERT embeddings, add proper patch diff previews, show context sources in chat, add syntax highlighting to the file viewer, and wire conversation memory summarization properly.

---

## 1. Model Storage Migration (Documents → Application Support)

**What changes:**

- Downloaded models currently go to `Documents/EmbeddingModels/`. They'll move to `Application Support/HybridCoder/Models/` instead — this is the correct location for app-managed data that shouldn't be visible to the user.
- Automatic migration: on first launch after the update, existing models in the old location are moved to the new location seamlessly.
- `ModelRegistry.downloadedModelsRoot` and `BundledEmbeddingAssets` updated to point to Application Support.

---

## 2. Qwen Model Registry & Download Pipeline

**What changes:**

- The Qwen registry entry currently has empty `remoteBaseURL` and `files`, so it can't be downloaded through the same pipeline as CodeBERT.
- Populate the registry with the correct GGUF-based Qwen model metadata and list required files expected in `Files > On My iPhone > Hybrid Coder > Models/` (GGUF weights plus tokenizer assets).
- `ModelDownloadService` validates and indexes externally managed Qwen model assets from the Files app location, then hands off to `QwenCoderService.warmUp()` for llama.cpp session prewarm.
- The Model Manager screen's runtime flow now focuses on refresh/validation + warm-up for local llama.cpp models in the external Files app folder, with explicit availability and health feedback.
- No Core ML pipeline fallback remains; runtime availability depends on GGUF model files being present in the external Models folder.

---

## 3. Semantic Search: Wire CodeBERT Embeddings Properly

**What changes:**

- The `SemanticSearchIndex` already stores and queries embedding vectors via `LlamaEmbeddingService` — this is working correctly. The search uses both vector similarity and lexical BM25 search, fused via Reciprocal Rank Fusion.
- **Fix:** The `gatherContext()` method in `AIOrchestrator` silently swallows search failures. If the embedding model isn't loaded, it falls back to just sampling random files — with no indication to the user that semantic search wasn't used.
- Add a `contextSources` field to `AssistantResponse` that records which files/chunks were retrieved and whether semantic search vs. fallback was used.
- When the embedding model is not loaded but the index exists, show a clear warning in the chat: "Semantic search unavailable — using file sampling. Download the embedding model for better results."
- Expose index health in the chat empty state: whether embeddings are loaded, how many chunks are indexed, and the last index time.

---

## 4. Context Sources in Chat UI

**What changes:**

- Add a new `ContextSource` model that tracks: file path, line range, retrieval method (semantic search, file hint, fallback sample), and relevance score.
- `AssistantResponse` gains a `contextSources: [ContextSource]` field populated during `gatherContext()`.
- `ChatMessage` gains a `contextSources` field.
- In the `MessageBubble`, a new collapsible "Sources" section appears below the assistant's response, showing which files were used as context with their retrieval method (semantic match, route hint, or fallback).
- Tapping a source navigates to that file in the file viewer.
- This gives users transparency into what the AI "saw" when answering.

---

## 5. Patch Preview & Diff Viewer Improvements

**What changes:**

- The `PatchPreviewView` already exists with a proper unified diff viewer showing before/after with line numbers, color-coded additions/removals, and context lines. This is well-implemented.
- **Fix:** The patch preview is not easily discoverable from the chat flow. Currently the user has to navigate to the Patches tab and manually tap each operation.
- Wire the patch preview inline: when a patch plan is proposed in chat, each operation in the `PatchListView` gets a "Preview" button that opens `PatchPreviewView` as a sheet.
- Add a "Preview All" option that shows a scrollable unified diff of all operations in the plan before applying.
- Add validation warnings inline: before applying, run `PatchEngine.validate()` and show any issues (search text not found, multiple matches) directly in the preview.

---

## 6. Basic Syntax Highlighting in File Viewer

**What changes:**

- The `FileViewerView` currently uses a plain `TextEditor` with monospaced font — no syntax highlighting.
- Add a `SyntaxHighlighter` utility that applies `AttributedString` coloring for common token types: keywords, strings, comments, numbers, and types.
- Support the most common languages in the codebase: Swift, JavaScript/TypeScript, Python, HTML/CSS, JSON, YAML, Markdown.
- Use regex-based tokenization (lightweight, no external dependencies) to identify token types and apply semantic colors from the app's theme.
- Replace the plain `TextEditor` with a read-only `Text(attributedString)` view for syntax-highlighted display, keeping the editable `TextEditor` for edit mode.
- The highlighting uses the existing dark theme colors (green for strings, orange for keywords, gray for comments, cyan for types, purple for numbers).

---

## 7. Conversation Memory Summarization Wiring

**What changes:**

- The summarization infrastructure already exists: `FoundationModelService.summarizeConversationMemory()`, `ChatViewModel.compactConversationMemoryIfNeeded()`, and `AIOrchestrator.summarizeConversationForCompaction()` are all implemented and wired.
- **Fix:** The compaction threshold (900 estimated tokens) is quite high relative to the context budget (700 max conversation budget), meaning compaction often doesn't trigger early enough.
- Lower the compaction threshold to 600 tokens so summarization kicks in sooner.
- Add a visual indicator in the chat when conversation memory has been compacted — a subtle system message like "Earlier messages summarized to save context space."
- Show the current memory usage estimate in the chat input bar (e.g. "3/7 context budget used") so users understand when they're approaching limits.

---

## Files Changed

**New files:**

- `Models/ContextSource.swift` — context source tracking model
- `Utilities/SyntaxHighlighter.swift` — regex-based syntax highlighting
- `Views/PatchPreviewAllView.swift` — scrollable multi-operation diff preview

**Modified files:**

- `Services/BundledEmbeddingAssets.swift` — update paths to Application Support
- `Services/ModelRegistry.swift` — populate Qwen files/URL, update storage root
- `Services/ModelDownloadService.swift` — add code generation model download, storage migration
- `Services/AIOrchestrator.swift` — track context sources in gatherContext(), fix silent search failures
- `Models/AssistantResponse.swift` — add contextSources field
- `Models/ChatMessage.swift` — add contextSources field
- `ViewModels/ChatViewModel.swift` — pass context sources, adjust compaction threshold, add memory indicator
- `Views/MessageBubble.swift` — add collapsible Sources section
- `Views/ChatView.swift` — add memory usage indicator in input bar
- `Views/FileViewerView.swift` — add syntax-highlighted read mode
- `Views/PatchListView.swift` — add Preview button per operation
- `Views/ModelManagerView.swift` — update Qwen card to use new download flow

