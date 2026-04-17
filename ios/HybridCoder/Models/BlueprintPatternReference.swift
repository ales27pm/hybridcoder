import Foundation

nonisolated struct BlueprintPatternReference: Hashable, Sendable {
    let id: String
    let name: String
    let category: Category
    let source: Source
    let applicablePaths: [String]

    nonisolated enum Category: String, Sendable {
        case routing
        case screenComposition
        case stateManagement
        case imports
        case fileStructure
        case testing
        case unknown
    }

    nonisolated enum Source: Hashable, Sendable {
        case builtIn
        case workspace(path: String)
        case documentation(url: URL)
    }
}
