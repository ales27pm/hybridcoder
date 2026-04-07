# Architecture

This repository now documents two things separately:

- the current implementation
- the target builder architecture

## Current implementation

HybridCoder is currently a SwiftUI iOS app with:

- local orchestration
- semantic retrieval
- patch planning and application
- project and workspace persistence
- imported repo handling
- a prototype-oriented editing flow

## Target architecture

The target product is a local-first React Native and Expo builder with these core subsystems:

1. Studio shell
2. Project studio
3. React Native workspace analysis
4. AI orchestration
5. Template system
6. Preview system

## Key rule

Preview should not be described as solved until the runtime story is genuinely strong enough to support that claim.
