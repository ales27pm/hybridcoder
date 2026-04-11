import SwiftUI

struct SettingsView: View {
    let bookmarkService: BookmarkService
    let orchestrator: AIOrchestrator
    let onOpenRepository: (Repository) -> Void
    let onCloseRepository: () -> Void
    var privacyService: PrivacyPolicyService? = nil
    var sessionManager: LanguageModelSessionManager? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                repositoriesSection
                indexSection
                runtimeMetricsSection
                if let privacyService {
                    privacySection(privacyService)
                }
                if let sessionManager {
                    sessionSection(sessionManager)
                }
                diagnosticsSection
                aboutSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.surfaceBg)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var repositoriesSection: some View {
        Section {
            if bookmarkService.repositories.isEmpty {
                Text("No repositories imported")
                    .font(.subheadline)
                    .foregroundStyle(Theme.dimText)
            } else {
                ForEach(bookmarkService.repositories) { repo in
                    Button {
                        onOpenRepository(repo)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(Theme.accent)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(repo.name)
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                                Text("\(repo.fileCount) files · Last opened \(repo.lastOpened.formatted(.relative(presentation: .named)))")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.dimText)
                            }
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Delete", role: .destructive) {
                            bookmarkService.removeRepository(repo)
                        }
                    }
                }
            }
        } header: {
            Text("Repositories")
        }
    }

    private var indexSection: some View {
        Section {
            HStack {
                Text("Indexed Files")
                    .font(.subheadline)
                Spacer()
                Text("\(orchestrator.indexStats?.indexedFiles ?? 0)")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(Theme.accent)
            }

            HStack {
                Text("Embedded Chunks")
                    .font(.subheadline)
                Spacer()
                Text("\(orchestrator.indexStats?.embeddedChunks ?? 0)")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(Theme.accent)
            }

            if let stats = orchestrator.indexStats, !stats.languageBreakdown.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Language Breakdown")
                        .font(.subheadline)

                    let sorted = stats.languageBreakdown.sorted { $0.value > $1.value }
                    ForEach(sorted, id: \.key) { language, count in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(languageColor(language))
                                .frame(width: 8, height: 8)

                            Text(language)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.8))

                            Spacer()

                            Text("\(count)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
            }

            if let stats = orchestrator.indexStats, let lastIndexed = stats.lastIndexedAt {
                HStack {
                    Text("Last Indexed")
                        .font(.subheadline)
                    Spacer()
                    Text(lastIndexed.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(Theme.dimText)
                }
            }

            Button("Close Repository") {
                onCloseRepository()
                dismiss()
            }
            .foregroundStyle(.red)
        } header: {
            Text("Index")
        }
    }

    private var runtimeMetricsSection: some View {
        let snapshot = orchestrator.agentRuntimeKPISnapshot
        let truthfulness = RuntimeTelemetryStore.loadPreviewTruthfulnessSnapshot() ?? .empty
        let exportSnapshot = RuntimeTelemetryStore.loadExportSnapshot()
        let validationReport = RuntimeTelemetryStore.loadValidationReport()
            ?? RuntimeKPIValidationService.evaluate(
                runtimeKPI: snapshot,
                previewTruthfulness: truthfulness,
                sourceTelemetryExportedAt: exportSnapshot?.exportedAt
            )
        let passingChecks = validationReport.checks.filter { $0.status == .passing }.count
        let failingChecks = validationReport.checks.filter { $0.status == .failing }.count
        let pendingChecks = validationReport.checks.filter { $0.status == .insufficientData }.count

        return Section {
            HStack {
                Text("Phase 6 Validation")
                    .font(.subheadline)
                Spacer()
                Text(formattedValidationStatus(validationReport.overallStatus))
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(validationStatusColor(validationReport.overallStatus))
            }

            HStack {
                Text("Validation Checks")
                    .font(.subheadline)
                Spacer()
                Text("\(passingChecks) pass · \(failingChecks) fail · \(pendingChecks) pending")
                    .font(.caption)
                    .foregroundStyle(Theme.dimText)
            }

            HStack {
                Text("Goal -> Plan p50")
                    .font(.subheadline)
                Spacer()
                Text(formattedMilliseconds(snapshot.goalToPlanLatencyP50Milliseconds))
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(Theme.accent)
            }

            HStack {
                Text("Scaffold First Output p50")
                    .font(.subheadline)
                Spacer()
                Text(formattedMilliseconds(snapshot.scaffoldTimeToFirstOutputP50Milliseconds))
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(Theme.accent)
            }

            HStack {
                Text("Multi-Step Completion")
                    .font(.subheadline)
                Spacer()
                Text(formattedCompletionRate(snapshot.multiStepCompletionRate))
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(Theme.accent)
            }

            HStack {
                Text("Multi-Step Samples")
                    .font(.subheadline)
                Spacer()
                Text("\(snapshot.multiStepScenarioCount)")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(Theme.accent)
            }

            HStack {
                Text("Workspace Safety Violations")
                    .font(.subheadline)
                Spacer()
                Text("\(snapshot.workspaceSafetyViolationCount)")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(snapshot.workspaceSafetyViolationCount == 0 ? Theme.accent : .orange)
            }

            HStack {
                Text("Preview Truth Checks")
                    .font(.subheadline)
                Spacer()
                Text("\(truthfulness.validationChecks)")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(Theme.accent)
            }

            HStack {
                Text("Preview False Claims")
                    .font(.subheadline)
                Spacer()
                Text("\(truthfulness.falseClaimCount)")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(truthfulness.falseClaimCount == 0 ? Theme.accent : .orange)
            }

            if let lastUpdatedAt = snapshot.lastUpdatedAt {
                HStack {
                    Text("Last Updated")
                        .font(.subheadline)
                    Spacer()
                    Text(lastUpdatedAt.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(Theme.dimText)
                }
            }

            if let lastTruthfulnessCheck = truthfulness.lastCheckedAt {
                HStack {
                    Text("Last Truthfulness Check")
                        .font(.subheadline)
                    Spacer()
                    Text(lastTruthfulnessCheck.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(Theme.dimText)
                }
            }

            if let exportSnapshot {
                HStack {
                    Text("Telemetry Export")
                        .font(.subheadline)
                    Spacer()
                    Text(exportSnapshot.exportedAt.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(Theme.dimText)
                }
            }

            HStack {
                Text("Validation Report")
                    .font(.subheadline)
                Spacer()
                Text(validationReport.generatedAt.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(Theme.dimText)
            }
        } header: {
            Text("Runtime KPIs")
        } footer: {
            Text("Persisted local runtime instrumentation for Phase 6. Telemetry snapshots and KPI validation reports are exported in Application Support after runtime and preview audits.")
        }
    }

    private func languageColor(_ language: String) -> Color {
        switch language.lowercased() {
        case "javascript": return .yellow
        case "typescript": return .blue
        case "swift": return .orange
        case "python": return .cyan
        case "json": return .orange.opacity(0.7)
        case "css": return .purple
        case "html": return .red.opacity(0.7)
        case "markdown": return .gray
        default: return Theme.accent
        }
    }

    private func formattedMilliseconds(_ value: Int?) -> String {
        guard let value else { return "No sample" }
        return "\(value) ms"
    }

    private func formattedCompletionRate(_ value: Double?) -> String {
        guard let value else { return "No sample" }
        let percent = Int((value * 100).rounded())
        return "\(percent)%"
    }

    private func formattedValidationStatus(_ status: RuntimeKPIValidationOverallStatus) -> String {
        switch status {
        case .passing:
            return "PASS"
        case .failing:
            return "FAIL"
        case .incomplete:
            return "INCOMPLETE"
        }
    }

    private func validationStatusColor(_ status: RuntimeKPIValidationOverallStatus) -> Color {
        switch status {
        case .passing:
            return Theme.accent
        case .failing:
            return .orange
        case .incomplete:
            return Theme.dimText
        }
    }

    private func privacySection(_ service: PrivacyPolicyService) -> some View {
        Section {
            Toggle("Local-Only Processing", isOn: Binding(
                get: { service.localOnlyProcessing },
                set: { service.localOnlyProcessing = $0 }
            ))
            .font(.subheadline)
            .tint(Theme.accent)

            Toggle("Allow Private Cloud Compute", isOn: Binding(
                get: { service.allowPrivateCloudCompute },
                set: { service.allowPrivateCloudCompute = $0 }
            ))
            .font(.subheadline)
            .tint(Theme.accent)
            .disabled(service.localOnlyProcessing)

            HStack {
                Text("Data Retention")
                    .font(.subheadline)
                Spacer()
                Text("\(service.dataRetentionDays) days")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(Theme.accent)
            }

            HStack {
                Text("Privacy Mode")
                    .font(.subheadline)
                Spacer()
                Text(service.privacyBadge)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.accent.opacity(0.15), in: .capsule)
            }

            Button("Reset to Defaults") {
                service.resetToDefaults()
            }
            .font(.subheadline)
            .foregroundStyle(.orange)
        } header: {
            Text("Privacy")
        } footer: {
            Text(service.privacySummary)
        }
    }

    private func sessionSection(_ manager: LanguageModelSessionManager) -> some View {
        Section {
            HStack {
                Text("Active Sessions")
                    .font(.subheadline)
                Spacer()
                Text("\(manager.activeSessions.values.filter(\.isActive).count)")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(Theme.accent)
            }

            HStack {
                Text("Token Budget")
                    .font(.subheadline)
                Spacer()
                Text("~\(manager.totalEstimatedTokens)")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(Theme.accent)
            }

            Button("Evict Idle Sessions") {
                manager.evictIdleSessions()
            }
            .font(.subheadline)
            .foregroundStyle(Theme.accent)
        } header: {
            Text("Session Management")
        } footer: {
            Text(manager.sessionSummary)
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                    .font(.subheadline)
                Spacer()
                Text("2.0.0")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(Theme.dimText)
            }

            HStack {
                Text("Architecture")
                    .font(.subheadline)
                Spacer()
                Text("Foundation Models + CoreML")
                    .font(.caption)
                    .foregroundStyle(Theme.dimText)
            }

            HStack {
                Text("Runtime")
                    .font(.subheadline)
                Spacer()
                Text("Local-First Offline")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
            }
        } header: {
            Text("About")
        }
    }

    private var diagnosticsSection: some View {
        Section {
            if orchestrator.discoveryDiagnostics.isEmpty {
                Text("No diagnostics")
                    .font(.subheadline)
                    .foregroundStyle(Theme.dimText)
            } else {
                if !orchestrator.templateDiagnostics.isEmpty {
                    diagnosticsGroup(title: "Prompt Templates", diagnostics: orchestrator.templateDiagnostics)
                }

                if !orchestrator.contextPolicyDiagnostics.isEmpty {
                    diagnosticsGroup(title: "Context Policies", diagnostics: orchestrator.contextPolicyDiagnostics)
                }
            }
        } header: {
            Text("Diagnostics")
        }
    }

    @ViewBuilder
    private func diagnosticsGroup(title: String, diagnostics: [DiscoveryDiagnostic]) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.dimText)
            .textCase(nil)

        ForEach(diagnostics) { diagnostic in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(diagnostic.severity.rawValue.capitalized)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(severityColor(diagnostic.severity))
                    Spacer()
                    Text(diagnostic.sourcePath)
                        .font(.caption2)
                        .foregroundStyle(Theme.dimText)
                        .lineLimit(1)
                }

                Text(diagnostic.actionableMessage)
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }
            .padding(.vertical, 4)
        }
    }

    private func severityColor(_ severity: DiscoveryDiagnosticSeverity) -> Color {
        switch severity {
        case .warning:
            return .yellow
        case .error:
            return .red
        case .collision:
            return .orange
        }
    }
}
