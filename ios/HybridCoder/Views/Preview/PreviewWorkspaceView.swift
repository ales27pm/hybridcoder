import SwiftUI

struct PreviewWorkspaceView: View {
    let coordinator: PreviewCoordinator
    let project: SandboxProject

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                statusHeader

                if let snapshot = coordinator.structuralSnapshot {
                    structuralPreview(snapshot)
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

                Text(statusSubtitle)
                    .font(.caption2)
                    .foregroundStyle(Theme.dimText)
            }

            Spacer()

            Button {
                Task { await coordinator.validate(project: project) }
            } label: {
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
                Text("APP STRUCTURE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.dimText)

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

                    Text("Your project structure has been analyzed.\nRun the project with Expo on your Mac for a live preview,\nor use the AI builder to iterate on your screens.")
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

    private func failedPreview(_ diagnostics: [ProjectDiagnostic]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("VALIDATION ISSUES")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.dimText)

            ForEach(diagnostics) { diag in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: diag.severity == .error ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(diag.severity == .error ? .red : .orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(diag.message)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                        if let path = diag.filePath {
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
            Text("Analyzing project structure…")
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

            Text("No Preview Available")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)

            Text("Add files to your project or tap\nthe refresh button to validate.")
                .font(.caption)
                .foregroundStyle(Theme.dimText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func statBadge(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.accent.opacity(0.7))
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.dimText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Theme.cardBg, in: .rect(cornerRadius: 10))
    }

    private var statusIcon: String {
        switch coordinator.state {
        case .idle: return "eye.slash"
        case .validating: return "arrow.triangle.2.circlepath"
        case .structuralReady: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch coordinator.state {
        case .idle: return Theme.dimText
        case .validating: return Theme.accent
        case .structuralReady: return .green
        case .failed: return .orange
        }
    }

    private var statusSubtitle: String {
        switch coordinator.state {
        case .idle: return "Tap refresh to analyze project structure"
        case .validating: return "Analyzing files and navigation…"
        case .structuralReady(let s): return "\(s.fileCount) files · \(s.screens.count) screens"
        case .failed(let d): return "\(d.count) issue\(d.count == 1 ? "" : "s") found"
        }
    }
}
