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

            Button("Close Repository") {
                onCloseRepository()
                dismiss()
            }
            .foregroundStyle(.red)
        } header: {
            Text("Index")
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
