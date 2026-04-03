import Foundation

struct Repository: Identifiable, Codable {
    let id: UUID
    let name: String
    let bookmarkData: Data
    var lastOpened: Date
    var fileCount: Int
    var indexedCount: Int

    init(
        id: UUID = UUID(),
        name: String,
        bookmarkData: Data,
        lastOpened: Date = Date(),
        fileCount: Int = 0,
        indexedCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.bookmarkData = bookmarkData
        self.lastOpened = lastOpened
        self.fileCount = fileCount
        self.indexedCount = indexedCount
    }
}
