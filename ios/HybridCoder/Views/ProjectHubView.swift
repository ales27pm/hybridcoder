import SwiftUI

struct ProjectHubView: View {
    @Bindable var containerViewModel: StudioContainerViewModel
    @Bindable var projectStudioViewModel: ProjectStudioViewModel
    @Bindable var workspaceViewModel: WorkspaceSessionViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    activeProjectCard
                    quickActions
                    recentRepositories
                    recentSandboxProjects
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Theme.surfaceBg)
            .navigationTitle("Projects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
            .toolbarBackground(Theme.cardBg, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var activeProjectCard: some View {
        if workspaceViewModel.activeRepositoryURL != nil || projectStudioViewModel.sandboxViewModel.activeProject != nil {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 8, height: 8)

                    Text("ACTIVE PROJECT")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.accent)
                }

                if let url = workspaceViewModel.activeRepositoryURL {
                    HStack(spacing: 12) {
                        Image(systemName: "folder.fill")
                            .font(.title3)
                            .foregroundStyle(Theme.accent)
                            .frame(width: 40, height: 40)
                            .background(Theme.accent.opacity(0.12), in: .rect(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(url.lastPathComponent)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)

                            if let stats = workspaceViewModel.orchestrator.indexStats {
                                Text("\(stats.indexedFiles) files · \(stats.embeddedChunks) chunks")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.dimText)
                            }

                            Text(workspaceViewModel.repositoryWorkspaceBadgeText)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Theme.accent.opacity(0.8))

                            Text(workspaceViewModel.repositoryWorkspaceDetailText)
                                .font(.caption2)
                                .foregroundStyle(Theme.dimText)
                                .lineLimit(3)
                        }

                        Spacer()

                        Button {
                            projectStudioViewModel.closeRepository(workspace: workspaceViewModel, container: containerViewModel)
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Theme.dimText)
                        }
                    }
                } else if let project = projectStudioViewModel.sandboxViewModel.activeProject {
                    HStack(spacing: 12) {
                        Image(systemName: project.templateType.iconName)
                            .font(.title3)
                            .foregroundStyle(Theme.accent)
                            .frame(width: 40, height: 40)
                            .background(Theme.accent.opacity(0.12), in: .rect(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(project.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)

                            Text("\(project.files.count) file\(project.files.count == 1 ? "" : "s") · Project")
                                .font(.caption2)
                                .foregroundStyle(Theme.dimText)
                        }

                        Spacer()

                        Button {
                            projectStudioViewModel.sandboxViewModel.closeProject()
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Theme.dimText)
                        }
                    }
                }
            }
            .padding(16)
            .background(Theme.cardBg, in: .rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Theme.accent.opacity(0.2), lineWidth: 1)
            )
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ACTIONS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.dimText)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ActionCard(
                    icon: "plus.rectangle.on.folder",
                    label: "New Project",
                    description: "RN/Expo app"
                ) {
                    projectStudioViewModel.prepareNewPrototypeProject(workspace: workspaceViewModel, container: containerViewModel)
                    dismiss()
                }

                ActionCard(
                    icon: "folder.badge.plus",
                    label: "Import Repo",
                    description: "From Files app"
                ) {
                    containerViewModel.isImportingFolder = true
                    dismiss()
                }

                ActionCard(
                    icon: "folder",
                    label: "Open Project",
                    description: "Recent repos"
                ) {
                    containerViewModel.showRecentPicker = true
                }

                ActionCard(
                    icon: "square.and.arrow.down",
                    label: "Save & Close",
                    description: "Current project",
                    disabled: workspaceViewModel.activeRepositoryURL == nil && projectStudioViewModel.sandboxViewModel.activeProject == nil
                ) {
                    if projectStudioViewModel.sandboxViewModel.activeProject != nil {
                        projectStudioViewModel.sandboxViewModel.closeProject()
                    }
                    if workspaceViewModel.activeRepositoryURL != nil {
                        projectStudioViewModel.closeRepository(workspace: workspaceViewModel, container: containerViewModel)
                    }
                    dismiss()
                }

                ActionCard(
                    icon: "arrow.down.doc",
                    label: "Import State",
                    description: "From repo .hybridcoder",
                    disabled: workspaceViewModel.activeRepositoryURL == nil || projectStudioViewModel.sandboxViewModel.activeProject == nil
                ) {
                    Task {
                        guard let project = projectStudioViewModel.sandboxViewModel.activeProject,
                              let repoURL = workspaceViewModel.activeRepositoryURL else { return }
                        await projectStudioViewModel.sandboxViewModel.exportStateFromProjectFolder(project.id, sourceRoot: repoURL)
                    }
                }

                ActionCard(
                    icon: "arrow.up.doc",
                    label: "Export State",
                    description: "To repo .hybridcoder",
                    disabled: workspaceViewModel.activeRepositoryURL == nil || projectStudioViewModel.sandboxViewModel.activeProject == nil
                ) {
                    Task {
                        guard let project = projectStudioViewModel.sandboxViewModel.activeProject,
                              let repoURL = workspaceViewModel.activeRepositoryURL else { return }
                        _ = await projectStudioViewModel.sandboxViewModel.importStateToProjectFolder(project.id, destinationRoot: repoURL)
                    }
                }
            }
        }
    }

    private var recentRepositories: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("REPOSITORIES")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.dimText)

                Spacer()

                if !projectStudioViewModel.bookmarkService.repositories.isEmpty {
                    Text("\(projectStudioViewModel.bookmarkService.repositories.count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.accent.opacity(0.6))
                }
            }

            if projectStudioViewModel.bookmarkService.repositories.isEmpty {
                emptyCard(
                    icon: "folder.badge.questionmark",
                    message: "No repositories imported yet.\nUse Import Repo to get started."
                )
            } else {
                ForEach(projectStudioViewModel.bookmarkService.repositories.sorted(by: { $0.lastOpened > $1.lastOpened }).prefix(5)) { repo in
                    RepoRow(repo: repo, isActive: workspaceViewModel.activeRepositoryURL?.lastPathComponent == repo.name) {
                        projectStudioViewModel.openRepository(repo, workspace: workspaceViewModel)
                        containerViewModel.selectedSection = .chat
                        dismiss()
                    }
                }
            }
        }
    }

    private var recentSandboxProjects: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PROJECTS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.dimText)

                Spacer()

                if !projectStudioViewModel.sandboxViewModel.projects.isEmpty {
                    Text("\(projectStudioViewModel.sandboxViewModel.projects.count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.accent.opacity(0.6))
                }
            }

            if projectStudioViewModel.sandboxViewModel.projects.isEmpty {
                emptyCard(
                    icon: "apps.iphone",
                    message: "No projects yet.\nCreate one from New Project."
                )
            } else {
                ForEach(projectStudioViewModel.sandboxViewModel.projects.prefix(5)) { project in
                    SandboxRow(
                        project: project,
                        isActive: projectStudioViewModel.sandboxViewModel.activeProject?.id == project.id
                    ) {
                        projectStudioViewModel.openPrototypeProject(project, workspace: workspaceViewModel, container: containerViewModel)
                        dismiss()
                    }
                }
            }
        }
    }

    private func emptyCard(icon: String, message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.dimText.opacity(0.6))

            Text(message)
                .font(.caption)
                .foregroundStyle(Theme.dimText)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.cardBg.opacity(0.6), in: .rect(cornerRadius: 12))
    }
}

