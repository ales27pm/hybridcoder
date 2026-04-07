import SwiftUI

struct TemplatePickerView: View {
    @Binding var selectedTemplate: ProjectTemplate?
    @State private var selectedCategory: ProjectTemplate.Category?

    private let grouped = ProjectTemplate.grouped()

    var body: some View {
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

                ForEach(ProjectTemplate.Category.allCases, id: \.self) { category in
                    categoryChip(label: category.rawValue, icon: category.iconName, category: category)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Theme.cardBg)
    }

    private func categoryChip(label: String, icon: String, category: ProjectTemplate.Category?) -> some View {
        let isActive = selectedCategory == category

        return Button {
            withAnimation(.snappy(duration: 0.25)) {
                selectedCategory = category
            }
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
            .background(
                isActive ? Theme.accent.opacity(0.25) : Theme.inputBg,
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .strokeBorder(isActive ? Theme.accent.opacity(0.4) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isActive)
    }

    private var filteredTemplates: [ProjectTemplate] {
        if let category = selectedCategory {
            return ProjectTemplate.all.filter { $0.category == category }
        }
        return ProjectTemplate.all
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

                            LazyVGrid(
                                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                                spacing: 10
                            ) {
                                ForEach(templates) { template in
                                    TemplateCard(
                                        template: template,
                                        isSelected: selectedTemplate?.id == template.id
                                    ) {
                                        withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
                                            selectedTemplate = template
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
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(filteredTemplates) { template in
                        TemplateCard(
                            template: template,
                            isSelected: selectedTemplate?.id == template.id
                        ) {
                            withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
                                selectedTemplate = template
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
    }
}

private struct TemplateCard: View {
    let template: ProjectTemplate
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
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

                    Text(template.category.rawValue)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.dimText)
                }
            }
            .padding(12)
            .background(
                isSelected ? Theme.accent.opacity(0.06) : Theme.cardBg,
                in: .rect(cornerRadius: 14)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        isSelected ? Theme.accent.opacity(0.4) : Theme.border,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: isSelected)
    }
}
