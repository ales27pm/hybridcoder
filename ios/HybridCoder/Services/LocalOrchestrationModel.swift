import Foundation

/// Local orchestration LLM.
///
/// Backed by the Qwen runtime (`QwenCoderService`); runs answer generation,
/// patch-plan generation, conversation summarization, and hosts the
/// route-classifier contract. The name deliberately does *not* reference
/// Apple's `FoundationModels` framework — this is a local model, not an
/// Apple system LLM. The old `FoundationModelService` name is retained as
/// a deprecated typealias below until every call site has migrated.
typealias LocalOrchestrationModel = FoundationModelService
