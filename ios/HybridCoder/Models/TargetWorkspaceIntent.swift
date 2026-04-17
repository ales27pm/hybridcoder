import Foundation

nonisolated struct TargetWorkspaceIntent: Sendable {
    let summary: String
    let operations: [Operation]
    let confidence: Confidence

    nonisolated enum Confidence: String, Sendable {
        case low
        case medium
        case high
    }

    nonisolated enum Operation: Sendable {
        case addRoute(AddRouteIntent)
        case createScreen(CreateScreenIntent)
        case rename(RenameIntent)
        case split(SplitIntent)
        case repairImports(RepairImportsIntent)
        case createFile(path: String, reason: String)
        case updateFile(path: String, reason: String)
    }
}

nonisolated struct AddRouteIntent: Hashable, Sendable {
    let routePath: String
    let screenName: String
    let parentLayoutPath: String?
}

nonisolated struct CreateScreenIntent: Hashable, Sendable {
    let screenName: String
    let destinationPath: String
    let usesExpoRouter: Bool
}

nonisolated struct RenameIntent: Hashable, Sendable {
    let fromPath: String
    let toPath: String
    let updatesReferences: Bool
}

nonisolated struct SplitIntent: Hashable, Sendable {
    let sourcePath: String
    let targets: [SplitTarget]

    nonisolated struct SplitTarget: Hashable, Sendable {
        let path: String
        let symbolNames: [String]
    }
}

nonisolated struct RepairImportsIntent: Hashable, Sendable {
    let targetPaths: [String]
    let preferredExtensions: [String]
}
