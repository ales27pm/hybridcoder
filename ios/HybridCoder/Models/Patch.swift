import Foundation

struct Patch: Identifiable {
    let id: UUID
    let filePath: String
    let oldText: String
    let newText: String
    var status: Status
    let description: String

    enum Status: String {
        case pending
        case applied
        case rejected
        case failed
    }

    init(
        id: UUID = UUID(),
        filePath: String,
        oldText: String,
        newText: String,
        status: Status = .pending,
        description: String = ""
    ) {
        self.id = id
        self.filePath = filePath
        self.oldText = oldText
        self.newText = newText
        self.status = status
        self.description = description
    }
}
