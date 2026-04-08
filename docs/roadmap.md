# Roadmap

## Phase 1
Split app-wide state from workspace state and lock the product identity around Expo and React Native.

## Phase 2
Replace the project model and template layer.

## Phase 3
Specialize orchestration for React Native and Expo.

## Phase 4
Replace the old sandbox with a preview coordinator and diagnostics flow.

## Phase 5
Treat imported Expo repositories as first-class projects.

## Phase 6
Implement the bytecoding runtime: introduce an agent layer that can turn user intent into a sequence of guarded coding actions.

### Phase 6 target capabilities

- intent decomposition
- execution planning
- first-class file actions
- iterative apply, validate, and retry loops
- transition from chat request to real workspace progress

## Phase 7
Delete obsolete files and finish the documentation and code alignment.

## Anti-drift note

At every phase, `docs/architecture.md` should remain the canonical source for:

- what is already implemented
- what is still missing
- what the product is supposed to become

## Status note

The repository now has partial progress inside several phases:

- Phase 2 is underway through `StudioProject` and manifest-driven Expo scaffolds
- Phase 4 is underway through structural preview coordination and diagnostics
- Phase 5 is underway through an Expo-first imported workspace path with generic repo fallback
- Phase 6 is underway through a planner/coordinator layer on top of the existing guarded patch runtime

Those phase starts should not be mistaken for completion. The remaining gaps are still the full builder project migration, richer scaffold breadth, stronger preview/runtime truthfulness in every screen, and a more complete bytecoding execution loop.
