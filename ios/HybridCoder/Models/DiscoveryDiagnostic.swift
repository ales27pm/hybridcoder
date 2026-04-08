import Foundation

nonisolated enum DiscoveryDiagnosticSeverity: String, Sendable {
    case warning
    case error
    case collision
}

nonisolated struct WarningDiagnostic: Sendable, Equatable {
    let sourcePath: String
    let message: String
    let contextID: String?

    init(sourcePath: String, message: String, contextID: String? = nil) {
        self.sourcePath = sourcePath
        self.message = message
        self.contextID = contextID
    }
}

nonisolated struct ErrorDiagnostic: Sendable, Equatable {
    let sourcePath: String
    let message: String
    let contextID: String?

    init(sourcePath: String, message: String, contextID: String? = nil) {
        self.sourcePath = sourcePath
        self.message = message
        self.contextID = contextID
    }
}

nonisolated struct CollisionDiagnostic: Sendable, Equatable {
    let sourcePath: String
    let conflictingPath: String
    let message: String
}

nonisolated enum DiscoveryDiagnostic: Sendable, Equatable, Identifiable {
    case warning(WarningDiagnostic)
    case error(ErrorDiagnostic)
    case collision(CollisionDiagnostic)

    var id: String {
        switch self {
        case .warning(let diagnostic):
            return "\(severity.rawValue):\(diagnostic.sourcePath):\(diagnostic.message):\(diagnostic.contextID ?? "-")"
        case .error(let diagnostic):
            return "\(severity.rawValue):\(diagnostic.sourcePath):\(diagnostic.message):\(diagnostic.contextID ?? "-")"
        case .collision(let diagnostic):
            return "\(severity.rawValue):\(diagnostic.sourcePath):\(diagnostic.conflictingPath):\(diagnostic.message)"
        }
    }

    var severity: DiscoveryDiagnosticSeverity {
        switch self {
        case .warning:
            return .warning
        case .error:
            return .error
        case .collision:
            return .collision
        }
    }

    var sourcePath: String {
        switch self {
        case .warning(let diagnostic):
            return diagnostic.sourcePath
        case .error(let diagnostic):
            return diagnostic.sourcePath
        case .collision(let diagnostic):
            return diagnostic.sourcePath
        }
    }

    var actionableMessage: String {
        switch self {
        case .warning(let diagnostic):
            return diagnostic.message
        case .error(let diagnostic):
            return diagnostic.message
        case .collision(let diagnostic):
            return "\(diagnostic.message) Conflicts with \(diagnostic.conflictingPath)."
        }
    }
}
