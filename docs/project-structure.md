# Project Structure

This document describes the target repository layout for the refactor.

## Main boundaries

- `App/` — app entry and bootstrapping
- `Models/` — stable domain models
- `Templates/` — Expo template manifests and builders
- `Services/` — orchestration, RN analysis, preview, storage, patching
- `ViewModels/` — workflow state
- `Views/` — SwiftUI presentation
- `Legacy/` — temporary holding area during migration

## Migration rule

Move one subsystem at a time, keep the repo buildable, then delete obsolete files only after the new path is working.
