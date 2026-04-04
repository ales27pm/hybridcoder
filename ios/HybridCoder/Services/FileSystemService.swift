import Foundation
import OSLog

actor FileSystemService {
    nonisolated enum FSError: Error, LocalizedError, Sendable {
        case fileNotFound(String)
        case directoryCreationFailed(String)
        case writeFailed(String)
        case readFailed(String)
        case deleteFailed(String)
        case moveFailed(String)
        case copyFailed(String)

        nonisolated var errorDescription: String? {
            switch self {
            case .fileNotFound(let p): return "File not found: \(p)"
            case .directoryCreationFailed(let p): return "Could not create directory: \(p)"
            case .writeFailed(let msg): return "Write failed: \(msg)"
            case .readFailed(let msg): return "Read failed: \(msg)"
            case .deleteFailed(let msg): return "Delete failed: \(msg)"
            case .moveFailed(let msg): return "Move failed: \(msg)"
            case .copyFailed(let msg): return "Copy failed: \(msg)"
            }
        }
    }

    nonisolated struct FileInfo: Sendable {
        let name: String
        let path: String
        let size: Int
        let isDirectory: Bool
        let modificationDate: Date?
        let creationDate: Date?
    }

    private let fm = FileManager.default
    private let logger = Logger(subsystem: "com.hybridcoder.app", category: "FileSystemService")

    private let baseDirectory: URL

    init(subdirectory: String = "HybridCoder") {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.baseDirectory = appSupport.appendingPathComponent(subdirectory, isDirectory: true)
        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }

    var basePath: String { baseDirectory.path }

    func writeString(_ content: String, to relativePath: String) throws {
        let url = resolvedURL(relativePath)
        try ensureParentDirectory(for: url)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw FSError.writeFailed(error.localizedDescription)
        }
    }

    func writeData(_ data: Data, to relativePath: String) throws {
        let url = resolvedURL(relativePath)
        try ensureParentDirectory(for: url)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw FSError.writeFailed(error.localizedDescription)
        }
    }

    func readString(from relativePath: String) throws -> String {
        let url = resolvedURL(relativePath)
        guard fm.fileExists(atPath: url.path) else {
            throw FSError.fileNotFound(relativePath)
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw FSError.readFailed(error.localizedDescription)
        }
    }

    func readData(from relativePath: String) throws -> Data {
        let url = resolvedURL(relativePath)
        guard fm.fileExists(atPath: url.path) else {
            throw FSError.fileNotFound(relativePath)
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw FSError.readFailed(error.localizedDescription)
        }
    }

    func exists(_ relativePath: String) -> Bool {
        fm.fileExists(atPath: resolvedURL(relativePath).path)
    }

    func delete(_ relativePath: String) throws {
        let url = resolvedURL(relativePath)
        guard fm.fileExists(atPath: url.path) else { return }
        do {
            try fm.removeItem(at: url)
        } catch {
            throw FSError.deleteFailed(error.localizedDescription)
        }
    }

    func move(from source: String, to destination: String) throws {
        let srcURL = resolvedURL(source)
        let dstURL = resolvedURL(destination)
        guard fm.fileExists(atPath: srcURL.path) else {
            throw FSError.fileNotFound(source)
        }
        try ensureParentDirectory(for: dstURL)
        do {
            if fm.fileExists(atPath: dstURL.path) {
                try fm.removeItem(at: dstURL)
            }
            try fm.moveItem(at: srcURL, to: dstURL)
        } catch {
            throw FSError.moveFailed(error.localizedDescription)
        }
    }

    func copy(from source: String, to destination: String) throws {
        let srcURL = resolvedURL(source)
        let dstURL = resolvedURL(destination)
        guard fm.fileExists(atPath: srcURL.path) else {
            throw FSError.fileNotFound(source)
        }
        try ensureParentDirectory(for: dstURL)
        do {
            if fm.fileExists(atPath: dstURL.path) {
                try fm.removeItem(at: dstURL)
            }
            try fm.copyItem(at: srcURL, to: dstURL)
        } catch {
            throw FSError.copyFailed(error.localizedDescription)
        }
    }

    func createDirectory(_ relativePath: String) throws {
        let url = resolvedURL(relativePath)
        do {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw FSError.directoryCreationFailed(error.localizedDescription)
        }
    }

    func listContents(of relativePath: String = "") throws -> [FileInfo] {
        let url = relativePath.isEmpty ? baseDirectory : resolvedURL(relativePath)
        guard fm.fileExists(atPath: url.path) else {
            throw FSError.fileNotFound(relativePath)
        }
        let contents = try fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        )

        return contents.compactMap { itemURL in
            let values = try? itemURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey, .contentModificationDateKey, .creationDateKey])
            return FileInfo(
                name: itemURL.lastPathComponent,
                path: itemURL.path,
                size: values?.fileSize ?? 0,
                isDirectory: values?.isDirectory ?? false,
                modificationDate: values?.contentModificationDate,
                creationDate: values?.creationDate
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func fileInfo(_ relativePath: String) throws -> FileInfo {
        let url = resolvedURL(relativePath)
        guard fm.fileExists(atPath: url.path) else {
            throw FSError.fileNotFound(relativePath)
        }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey, .contentModificationDateKey, .creationDateKey])
        return FileInfo(
            name: url.lastPathComponent,
            path: url.path,
            size: values.fileSize ?? 0,
            isDirectory: values.isDirectory ?? false,
            modificationDate: values.contentModificationDate,
            creationDate: values.creationDate
        )
    }

    func appendString(_ content: String, to relativePath: String) throws {
        let url = resolvedURL(relativePath)
        try ensureParentDirectory(for: url)

        if fm.fileExists(atPath: url.path) {
            guard let fileHandle = try? FileHandle(forWritingTo: url) else {
                throw FSError.writeFailed("Cannot open file handle for \(relativePath)")
            }
            defer { try? fileHandle.close() }
            fileHandle.seekToEndOfFile()
            guard let data = content.data(using: .utf8) else {
                throw FSError.writeFailed("Cannot encode string to UTF-8")
            }
            fileHandle.write(data)
        } else {
            try writeString(content, to: relativePath)
        }
    }

    func totalSize(of relativePath: String = "") throws -> Int64 {
        let url = relativePath.isEmpty ? baseDirectory : resolvedURL(relativePath)
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }

    private func resolvedURL(_ relativePath: String) -> URL {
        baseDirectory.appendingPathComponent(relativePath)
    }

    private func ensureParentDirectory(for url: URL) throws {
        let parent = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: parent.path) {
            do {
                try fm.createDirectory(at: parent, withIntermediateDirectories: true)
            } catch {
                throw FSError.directoryCreationFailed(error.localizedDescription)
            }
        }
    }
}
