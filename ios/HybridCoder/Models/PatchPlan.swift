import Foundation

nonisolated struct PatchPlan: Identifiable, Sendable {
    let id: UUID
    let summary: String
    let operations: [PatchOperation]
    let createdAt: Date

    var pendingCount: Int { operations.filter { $0.status == .pending }.count }
    var appliedCount: Int { operations.filter { $0.status == .applied }.count }
    var totalCount: Int { operations.count }

    init(
        id: UUID = UUID(),
        summary: String,
        operations: [PatchOperation],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.summary = summary
        self.operations = operations
        self.createdAt = createdAt
    }

    func withUpdatedOperation(_ operationID: UUID, status: PatchOperation.Status) -> PatchPlan {
        let updated = operations.map { op in
            guard op.id == operationID else { return op }
            return PatchOperation(
                id: op.id,
                filePath: op.filePath,
                searchText: op.searchText,
                replaceText: op.replaceText,
                description: op.description,
                status: status
            )
        }
        return PatchPlan(id: id, summary: summary, operations: updated, createdAt: createdAt)
    }
}

nonisolated struct PatchOperation: Identifiable, Sendable {
    let id: UUID
    let filePath: String
    let searchText: String
    let replaceText: String
    let description: String
    var status: Status

    nonisolated enum Status: String, Sendable {
        case pending
        case applied
        case rejected
        case failed
    }

    init(
        id: UUID = UUID(),
        filePath: String,
        searchText: String,
        replaceText: String,
        description: String = "",
        status: Status = .pending
    ) {
        self.id = id
        self.filePath = filePath
        self.searchText = searchText
        self.replaceText = replaceText
        self.description = description
        self.status = status
    }
}
