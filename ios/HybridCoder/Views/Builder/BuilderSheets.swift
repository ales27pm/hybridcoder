import SwiftUI

struct AddFileSheet: View {
    @Bindable var viewModel: SandboxViewModel
    let projectID: UUID
    @State private var fileName: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("File Name")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.dimText)

                TextField("Component.tsx", text: $fileName)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Theme.inputBg, in: .rect(cornerRadius: 10))

                Text("Include the file extension (e.g. .tsx, .ts, .json)")
                    .font(.caption2)
                    .foregroundStyle(Theme.dimText)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .background(Theme.surfaceBg)
            .navigationTitle("Add File")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.dimText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let name = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        Task {
                            await viewModel.addFileToProject(projectID, name: name)
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.accent)
                    .disabled(fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .toolbarBackground(Theme.cardBg, for: .navigationBar)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

struct RenameProjectSheet: View {
    @Bindable var viewModel: SandboxViewModel
    let project: SandboxProject
    @State private var newName: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Project Name")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.dimText)

                TextField("My App", text: $newName)
                    .font(.body)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Theme.inputBg, in: .rect(cornerRadius: 10))

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .background(Theme.surfaceBg)
            .navigationTitle("Rename")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.dimText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        Task {
                            await viewModel.renameProject(project.id, newName: name)
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.accent)
                }
            }
            .toolbarBackground(Theme.cardBg, for: .navigationBar)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear { newName = project.name }
    }
}
