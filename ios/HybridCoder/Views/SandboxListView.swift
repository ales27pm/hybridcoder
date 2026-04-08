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

            Image(systemName: "apps.iphone")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Theme.accent.opacity(0.4))

            Text("Project Studio")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)

            Text("Create a new React Native / Expo project\nor open an imported repository to start building.")
                .font(.subheadline)
                .foregroundStyle(Theme.dimText)
                .multilineTextAlignment(.center)

            Button {
                viewModel.showNewProjectSheet = true
            } label: {
                Label("New Project", systemImage: "plus.circle.fill")
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
                ForEach(viewModel.studioProjects) { project in
                    ProjectCard(project: project) {
                        viewModel.openProject(project.asLegacySandboxProject())
                    } onDelete: {
                        viewModel.projectToDelete = project.asLegacySandboxProject()
                        viewModel.showDeleteConfirmation = true
                    } onDuplicate: {
                        Task { await viewModel.duplicateProject(project.asLegacySandboxProject()) }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

private struct ProjectCard: View {
    let project: StudioProject
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

                    Image(systemName: project.kind.iconName)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(project.templateReference?.name ?? project.kind.displayName)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Theme.accent.opacity(0.7))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.accent.opacity(0.1), in: Capsule())

                        Text("\(project.fileCount) file\(project.fileCount == 1 ? "" : "s")")
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
    @State private var selectedStudioTemplate: StudioTemplate?
    @State private var currentStep: CreationStep = .template
    @State private var selectedCategory: StudioTemplate.Category?
    @Environment(\.dismiss) private var dismiss

    private enum CreationStep {
        case template
        case configure
    }

    private var grouped: [(StudioTemplate.Category, [StudioTemplate])] {
        TemplateCatalog.grouped()
    }

    private var filteredTemplates: [StudioTemplate] {
        if let cat = selectedCategory {
            return TemplateCatalog.all.filter { $0.category == cat }
        }
        return TemplateCatalog.all
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
            .navigationTitle(currentStep == .template ? "New Project" : "Configure")
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
                        .disabled(selectedStudioTemplate == nil)
                    } else {
                        Button("Create") {
                            guard let template = selectedStudioTemplate else { return }
                            Task {
                                let spec = NewProjectSpec(
                                    name: projectName,
                                    templateID: template.id,
                                    kind: template.kind,
                                    navigationPreset: template.navigationPreset,
                                    source: .scaffold
                                )
                                await viewModel.createProject(from: spec)
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
        VStack(alignment: .leading, spacing: 0) {
            categoryTabs
            Divider().overlay(Theme.border)
            templateGrid
        }
    }

    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip(label: "All", icon: "square.grid.2x2", category: nil)
                ForEach(StudioTemplate.Category.allCases, id: \.self) { category in
                    categoryChip(label: category.rawValue, icon: category.iconName, category: category)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Theme.cardBg)
    }

    private func categoryChip(label: String, icon: String, category: StudioTemplate.Category?) -> some View {
        let isActive = selectedCategory == category
        return Button {
            withAnimation(.snappy(duration: 0.25)) { selectedCategory = category }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(label)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(isActive ? .white : Theme.dimText)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isActive ? Theme.accent.opacity(0.25) : Theme.inputBg, in: Capsule())
            .overlay(Capsule().strokeBorder(isActive ? Theme.accent.opacity(0.4) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isActive)
    }

    private var templateGrid: some View {
        ScrollView {
            if selectedCategory == nil {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(grouped, id: \.0) { category, templates in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 6) {
                                Image(systemName: category.iconName)
                                    .font(.system(size: 10, weight: .semibold))
                                Text(category.rawValue.uppercased())
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                            }
                            .foregroundStyle(Theme.dimText)
                            .padding(.horizontal, 16)

                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                                ForEach(templates) { template in
                                    StudioTemplateCard(template: template, isSelected: selectedStudioTemplate?.id == template.id) {
                                        withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
                                            selectedStudioTemplate = template
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.vertical, 16)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(filteredTemplates) { template in
                        StudioTemplateCard(template: template, isSelected: selectedStudioTemplate?.id == template.id) {
                            withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
                                selectedStudioTemplate = template
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
    }

    private var configureStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let template = selectedStudioTemplate {
                    studioTemplateBanner(template)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("PROJECT NAME")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.dimText)

                    TextField(selectedStudioTemplate?.name ?? "My App", text: $projectName)
                        .font(.body)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Theme.inputBg, in: .rect(cornerRadius: 10))

                    Text("Leave blank to use the template name")
                        .font(.caption2)
                        .foregroundStyle(Theme.dimText)
                }

                if let template = selectedStudioTemplate {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("INCLUDED FILES")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(Theme.dimText)
                            Spacer()
                            Text("\(template.files.count) files")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(Theme.accent.opacity(0.6))
                        }

                        ForEach(template.files, id: \.name) { file in
                            HStack(spacing: 10) {
                                Image(systemName: fileIcon(for: file.name))
                                    .font(.system(size: 13))
                                    .foregroundStyle(fileIconColor(for: file.name))
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.name)
                                        .font(.system(.subheadline, design: .monospaced).weight(.medium))
                                        .foregroundStyle(.white)

                                    Text(file.language)
                                        .font(.caption2)
                                        .foregroundStyle(Theme.dimText)
                                }

                                Spacer()
                            }
                            .padding(10)
                            .background(Theme.cardBg, in: .rect(cornerRadius: 10))
                        }
                    }

                    if template.navigationPreset != .none {
                        HStack(spacing: 8) {
                            Image(systemName: template.navigationPreset.iconName)
                                .font(.caption)
                                .foregroundStyle(Theme.accent)
                            Text("\(template.navigationPreset.displayName) Navigation")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.accent.opacity(0.08), in: Capsule())
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
    }

    private func studioTemplateBanner(_ template: StudioTemplate) -> some View {
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
                withAnimation(.snappy(duration: 0.25)) { currentStep = .template }
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

    private func fileIcon(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "js", "jsx": return "j.square"
        case "ts", "tsx": return "t.square"
        case "json": return "curlybraces"
        case "css": return "paintbrush"
        default: return "doc.text"
        }
    }

    private func fileIconColor(for name: String) -> Color {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "js", "jsx": return .yellow
        case "ts", "tsx": return .blue
        case "json": return .orange
        case "css": return .purple
        default: return Theme.dimText
        }
    }
}

private struct StudioTemplateCard: View {
    let template: StudioTemplate
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button { onTap() } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(template.accentColor.opacity(isSelected ? 0.25 : 0.12))
                            .frame(width: 36, height: 36)

                        Image(systemName: template.iconName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(template.accentColor)
                    }

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.accent)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(template.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(template.subtitle)
                        .font(.caption2)
                        .foregroundStyle(Theme.dimText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 6) {
                    Text("\(template.files.count) file\(template.files.count == 1 ? "" : "s")")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(template.accentColor.opacity(0.8))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(template.accentColor.opacity(0.1), in: Capsule())

                    if template.kind.isTypeScript {
                        Text("TS")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.blue.opacity(0.8))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.1), in: Capsule())
                    }

                    if template.navigationPreset != .none {
                        Image(systemName: template.navigationPreset.iconName)
                            .font(.system(size: 8))
                            .foregroundStyle(Theme.dimText)
                    }
                }
            }
            .padding(12)
            .background(isSelected ? Theme.accent.opacity(0.06) : Theme.cardBg, in: .rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isSelected ? Theme.accent.opacity(0.4) : Theme.border, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: isSelected)
    }
}
