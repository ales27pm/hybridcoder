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

            Text("Create a prototype workspace or open any imported repository in Sandbox.\nBoth now share the same editing surface.")
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
    @State private var selectedTemplate: ProjectTemplate?
    @State private var currentStep: CreationStep = .template
    @Environment(\.dismiss) private var dismiss

    private enum CreationStep {
        case template
        case configure
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                switch currentStep {
                case .template:
                    templateStep
                case .configure:
                    configureStep
                }
            }
            .background(Theme.surfaceBg)
            .navigationTitle(currentStep == .template ? "Choose Template" : "Configure")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        if currentStep == .configure {
                            withAnimation(.snappy(duration: 0.25)) {
                                currentStep = .template
                            }
                        } else {
                            dismiss()
                        }
                    } label: {
                        if currentStep == .configure {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.caption.weight(.semibold))
                                Text("Templates")
                            }
                            .foregroundStyle(Theme.accent)
                        } else {
                            Text("Cancel")
                                .foregroundStyle(Theme.dimText)
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if currentStep == .template {
                        Button("Next") {
                            withAnimation(.snappy(duration: 0.25)) {
                                currentStep = .configure
                            }
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.accent)
                        .disabled(selectedTemplate == nil)
                    } else {
                        Button("Create") {
                            guard let template = selectedTemplate else { return }
                            Task {
                                await viewModel.createProjectFromTemplate(name: projectName, template: template)
                                dismiss()
                            }
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.accent)
                    }
                }
            }
            .toolbarBackground(Theme.cardBg, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var templateStep: some View {
        TemplatePickerView(selectedTemplate: $selectedTemplate)
    }

    private var configureStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let template = selectedTemplate {
                    selectedTemplateBanner(template)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("PROJECT NAME")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.dimText)

                    TextField(selectedTemplate?.name ?? "My App", text: $projectName)
                        .font(.body)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Theme.inputBg, in: .rect(cornerRadius: 10))

                    Text("Leave blank to use the template name")
                        .font(.caption2)
                        .foregroundStyle(Theme.dimText)
                }

                if let template = selectedTemplate {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("INCLUDED FILES")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.dimText)

                        ForEach(template.files, id: \.name) { file in
                            HStack(spacing: 10) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.accent.opacity(0.7))
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.name)
                                        .font(.system(.subheadline, design: .monospaced).weight(.medium))
                                        .foregroundStyle(.white)

                                    Text("\(file.content.count) characters")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.dimText)
                                }

                                Spacer()
                            }
                            .padding(10)
                            .background(Theme.cardBg, in: .rect(cornerRadius: 10))
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
    }

    private func selectedTemplateBanner(_ template: ProjectTemplate) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(template.accentColor.opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: template.iconName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(template.accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(template.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Text(template.subtitle)
                    .font(.caption2)
                    .foregroundStyle(Theme.dimText)
            }

            Spacer()

            Button {
                withAnimation(.snappy(duration: 0.25)) {
                    currentStep = .template
                }
            } label: {
                Text("Change")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.accent.opacity(0.12), in: Capsule())
            }
        }
        .padding(14)
        .background(Theme.cardBg, in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(template.accentColor.opacity(0.2), lineWidth: 1)
        )
    }
}
