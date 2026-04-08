import Foundation

nonisolated struct AgentWorkspaceContext: Sendable {
    let kind: Kind
    let projectName: String
    let projectKind: ProjectKind?
    let entryFile: String?
    let hasExpoRouter: Bool
    let dependencies: [String]

    nonisolated enum Kind: String, Sendable {
        case prototype
        case importedExpo
        case importedGeneric
        case unknown
    }

    var isExpoFocused: Bool {
        kind == .prototype || kind == .importedExpo || projectKind?.isExpo == true
    }

    var displayName: String {
        switch kind {
        case .prototype:
            return "Prototype Expo workspace"
        case .importedExpo:
            return "Imported Expo workspace"
        case .importedGeneric:
            return "Imported generic workspace"
        case .unknown:
            return "Unknown workspace"
        }
    }
}

nonisolated struct AgentExecutionPlan: Sendable {
    let goal: String
    let workspace: AgentWorkspaceContext
    let steps: [AgentExecutionStep]
}

nonisolated struct AgentExecutionStep: Identifiable, Sendable {
    let id: UUID
    let title: String
    let action: AgentWorkspaceAction
    let status: Status
    let detail: String

    nonisolated enum Status: String, Sendable {
        case planned
        case running
        case succeeded
        case blocked
        case skipped
    }

    init(
        id: UUID = UUID(),
        title: String,
        action: AgentWorkspaceAction,
        status: Status,
        detail: String
    ) {
        self.id = id
        self.title = title
        self.action = action
        self.status = status
        self.detail = detail
    }
}

nonisolated enum AgentWorkspaceAction: Sendable, Equatable {
    case decomposeIntent
    case inspectWorkspaceContext
    case selectExecutionStrategy
    case validatePatchPlan(operationCount: Int)
    case coordinateGuardedPatchExecution
    case applyPatchPlan(operationCount: Int)
    case validateReactNativeWorkspace
}
