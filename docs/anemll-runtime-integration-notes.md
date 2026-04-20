# ANEMLL runtime integration notes

This document records the remaining non-additive repository changes needed to finish the ANEMLL runtime path inside HybridCoder.

The branch already contains these additive files:

- `scripts/import_anemll_zip_into_hybridcoder.py`
- `ios/HybridCoder/Models/ANEMLL/ANEMLLModelPackageManifest.swift`
- `ios/HybridCoder/Services/ANEMLL/ANEMLLBundleImportService.swift`
- `ios/HybridCoder/Services/ANEMLL/ANEMLLCoderService.swift`
- `docs/anemll-import-patch-plan.example.json`

## 1. ModelRegistry.swift

Add a new runtime case:

```swift
case anemll
```

Add a new code-generation model id:

```swift
private let anemllCodeGenerationID = "anemll/imported-bundle"
```

Add a new entry inside `initialEntries`:

```swift
anemllCodeGenerationID: Entry(
    id: anemllCodeGenerationID,
    displayName: "ANEMLL Imported Bundle",
    capability: .codeGeneration,
    provider: .apple,
    runtime: .anemll,
    remoteBaseURL: nil,
    files: [],
    isAvailable: true,
    installState: .notInstalled,
    loadState: .unloaded
)
```

Teach `areCodeGenerationModelFilesInstalled(modelID:)` to treat imported ANEMLL bundles as installed when `ANEMLLBundleImportService.shared.importedBundles()` is non-empty.

## 2. AIOrchestrator.swift

Store an additional runtime service:

```swift
private(set) var anemllCoderService: ANEMLLCoderService?
```

Add helpers:

- `makeANEMLLCoderService(modelID:)`
- `ensureANEMLLServiceMatchesActiveModel()`
- `activeCodeGenerationRuntime()`
- `requireANEMLLCoder()`

Branch the code-generation path in these methods:

- `warmUpCodeGenerationModel(onProgress:)`
- `unloadCodeGenerationModel()`
- `generateCode(query:context:)`
- `streamText(query:context:route:onPartial:)` when `route == .codeGeneration`
- `generateExplanation(query:context:preferredProvider:)` when the preferred provider is `.qwenCodeAssistant`
- `streamExplanation(query:context:preferredProvider:onPartial:)` when the preferred provider is `.qwenCodeAssistant`

The branch file `ios/HybridCoder/Services/ANEMLL/ANEMLLCoderService.swift` is designed to be used as a drop-in parallel to `QwenCoderService`.

## 3. ModelManagerView.swift

The current model manager only renders one active code-generation card. To expose ANEMLL properly, the UI should:

- render every `.codeGeneration` model entry
- show which one is active
- allow the user to activate a different runtime via `modelRegistry.setActiveCodeGenerationModel(id:)`
- only show download controls for the Qwen/CoreMLPipelines path
- show bundle/import status for the ANEMLL path

## 4. project.pbxproj

Add these Swift package products to the HybridCoder target:

- `Yams`
- `Tokenizers`

`Tokenizers` should come from the existing `swift-transformers` package reference.
`Yams` should be added as a new package reference.

## 5. Import flow

For a full end-to-end setup, the intended flow is:

1. run `scripts/import_anemll_zip_into_hybridcoder.py` in a local clone of `hybridcoder`
2. copy ANEMLL core sources into `ios/HybridCoder/Services/ANEMLLCore/`
3. keep the additive bridge files already present in this branch
4. apply the non-additive rewrites described in this document
5. build and fix any compile drift caused by upstream changes in HybridCoder

## Why this document exists

The GitHub connector accepted all additive ANEMLL files, but the existing-file rewrite path was unreliable during this session. These notes preserve the exact remaining integration work so the branch stays useful and coherent.
