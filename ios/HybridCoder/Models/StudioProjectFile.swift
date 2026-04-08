import Foundation

nonisolated struct StudioProjectFile: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var path: String
    var content: String
    var language: String

    init(id: UUID = UUID(), path: String, content: String, language: String? = nil) {
        self.id = id
        self.path = path
        self.content = content
        self.language = language ?? RepoFile.detectLanguage(for: path)
    }

    var name: String { path }
    var fileName: String { URL(fileURLWithPath: path).lastPathComponent }

    var isEntryCandidate: Bool {
        Self.entryCandidates.contains(path)
    }

    private static let entryCandidates: Set<String> = [
        "App.tsx",
        "App.ts",
        "App.js",
        "index.tsx",
        "index.ts",
        "index.js",
        "app/_layout.tsx",
        "app/_layout.js",
    ]
}
