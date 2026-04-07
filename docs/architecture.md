# Architecture

This document is the canonical source for the split between the **current implementation** and the **target architecture**.

## Current implementation

HybridCoder is currently a SwiftUI iOS app with:

- local orchestration
- semantic retrieval
- patch planning and application
- project and workspace persistence
- imported repository handling
- a prototype-oriented editing flow

## Target architecture

The target product is a local-first React Native and Expo builder with these core subsystems:

1. Studio shell
2. Project studio
3. React Native workspace analysis
4. AI orchestration
5. Template system
6. Preview system

## How these docs fit together

- `docs/product-vision.md` — product goals, non-goals, and scope
- `docs/project-structure.md` — target repository layout and migration boundaries
- `docs/template-system.md` — template and scaffold strategy
- `docs/preview-system.md` — preview constraints and staged preview plan
- `docs/roadmap.md` — phased refactor order

Read this file first, then use the linked docs to go deeper into each subsystem.

## Documentation rule

Preview should not be described as solved until the runtime story is genuinely strong enough to support that claim.
