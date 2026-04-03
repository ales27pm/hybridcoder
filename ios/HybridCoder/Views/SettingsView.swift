import SwiftUI

struct SettingsView: View {
    let bookmarkService: BookmarkService
    let orchestrator: AIOrchestrator
    let onOpenRepository: (Repository) -> Void
    let onCloseRepository: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                repositoriesSection
                indexSection
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

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                    .font(.subheadline)
                Spacer()
                Text("1.0.0")
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
        } header: {
            Text("About")
        }
    }
}
