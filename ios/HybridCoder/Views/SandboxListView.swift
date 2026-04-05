import SwiftUI

struct SandboxListView: View {
    @Bindable var viewModel: SandboxViewModel

    var body: some View {
        Group {
            if viewModel.projects.isEmpty && !viewModel.isLoading {
                emptyState
            } else {
                projectList
            }
        }
        .background(Theme.surfaceBg)
        .task {
            await viewModel.loadProjects()
        }
        .alert("Delete Project?", isPresented: $viewModel.showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let project = viewModel.projectToDelete {
                    Task { await viewModel.deleteProject(project) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let project = viewModel.projectToDelete {
                Text("\(project.name) will be permanently deleted.")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "hammer.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Theme.accent.opacity(0.4))

            Text("Prototype Lab")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)

            Text("Build isolated React Native / Expo snippets.\nThese prototypes are not synced to imported repositories.")
                .font(.subheadline)
                .foregroundStyle(Theme.dimText)
                .multilineTextAlignment(.center)

            Button {
                viewModel.showNewProjectSheet = true
            } label: {
                Label("New Prototype", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.regular)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var projectList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.projects) { project in
                    ProjectCard(project: project) {
                        viewModel.openProject(project)
                    } onDelete: {
                        viewModel.projectToDelete = project
                        viewModel.showDeleteConfirmation = true
                    } onDuplicate: {
                        Task { await viewModel.duplicateProject(project) }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

private struct ProjectCard: View {
    let project: SandboxProject
    let onOpen: () -> Void
    let onDelete: () -> Void
    let onDuplicate: () -> Void

    var body: some View {
        Button {
            onOpen()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.accent.opacity(0.12))
                        .frame(width: 44, height: 44)

                    Image(systemName: project.templateType.iconName)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(project.templateType.rawValue)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Theme.accent.opacity(0.7))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.accent.opacity(0.1), in: Capsule())

                        Text("\(project.files.count) file\(project.files.count == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(Theme.dimText)
                    }

                    Text(project.lastOpenedAt.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(Theme.dimText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.dimText)
            }
            .padding(14)
            .background(Theme.cardBg, in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open", systemImage: "arrow.right.circle") { onOpen() }
            Button("Duplicate", systemImage: "doc.on.doc") { onDuplicate() }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { onDelete() }
        }
    }
}

struct NewSandboxProjectSheet: View {
    @Bindable var viewModel: SandboxViewModel
    @State private var projectName: String = ""
    @State private var selectedTemplate: SandboxProject.TemplateType = .helloWorld
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Project Name")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.dimText)

                        TextField("My App", text: $projectName)
                            .font(.body)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Theme.inputBg, in: .rect(cornerRadius: 10))
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Template")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.dimText)

                        ForEach(SandboxProject.TemplateType.allCases, id: \.self) { template in
                            TemplateRow(
                                template: template,
                                isSelected: selectedTemplate == template
                            ) {
                                selectedTemplate = template
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            .background(Theme.surfaceBg)
            .navigationTitle("New Prototype")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.dimText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            await viewModel.createProject(name: projectName, template: selectedTemplate)
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.accent)
                }
            }
            .toolbarBackground(Theme.cardBg, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct TemplateRow: View {
    let template: SandboxProject.TemplateType
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: template.iconName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.dimText)
                    .frame(width: 32, height: 32)
                    .background(
                        isSelected ? Theme.accent.opacity(0.12) : Theme.codeBg,
                        in: .rect(cornerRadius: 8)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(template.rawValue)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)

                    Text(template.description)
                        .font(.caption2)
                        .foregroundStyle(Theme.dimText)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(12)
            .background(
                isSelected ? Theme.accent.opacity(0.06) : Theme.cardBg,
                in: .rect(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Theme.accent.opacity(0.3) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
