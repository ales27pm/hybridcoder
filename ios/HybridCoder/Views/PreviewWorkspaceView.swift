import SwiftUI

struct PreviewWorkspaceView: View {
    let coordinator: PreviewCoordinator
    let workspaceName: String
    let onRefresh: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                statusHeader

                if let snapshot = coordinator.structuralSnapshot {
                    structuralPreview(snapshot)
                } else if case .diagnosticFallback(let diagnostics) = coordinator.state {
                    diagnosticFallbackView(diagnostics)
                } else if case .failed(let diagnostics) = coordinator.state {
                    failedPreview(diagnostics)
                } else if case .validating = coordinator.state {
                    validatingView
                } else {
                    emptyPreview
                }
            }
            .padding(16)
        }
        .background(Theme.surfaceBg)
    }

    private var statusHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: statusIcon)
                .font(.title3)
                .foregroundStyle(statusColor)
                .frame(width: 36, height: 36)
                .background(statusColor.opacity(0.12), in: .rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(coordinator.statusText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Text(coordinator.readiness.detail)
                    .font(.caption2)
                    .foregroundStyle(Theme.dimText)
            }

            Spacer()

            Button(action: onRefresh) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(14)
        .background(Theme.cardBg, in: .rect(cornerRadius: 14))
    }

    private func structuralPreview(_ snapshot: StructuralSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("WORKSPACE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.dimText)

                Text(workspaceName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                HStack(spacing: 12) {
                    statBadge(icon: "doc.text", value: "\(snapshot.fileCount)", label: "Files")
                    statBadge(icon: "rectangle.3.group", value: "\(snapshot.componentCount)", label: "Components")
                    statBadge(icon: "rectangle.stack", value: "\(snapshot.screens.count)", label: "Screens")
                }
            }

            if snapshot.navigationKind != .none {
                HStack(spacing: 8) {
                    Image(systemName: snapshot.navigationKind.iconName)
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                    Text("\(snapshot.navigationKind.displayName) Navigation")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.accent.opacity(0.08), in: Capsule())
            }

            if let entry = snapshot.entryFile {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.right.circle")
                        .font(.caption)
                        .foregroundStyle(Theme.accent.opacity(0.7))
                    Text("Entry: \(entry)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.dimText)
                }
            }

            if !snapshot.screens.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SCREENS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.dimText)

                    ForEach(snapshot.screens) { screen in
                        HStack(spacing: 10) {
                            Image(systemName: "rectangle.portrait")
                                .font(.caption)
                                .foregroundStyle(Theme.accent.opacity(0.6))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(screen.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.white)

                                Text(screen.filePath)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(Theme.dimText)
                            }

                            Spacer()

                            if screen.isEntry {
                                Text("Entry")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Theme.accent)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Theme.accent.opacity(0.12), in: Capsule())
                            }
                        }
                        .padding(10)
                        .background(Theme.cardBg, in: .rect(cornerRadius: 10))
                    }
                }
            }

            if let report = coordinator.report, !report.workspaceNotes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("NOTES")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.dimText)

                    ForEach(Array(report.workspaceNotes.suffix(3).enumerated()), id: \.offset) { item in
                        Text(item.element)
                            .font(.caption)
                            .foregroundStyle(Theme.dimText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Theme.cardBg, in: .rect(cornerRadius: 10))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("PREVIEW")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.dimText)

                VStack(spacing: 12) {
                    Image(systemName: "iphone")
                        .font(.system(size: 48, weight: .ultraLight))
                        .foregroundStyle(Theme.dimText.opacity(0.4))

                    Text("Structural Preview")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)

                    Text("HybridCoder is confirming structure, entry points, and diagnostics here.\nRun the same workspace with Expo on your Mac for a live runtime preview.")
                        .font(.caption)
                        .foregroundStyle(Theme.dimText)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(Theme.cardBg, in: .rect(cornerRadius: 14))
            }
        }
    }

    private func diagnosticFallbackView(_ diagnostics: [ProjectDiagnostic]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DIAGNOSTICS-ONLY")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.dimText)

            Text("This workspace is loaded into the builder model, but HybridCoder is only surfacing structural diagnostics until Expo / React Native support is confirmed.")
                .font(.caption)
                .foregroundStyle(Theme.dimText)

            failedPreview(diagnostics)
        }
    }

    private func failedPreview(_ diagnostics: [ProjectDiagnostic]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DIAGNOSTICS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.dimText)

            ForEach(diagnostics) { diagnostic in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: diagnosticIcon(diagnostic.severity))
                        .font(.caption)
                        .foregroundStyle(diagnosticColor(diagnostic.severity))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(diagnostic.message)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))

                        if let path = diagnostic.filePath {
                            Text(path)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(Theme.dimText)
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.cardBg, in: .rect(cornerRadius: 8))
            }
        }
    }

    private var validatingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(Theme.accent)

            Text("Analyzing project structure and diagnostics…")
                .font(.subheadline)
                .foregroundStyle(Theme.dimText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var emptyPreview: some View {
        VStack(spacing: 16) {
            Image(systemName: "eye.slash")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.dimText.opacity(0.4))

            Text("No Preview Data Yet")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)

            Text("Validate the current workspace to inspect entry points, files, and preview readiness.")
                .font(.caption)
                .foregroundStyle(Theme.dimText)
                .multilineTextAlignment(.center)
        }
    }

    private var statusIcon: String {
        switch coordinator.state {
        case .idle:
            return "eye"
        case .validating:
            return "clock"
        case .diagnosticFallback:
            return "stethoscope"
        case .structuralReady:
            return "checkmark.seal"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    private var statusColor: Color {
        switch coordinator.state {
        case .diagnosticFallback:
            return .yellow
        case .structuralReady:
            return .green
        case .failed:
            return .orange
        case .idle, .validating:
            return Theme.accent
        }
    }

    private func diagnosticIcon(_ severity: ProjectDiagnostic.Severity) -> String {
        switch severity {
        case .error: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private func diagnosticColor(_ severity: ProjectDiagnostic.Severity) -> Color {
        switch severity {
        case .error: return .red
        case .warning: return .orange
        case .info: return Theme.accent
        }
    }

    private func statBadge(icon: String, value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(Theme.accent)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }

            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.dimText)
        }
        .padding(10)
        .background(Theme.cardBg, in: .rect(cornerRadius: 10))
    }
}
