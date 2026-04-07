import Foundation
import OSLog

actor PrototypeStateMemory {
    nonisolated struct ProjectState: Codable, Sendable {
        var projectID: UUID
        var activeFileID: UUID?
        var editorCursorPosition: Int?
        var lastOpenedTab: String?
        var conversationSnippets: [ConversationSnippet]
        var workspaceNotes: String?
        var lastSavedAt: Date

        nonisolated struct ConversationSnippet: Codable, Sendable {
            let role: String
            let content: String
            let timestamp: Date
        }
    }

    private let fileSystem: FileSystemService
    private let logger = Logger(subsystem: "com.hybridcoder.app", category: "PrototypeStateMemory")
    private let stateDirectoryName = "prototype_state"

    init(fileSystem: FileSystemService? = nil) {
        self.fileSystem = fileSystem ?? FileSystemService(subdirectory: "HybridCoder")
    }

    func saveState(_ state: ProjectState) async {
        let relativePath = "\(stateDirectoryName)/\(state.projectID.uuidString).json"
        do {
            let data = try JSONEncoder().encode(state)
            guard let json = String(data: data, encoding: .utf8) else { return }
            try await fileSystem.createDirectory(stateDirectoryName)
            try await fileSystem.writeString(json, to: relativePath)
        } catch {
            logger.error("Failed to save prototype state for \(state.projectID): \(error.localizedDescription)")
        }
    }

    func loadState(for projectID: UUID) async -> ProjectState? {
        let relativePath = "\(stateDirectoryName)/\(projectID.uuidString).json"
        do {
            let json = try await fileSystem.readString(from: relativePath)
            guard let data = json.data(using: .utf8) else { return nil }
            return try JSONDecoder().decode(ProjectState.self, from: data)
        } catch {
            return nil
        }
    }

    func deleteState(for projectID: UUID) async {
        let relativePath = "\(stateDirectoryName)/\(projectID.uuidString).json"
        do {
            try await fileSystem.delete(relativePath)
        } catch {
            logger.error("Failed to delete state for \(projectID): \(error.localizedDescription)")
        }
    }

    func importStateToProjectFolder(projectID: UUID, destinationRoot: URL) async -> Bool {
        guard let state = await loadState(for: projectID) else { return false }

        let fm = FileManager.default
        let stateDir = destinationRoot.appendingPathComponent(".hybridcoder", isDirectory: true)

        do {
            try fm.createDirectory(at: stateDir, withIntermediateDirectories: true)

            let data = try JSONEncoder().encode(state)
            let statePath = stateDir.appendingPathComponent("state.json")
            try data.write(to: statePath, options: .atomic)

            if !state.conversationSnippets.isEmpty {
                let memoryPath = stateDir.appendingPathComponent("conversation_memory.json")
                let memoryData = try JSONEncoder().encode(state.conversationSnippets)
                try memoryData.write(to: memoryPath, options: .atomic)
            }

            if let notes = state.workspaceNotes, !notes.isEmpty {
                let notesPath = stateDir.appendingPathComponent("workspace_notes.md")
                try notes.write(to: notesPath, atomically: true, encoding: .utf8)
            }

            logger.info("Imported state memory to \(stateDir.path)")
            return true
        } catch {
            logger.error("Failed to import state to project folder: \(error.localizedDescription)")
            return false
        }
    }

    func exportStateFromProjectFolder(projectID: UUID, sourceRoot: URL) async -> ProjectState? {
        let stateFile = sourceRoot
            .appendingPathComponent(".hybridcoder", isDirectory: true)
            .appendingPathComponent("state.json")

        guard FileManager.default.fileExists(atPath: stateFile.path) else { return nil }

        do {
            let data = try Data(contentsOf: stateFile)
            var state = try JSONDecoder().decode(ProjectState.self, from: data)
            state.projectID = projectID

            let memoryFile = sourceRoot
                .appendingPathComponent(".hybridcoder", isDirectory: true)
                .appendingPathComponent("conversation_memory.json")
            if let memoryData = try? Data(contentsOf: memoryFile) {
                state.conversationSnippets = (try? JSONDecoder().decode(
                    [ProjectState.ConversationSnippet].self, from: memoryData
                )) ?? state.conversationSnippets
            }

            let notesFile = sourceRoot
                .appendingPathComponent(".hybridcoder", isDirectory: true)
                .appendingPathComponent("workspace_notes.md")
            if let notesContent = try? String(contentsOf: notesFile, encoding: .utf8) {
                state.workspaceNotes = notesContent
            }

            await saveState(state)
            return state
        } catch {
            logger.error("Failed to export state from project folder: \(error.localizedDescription)")
            return nil
        }
    }

    func listSavedStates() async -> [UUID] {
        do {
            let files = try await fileSystem.listContents(of: stateDirectoryName)
            return files.compactMap { file in
                guard file.name.hasSuffix(".json") else { return nil }
                let uuidString = String(file.name.dropLast(5))
                return UUID(uuidString: uuidString)
            }
        } catch {
            return []
        }
    }
}
