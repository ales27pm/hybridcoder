import Foundation

@Observable
@MainActor
final class CodeIndexService {
    var indexedFiles: [IndexedFile] = []
    var isIndexing: Bool = false
    var indexProgress: Double = 0

    private let fileSystemService = FileSystemService()

    func indexRepository(at url: URL) async {
        isIndexing = true
        indexProgress = 0
        indexedFiles = []

        let sourceURLs = fileSystemService.collectSourceFiles(at: url)
        let total = sourceURLs.count

        for (i, fileURL) in sourceURLs.enumerated() {
            guard let content = fileSystemService.readFileContent(at: fileURL) else { continue }
            let relativePath = fileURL.path.replacingOccurrences(of: url.path, with: "")
            let language = fileSystemService.languageForFile(fileURL)
            let lines = content.components(separatedBy: .newlines).count

            let indexed = IndexedFile(
                relativePath: relativePath,
                absoluteURL: fileURL,
                content: content,
                language: language,
                lastModified: (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date(),
                lineCount: lines
            )
            indexedFiles.append(indexed)
            indexProgress = Double(i + 1) / Double(total)
        }

        isIndexing = false
    }

    func searchFiles(query: String) -> [IndexedFile] {
        guard !query.isEmpty else { return indexedFiles }
        let lowered = query.lowercased()
        return indexedFiles.filter { file in
            file.relativePath.lowercased().contains(lowered) ||
            file.content.lowercased().contains(lowered)
        }
    }

    func findRelevantContext(for query: String, maxFiles: Int = 5, maxCharsPerFile: Int = 2000) -> String {
        let relevant = searchFiles(query: query).prefix(maxFiles)
        var context = ""
        for file in relevant {
            let truncated = String(file.content.prefix(maxCharsPerFile))
            context += "--- \(file.relativePath) ---\n\(truncated)\n\n"
        }
        return context
    }

    func indexedFilePaths() -> [String] {
        indexedFiles.map { $0.relativePath }
    }

    func clearIndex() {
        indexedFiles = []
        indexProgress = 0
    }
}
