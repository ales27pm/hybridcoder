# ANEMLL -> HybridCoder import system

This import system is built for the current `ales27pm/hybridcoder` repository layout and the uploaded `Anemll-main.zip` archive layout.

## What it does

The importer at `scripts/import_anemll_zip_into_hybridcoder.py` turns the ANEMLL zip into a HybridCoder source integration.

It performs seven concrete steps:

1. validates that the target repository matches the current HybridCoder iOS/Xcode layout
2. unpacks the ANEMLL zip and finds `anemll-swift-cli/Sources/AnemllCore`
3. vendors the ANEMLL Swift runtime into `ios/HybridCoder/Services/ANEMLLCore/`
4. generates HybridCoder-side ANEMLL bridge files in:
   - `ios/HybridCoder/Services/ANEMLL/ANEMLLCoderService.swift`
   - `ios/HybridCoder/Services/ANEMLL/ANEMLLBundleImportService.swift`
   - `ios/HybridCoder/Models/ANEMLL/ANEMLLModelPackageManifest.swift`
5. patches `ios/HybridCoder.xcodeproj/project.pbxproj` to add `Yams` and `Tokenizers`
6. patches `ModelRegistry.swift`, `AIOrchestrator.swift`, and `ModelManagerView.swift` to register the ANEMLL runtime path
7. appends importer documentation to the repository `README.md`

## Expected inputs

- HybridCoder repo root
- the uploaded ANEMLL zip archive

Example:

```bash
python3 scripts/import_anemll_zip_into_hybridcoder.py \
  --zip /absolute/path/to/Anemll-main.zip \
  --repo-root /absolute/path/to/hybridcoder \
  --report /absolute/path/to/anemll-import-report.txt
```

## Assumptions baked into the importer

This importer is intentionally opinionated.

It assumes the current HybridCoder repo still contains these files:

- `ios/HybridCoder.xcodeproj/project.pbxproj`
- `ios/HybridCoder/Services/ModelRegistry.swift`
- `ios/HybridCoder/Services/AIOrchestrator.swift`
- `ios/HybridCoder/Views/ModelManagerView.swift`

It also assumes the uploaded ANEMLL archive still contains:

- `anemll-swift-cli/Sources/AnemllCore/*.swift`

## Important limits

This is a source-integration system, not a remote code executor.

The GitHub connector can write the importer into the repo branch, but it cannot execute the importer inside your GitHub repository checkout. Run the importer in a local clone of `hybridcoder`, then build and fix any compile drift introduced by upstream changes after the importer was written.

## Why this route

The repository already has a working code-generation/runtime spine around `AIOrchestrator`, `ModelRegistry`, and the model manager UI. The importer is designed to land ANEMLL into that spine directly instead of leaving it as a detached side package.
