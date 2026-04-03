import Foundation

nonisolated struct CodeBlock: Identifiable, Sendable {
    let id: UUID
    let language: String
    let code: String
    let filePath: String?

    init(
        id: UUID = UUID(),
        language: String = "",
        code: String,
        filePath: String? = nil
    ) {
        self.id = id
        self.language = language
        self.code = code
        self.filePath = filePath
    }
}
