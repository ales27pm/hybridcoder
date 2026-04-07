import SwiftUI

struct RecentProjectPickerSheet: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if !viewModel.bookmarkService.repositories.isEmpty {
                        repoSection
                    }

                    if !viewModel.sandboxViewModel.projects.isEmpty {
                        sandboxSection
                    }

                    if viewModel.bookmarkService.repositories.isEmpty && viewModel.sandboxViewModel.projects.isEmpty {
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
                        viewModel.isImportingFolder = true
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

            ForEach(viewModel.bookmarkService.repositories.sorted(by: { $0.lastOpened > $1.lastOpened })) { repo in
                Button {
                    viewModel.openRepository(repo)
                    viewModel.selectedSection = .chat
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

            ForEach(viewModel.sandboxViewModel.projects) { project in
                Button {
                    viewModel.openPrototypeProject(project)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: project.templateType.iconName)
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 32, height: 32)
                            .background(Theme.accent.opacity(0.1), in: .rect(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white)

                            Text("\(project.files.count) file\(project.files.count == 1 ? "" : "s") · \(project.templateType.rawValue)")
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
