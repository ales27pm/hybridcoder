import Foundation
import OSLog

@Observable
@MainActor
final class PrivacyPolicyService {
    private let defaults = UserDefaults.standard
    private let logger = Logger(subsystem: "com.hybridcoder.app", category: "PrivacyPolicy")

    private let localOnlyKey = "privacy.localOnlyProcessing"
    private let telemetryKey = "privacy.allowTelemetry"
    private let pccKey = "privacy.allowPCC"
    private let dataRetentionKey = "privacy.dataRetentionDays"

    var localOnlyProcessing: Bool {
        didSet { defaults.set(localOnlyProcessing, forKey: localOnlyKey) }
    }

    var allowTelemetry: Bool {
        didSet { defaults.set(allowTelemetry, forKey: telemetryKey) }
    }

    var allowPrivateCloudCompute: Bool {
        didSet { defaults.set(allowPrivateCloudCompute, forKey: pccKey) }
    }

    var dataRetentionDays: Int {
        didSet { defaults.set(dataRetentionDays, forKey: dataRetentionKey) }
    }

    var privacySummary: String {
        if localOnlyProcessing {
            return "All data processed locally. Nothing leaves device."
        }
        if allowPrivateCloudCompute {
            return "Local-first with PCC fallback for complex reasoning."
        }
        return "Local processing with optional cloud bridging."
    }

    var privacyBadge: String {
        localOnlyProcessing ? "Local Only" : (allowPrivateCloudCompute ? "Local + PCC" : "Local")
    }

    init() {
        self.localOnlyProcessing = defaults.object(forKey: localOnlyKey) as? Bool ?? true
        self.allowTelemetry = defaults.object(forKey: telemetryKey) as? Bool ?? false
        self.allowPrivateCloudCompute = defaults.object(forKey: pccKey) as? Bool ?? false
        self.dataRetentionDays = defaults.object(forKey: dataRetentionKey) as? Int ?? 30
    }

    func purgeExpiredData() async {
        let cutoff = Calendar.current.date(byAdding: .day, value: -dataRetentionDays, to: Date()) ?? Date()
        logger.info("Purging data older than \(cutoff.formatted(), privacy: .public)")
    }

    func resetToDefaults() {
        localOnlyProcessing = true
        allowTelemetry = false
        allowPrivateCloudCompute = false
        dataRetentionDays = 30
    }
}
