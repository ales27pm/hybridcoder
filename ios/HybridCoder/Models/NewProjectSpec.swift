import Foundation

nonisolated struct NewProjectSpec: Codable, Sendable, Hashable {
    var name: String = ""
    var templateID: String = "blank_expo_ts"
    var kind: ProjectKind = .expoTS
    var navigationPreset: NavigationPreset = .none
    var source: ProjectSource = .scaffold
    var preferredEntryFile: String?
    var workspaceNotes: [String] = []

    var effectiveName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }
}
