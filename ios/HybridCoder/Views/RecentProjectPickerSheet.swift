import SwiftUI

struct RecentProjectPickerSheet: View {
    @Bindable var containerViewModel: StudioContainerViewModel
    @Bindable var projectStudioViewModel: ProjectStudioViewModel
    @Bindable var workspaceViewModel: WorkspaceSessionViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if !projectStudioViewModel.bookmarkService.repositories.isEmpty {
                        repoSection
                    }

                    if !projectStudioViewModel.sandboxViewModel.studioProjects.isEmpty {
                        sandboxSection
                    }

                    if projectStudioViewModel.bookmarkService.repositories.isEmpty && projectStudioViewModel.sandboxViewModel.studioProjects.isEmpty {
                        emptyState
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Theme.surfaceBg)
            .navigationTitle("Open Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.dimText)
                }

                ToolbarItem(placement: .bottomBar) {
                    Button {
                        dismiss()
                        containerViewModel.isImportingFolder = true
                    } label: {
                        Label("Import from Files", systemImage: "folder.badge.plus")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                }
            }
            .toolbarBackground(Theme.cardBg, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private var repoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("REPOSITORIES")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.dimText)

            ForEach(projectStudioViewModel.bookmarkService.repositories.sorted(by: { $0.lastOpened > $1.lastOpened })) { repo in
                Button {
                    projectStudioViewModel.openRepository(repo, workspace: workspaceViewModel)
                    containerViewModel.selectedSection = .chat
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 32, height: 32)
                            .background(Theme.accent.opacity(0.1), in: .rect(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(repo.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white)

                            Text("\(repo.fileCount) files · \(repo.lastOpened.formatted(.relative(presentation: .named)))")
                                .font(.caption2)
                                .foregroundStyle(Theme.dimText)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(Theme.dimText)
                    }
                    .padding(12)
                    .background(Theme.cardBg, in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sandboxSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PROTOTYPES")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.dimText)

            ForEach(projectStudioViewModel.sandboxViewModel.studioProjects) { project in
                Button {
                    projectStudioViewModel.openStudioProject(project, workspace: workspaceViewModel, container: containerViewModel)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: project.kind.iconName)
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 32, height: 32)
                            .background(Theme.accent.opacity(0.1), in: .rect(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white)

                            Text("\(project.fileCount) file\(project.fileCount == 1 ? "" : "s") · Builder Project")
                                .font(.caption2)
                                .foregroundStyle(Theme.dimText)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(Theme.dimText)
                    }
                    .padding(12)
                    .background(Theme.cardBg, in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 40)

            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.dimText)

            Text("No Projects Yet")
                .font(.headline)
                .foregroundStyle(.white)

            Text("Import a repository from the Files app\nor create a sandbox prototype.")
                .font(.subheadline)
                .foregroundStyle(Theme.dimText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}
