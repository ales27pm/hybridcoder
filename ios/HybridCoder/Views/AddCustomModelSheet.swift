import SwiftUI

struct AddCustomModelSheet: View {
    let orchestrator: AIOrchestrator

    enum InputMode: String, CaseIterable, Identifiable {
        case directURL = "Direct URL"
        case huggingFace = "HuggingFace Repo"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss

    @State private var mode: InputMode = .directURL
    @State private var directURL: String = ""
    @State private var repoID: String = ""
    @State private var filename: String = ""
    @State private var revision: String = ""
    @State private var displayName: String = ""
    @State private var capability: ModelRegistry.Capability = .codeGeneration
    @State private var errorMessage: String?

    private var resolved: CustomModelInputParser.Resolved? {
        switch mode {
        case .directURL:
            return CustomModelInputParser.resolveDirectURL(directURL)
        case .huggingFace:
            return CustomModelInputParser.resolveHuggingFaceRepo(
                repoID: repoID,
                filename: filename,
                revision: revision.isEmpty ? nil : revision
            )
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Source") {
                    Picker("Input", selection: $mode) {
                        ForEach(InputMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch mode {
                    case .directURL:
                        TextField("https://.../file.gguf", text: $directURL, axis: .vertical)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .font(.system(.body, design: .monospaced))
                            .onChange(of: directURL) { _, newValue in
                                if displayName.isEmpty,
                                   let parsed = CustomModelInputParser.resolveDirectURL(newValue) {
                                    displayName = parsed.filename.replacingOccurrences(of: ".gguf", with: "")
                                }
                            }
                    case .huggingFace:
                        TextField("owner/repo", text: $repoID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .font(.system(.body, design: .monospaced))
                        TextField("filename.gguf", text: $filename)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .font(.system(.body, design: .monospaced))
                            .onChange(of: filename) { _, newValue in
                                if displayName.isEmpty, !newValue.isEmpty {
                                    displayName = newValue.replacingOccurrences(of: ".gguf", with: "")
                                }
                            }
                        TextField("Revision (defaults to main)", text: $revision)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .font(.system(.body, design: .monospaced))
                    }
                }

                Section("Model") {
                    TextField("Display name", text: $displayName)
                    Picker("Capability", selection: $capability) {
                        Text("Code Generation").tag(ModelRegistry.Capability.codeGeneration)
                        Text("Embedding").tag(ModelRegistry.Capability.embedding)
                    }
                }

                Section("Preview") {
                    if let resolved {
                        VStack(alignment: .leading, spacing: 6) {
                            labelRow("Filename", value: resolved.filename)
                            labelRow("Download URL", value: resolved.downloadURL, monospaced: true)
                            if let repo = resolved.repoID {
                                labelRow("Repo", value: repo)
                            }
                            if let revision = resolved.revision {
                                labelRow("Revision", value: revision)
                            }
                        }
                        .font(.caption)
                    } else {
                        Text("Enter a valid URL or repo + filename to preview.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add Custom Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add & Download") { commit() }
                        .disabled(resolved == nil)
                }
            }
        }
    }

    private func labelRow(_ label: String, value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(monospaced ? .system(.caption, design: .monospaced) : .caption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func commit() {
        guard let resolved else {
            errorMessage = "Invalid input. Check the URL or repo + filename."
            return
        }

        let finalName = displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? resolved.filename
            : displayName

        guard let entry = orchestrator.modelDownload.addCustomModel(
            displayName: finalName,
            capability: capability,
            resolved: resolved
        ) else {
            errorMessage = "Failed to register model."
            return
        }

        Task {
            await orchestrator.modelDownload.download(modelID: entry.id)
        }

        dismiss()
    }
}