private struct ActionCard: View {
    let icon: String
    let label: String
    let description: String
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(disabled ? Theme.dimText.opacity(0.4) : Theme.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(disabled ? Theme.dimText.opacity(0.5) : .white)

                    Text(description)
                        .font(.caption2)
                        .foregroundStyle(Theme.dimText.opacity(disabled ? 0.4 : 1))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.cardBg, in: .rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }
}

private struct RepoRow: View {
    let repo: Repository
    let isActive: Bool
    let onOpen: () -> Void

    var body: some View {
        Button {
            onOpen()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(isActive ? Theme.accent : Theme.accent.opacity(0.6))
                    .frame(width: 32, height: 32)
                    .background(Theme.accent.opacity(isActive ? 0.15 : 0.08), in: .rect(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(repo.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text("\(repo.fileCount) files · \(repo.lastOpened.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(Theme.dimText)
                }

                Spacer()

                if isActive {
                    Text("Active")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Theme.accent.opacity(0.12), in: Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(Theme.dimText)
            }
            .padding(12)
            .background(isActive ? Theme.accent.opacity(0.04) : Theme.cardBg, in: .rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isActive ? Theme.accent.opacity(0.2) : Theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SandboxRow: View {
    let project: SandboxProject
    let isActive: Bool
    let onOpen: () -> Void

    var body: some View {
        Button {
            onOpen()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: project.templateType.iconName)
                    .font(.system(size: 15))
                    .foregroundStyle(isActive ? Theme.accent : Theme.accent.opacity(0.6))
                    .frame(width: 32, height: 32)
                    .background(Theme.accent.opacity(isActive ? 0.15 : 0.08), in: .rect(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(project.templateType.rawValue)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Theme.accent.opacity(0.7))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Theme.accent.opacity(0.08), in: Capsule())

                        Text("\(project.files.count) file\(project.files.count == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(Theme.dimText)
                    }
                }

                Spacer()

                if isActive {
                    Text("Active")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Theme.accent.opacity(0.12), in: Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(Theme.dimText)
            }
            .padding(12)
            .background(isActive ? Theme.accent.opacity(0.04) : Theme.cardBg, in: .rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isActive ? Theme.accent.opacity(0.2) : Theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
