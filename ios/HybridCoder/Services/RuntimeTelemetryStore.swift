import Foundation
import OSLog

nonisolated struct RuntimeTelemetryExportSnapshot: Sendable, Codable {
    let exportedAt: Date
    let runtimeKPI: AgentRuntimeKPISnapshot
    let previewTruthfulness: PreviewTruthfulnessSnapshot
}

nonisolated enum RuntimeTelemetryStore {
    private static let logger = Logger(subsystem: "com.hybridcoder.app", category: "RuntimeTelemetryStore")
    private static let runtimeKPIFileName = "agent-runtime-kpi-store.json"
    private static let previewTruthfulnessFileName = "preview-truthfulness-snapshot.json"
    private static let exportFileName = "runtime-telemetry-export.json"
    private static let validationReportFileName = "runtime-kpi-validation-report.json"

    static func runtimeKPIStoreURL(fileManager: FileManager = .default) -> URL? {
        HybridCoderResourceLocator.appSupportRoot(fileManager: fileManager)?
            .appendingPathComponent(runtimeKPIFileName, isDirectory: false)
    }

    static func previewTruthfulnessStoreURL(fileManager: FileManager = .default) -> URL? {
        HybridCoderResourceLocator.appSupportRoot(fileManager: fileManager)?
            .appendingPathComponent(previewTruthfulnessFileName, isDirectory: false)
    }

    static func exportSnapshotURL(fileManager: FileManager = .default) -> URL? {
        HybridCoderResourceLocator.appSupportRoot(fileManager: fileManager)?
            .appendingPathComponent(exportFileName, isDirectory: false)
    }

    static func validationReportURL(fileManager: FileManager = .default) -> URL? {
        HybridCoderResourceLocator.appSupportRoot(fileManager: fileManager)?
            .appendingPathComponent(validationReportFileName, isDirectory: false)
    }

    static func loadRuntimeKPIStore(fileManager: FileManager = .default) -> AgentRuntimeKPIStore? {
        guard let url = runtimeKPIStoreURL(fileManager: fileManager) else {
            return nil
        }
        return loadRuntimeKPIStore(from: url, fileManager: fileManager)
    }

    static func loadRuntimeKPIStore(
        from fileURL: URL,
        fileManager: FileManager = .default
    ) -> AgentRuntimeKPIStore? {
        loadCodable(AgentRuntimeKPIStore.self, from: fileURL, fileManager: fileManager)
    }

    static func saveRuntimeKPIStore(
        _ store: AgentRuntimeKPIStore,
        fileManager: FileManager = .default
    ) {
        guard let url = runtimeKPIStoreURL(fileManager: fileManager) else {
            return
        }
        _ = saveRuntimeKPIStore(store, to: url, fileManager: fileManager)
    }

    @discardableResult
    static func saveRuntimeKPIStore(
        _ store: AgentRuntimeKPIStore,
        to fileURL: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        saveCodable(store, to: fileURL, fileManager: fileManager)
    }

    static func loadPreviewTruthfulnessSnapshot(fileManager: FileManager = .default) -> PreviewTruthfulnessSnapshot? {
        guard let url = previewTruthfulnessStoreURL(fileManager: fileManager) else {
            return nil
        }
        return loadPreviewTruthfulnessSnapshot(from: url, fileManager: fileManager)
    }

    static func loadPreviewTruthfulnessSnapshot(
        from fileURL: URL,
        fileManager: FileManager = .default
    ) -> PreviewTruthfulnessSnapshot? {
        loadCodable(PreviewTruthfulnessSnapshot.self, from: fileURL, fileManager: fileManager)
    }

    static func savePreviewTruthfulnessSnapshot(
        _ snapshot: PreviewTruthfulnessSnapshot,
        fileManager: FileManager = .default
    ) {
        guard let url = previewTruthfulnessStoreURL(fileManager: fileManager) else {
            return
        }
        _ = savePreviewTruthfulnessSnapshot(snapshot, to: url, fileManager: fileManager)
    }

    @discardableResult
    static func savePreviewTruthfulnessSnapshot(
        _ snapshot: PreviewTruthfulnessSnapshot,
        to fileURL: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        saveCodable(snapshot, to: fileURL, fileManager: fileManager)
    }

    static func loadExportSnapshot(fileManager: FileManager = .default) -> RuntimeTelemetryExportSnapshot? {
        guard let url = exportSnapshotURL(fileManager: fileManager) else {
            return nil
        }
        return loadExportSnapshot(from: url, fileManager: fileManager)
    }

    static func loadExportSnapshot(
        from fileURL: URL,
        fileManager: FileManager = .default
    ) -> RuntimeTelemetryExportSnapshot? {
        loadCodable(RuntimeTelemetryExportSnapshot.self, from: fileURL, fileManager: fileManager)
    }

    static func loadValidationReport(fileManager: FileManager = .default) -> RuntimeKPIValidationReport? {
        guard let url = validationReportURL(fileManager: fileManager) else {
            return nil
        }
        return loadValidationReport(from: url, fileManager: fileManager)
    }

    static func loadValidationReport(
        from fileURL: URL,
        fileManager: FileManager = .default
    ) -> RuntimeKPIValidationReport? {
        loadCodable(RuntimeKPIValidationReport.self, from: fileURL, fileManager: fileManager)
    }

    @discardableResult
    static func exportSnapshot(
        runtimeKPI: AgentRuntimeKPISnapshot,
        previewTruthfulness: PreviewTruthfulnessSnapshot,
        fileManager: FileManager = .default
    ) -> URL? {
        guard let url = exportSnapshotURL(fileManager: fileManager) else {
            return nil
        }
        let now = Date()
        let export = RuntimeTelemetryExportSnapshot(
            exportedAt: now,
            runtimeKPI: runtimeKPI,
            previewTruthfulness: previewTruthfulness
        )
        let didSave = saveCodable(export, to: url, fileManager: fileManager)
        if didSave {
            let report = RuntimeKPIValidationService.evaluate(
                runtimeKPI: runtimeKPI,
                previewTruthfulness: previewTruthfulness,
                sourceTelemetryExportedAt: now,
                now: now
            )
            saveValidationReport(report, fileManager: fileManager)
        }
        return didSave ? url : nil
    }

    @discardableResult
    static func exportSnapshot(
        runtimeKPI: AgentRuntimeKPISnapshot,
        previewTruthfulness: PreviewTruthfulnessSnapshot,
        to fileURL: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        let now = Date()
        let export = RuntimeTelemetryExportSnapshot(
            exportedAt: now,
            runtimeKPI: runtimeKPI,
            previewTruthfulness: previewTruthfulness
        )
        return saveCodable(export, to: fileURL, fileManager: fileManager)
    }

    static func saveValidationReport(
        _ report: RuntimeKPIValidationReport,
        fileManager: FileManager = .default
    ) {
        guard let url = validationReportURL(fileManager: fileManager) else {
            return
        }
        _ = saveValidationReport(report, to: url, fileManager: fileManager)
    }

    @discardableResult
    static func saveValidationReport(
        _ report: RuntimeKPIValidationReport,
        to fileURL: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        saveCodable(report, to: fileURL, fileManager: fileManager)
    }

    @discardableResult
    private static func saveCodable<T: Encodable>(
        _ payload: T,
        to fileURL: URL,
        fileManager: FileManager
    ) -> Bool {
        do {
            try ensureParentDirectory(for: fileURL, fileManager: fileManager)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            try data.write(to: fileURL, options: [.atomic])
            return true
        } catch {
            logger.error("telemetry.save_failed file=\(fileURL.path(percentEncoded: false), privacy: .public) reason=\(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private static func loadCodable<T: Decodable>(
        _ type: T.Type,
        from fileURL: URL,
        fileManager: FileManager
    ) -> T? {
        guard fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            return try decoder.decode(type, from: data)
        } catch {
            logger.error("telemetry.load_failed file=\(fileURL.path(percentEncoded: false), privacy: .public) reason=\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func ensureParentDirectory(
        for fileURL: URL,
        fileManager: FileManager
    ) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }
}
