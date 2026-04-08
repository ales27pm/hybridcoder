import Foundation

func makeTempRepoRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@MainActor
func drainAsyncState() async {
    for _ in 0..<4 {
        await Task.yield()
    }
}
