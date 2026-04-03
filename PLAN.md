# HybridCoder — Local-First AI Coding Assistant for iOS

## Features

- **Import code repositories** from the Files app, with persistent access so the app remembers your folders across launches
- **Browse source files** in a sidebar file tree — tap to view code with syntax-highlighted previews
- **Ask coding questions** against your imported repo in a chat interface powered by Apple's on-device AI
- **AI-powered code generation** using Apple Foundation Models (Apple Intelligence) running entirely on-device
- **Semantic code search** using CodeBERT embeddings — find relevant code by meaning, not just keywords
- **Plan and apply patches** — the AI proposes exact-match find-and-replace edits that you review and apply deterministically
- **Model download manager** — on first launch, download the CoreML embedding model from a configurable URL with progress tracking
- **Fully offline** — all AI inference runs on-device, no cloud required

## Design

- **Dark theme** inspired by Xcode and terminal editors — dark backgrounds with a green accent color for that classic code editor feel
- **Monospaced typography** for code, SF Pro for UI text
- **Sidebar navigation** — file tree on the left, main content (chat, file viewer, patches) on the right
- Code blocks rendered with dark card backgrounds and green-tinted syntax
- Clean, minimal chrome — content is king
- Haptic feedback on patch apply, message send, and model readiness
- Smooth spring animations for sidebar transitions and chat messages

## Screens

- **Sidebar** — collapsible file tree showing the imported repository structure, with folder expand/collapse and file type icons
- **Chat** — main conversation view where you ask questions about your code; messages stream in with AI responses; code blocks are formatted with monospace styling
- **File Viewer** — tap a file in the sidebar to view its contents with line numbers and monospace font
- **Patches** — review proposed code changes as diff-style cards; approve or reject each patch individually
- **Settings** — configure model download URLs, view model status (downloaded / downloading / not available), manage imported repositories, clear index
- **Model Manager** — shows Foundation Models availability and CodeBERT download progress, with retry on failure

## App Icon

- Dark background with a subtle green-to-teal gradient
- A terminal cursor or code bracket symbol (`{ }`) in bright green, suggesting code + AI
- Clean, minimal, professional — matches the dark + green code editor aesthetic
