import SwiftUI

struct AsyncStorageInspectorView: View {
    @Bindable var viewModel: RNPreviewViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var newKey: String = ""
    @State private var newValue: String = ""
    @State private var searchText: String = ""
    @State private var editingKey: String?
    @State private var editValue: String = ""
    @State private var expandedKeys: Set<String> = []
    @State private var showImportSheet: Bool = false
    @State private var importJSON: String = ""

    private var filteredKeys: [String] {
        if searchText.isEmpty { return viewModel.asyncStorageKeys }
        return viewModel.asyncStorageKeys.filter { key in
            key.localizedCaseInsensitiveContains(searchText) ||
            (viewModel.asyncStorageData[key]?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !viewModel.asyncStorageKeys.isEmpty {
                    searchSection
                }
                storedKeysSection
                addEntrySection
                bulkActionsSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.surfaceBg)
            .navigationTitle("AsyncStorage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await viewModel.refreshAsyncStorageData() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            .sheet(isPresented: $showImportSheet) {
                importJSONSheet
            }
        }
        .task { await viewModel.refreshAsyncStorageData() }
    }

    @ViewBuilder
    private var searchSection: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(Theme.dimText)
                TextField("Search keys or values…", text: $searchText)
                    .font(.system(.subheadline, design: .monospaced))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.dimText)
                    }
                }
            }
            .listRowBackground(Theme.inputBg)
        }
    }

    private var storedKeysSection: some View {
        Section {
            if filteredKeys.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: searchText.isEmpty ? "cylinder.split.1x2" : "magnifyingglass")
                            .font(.title2)
                            .foregroundStyle(Theme.dimText.opacity(0.5))
                        Text(searchText.isEmpty ? "No stored data" : "No matching keys")
                            .font(.subheadline)
                            .foregroundStyle(Theme.dimText)
                        if searchText.isEmpty {
                            Text("Use the form below to add entries, or interact with components in the preview.")
                                .font(.caption2)
                                .foregroundStyle(Theme.dimText.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
                .listRowBackground(Theme.cardBg)
            } else {
                ForEach(filteredKeys, id: \.self) { key in
                    storageRow(key: key)
                }
            }
        } header: {
            HStack {
                Text("Stored Keys (\(viewModel.asyncStorageKeys.count))")
                Spacer()
                if !viewModel.asyncStorageKeys.isEmpty {
                    Text("\(totalStorageSize) bytes")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.dimText)
                }
            }
        }
    }

    @ViewBuilder
    private func storageRow(key: String) -> some View {
        let value = viewModel.asyncStorageData[key] ?? "null"
        let isExpanded = expandedKeys.contains(key)
        let isEditing = editingKey == key
        let isJSON = isJSONValue(value)
        let isBinding = viewModel.stateManager.asyncStorageBindings[key] != nil

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if isBinding {
                    Image(systemName: "link.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.accent)
                }
                Text(key)
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Theme.accent)

                Spacer()

                if isJSON {
                    Button {
                        if isExpanded {
                            expandedKeys.remove(key)
                        } else {
                            expandedKeys.insert(key)
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.dimText)
                    }
                }

                Button {
                    if isEditing {
                        editingKey = nil
                    } else {
                        editingKey = key
                        editValue = value
                    }
                } label: {
                    Image(systemName: isEditing ? "checkmark.circle" : "pencil")
                        .font(.system(size: 11))
                        .foregroundStyle(isEditing ? Theme.accent : Theme.dimText)
                }
            }

            if isEditing {
                TextField("Value", text: $editValue, axis: .vertical)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1...8)
                    .padding(8)
                    .background(Theme.inputBg, in: .rect(cornerRadius: 6))

                HStack(spacing: 8) {
                    Button("Save") {
                        Task {
                            await viewModel.updateAsyncStorageItem(key: key, value: editValue)
                            editingKey = nil
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)

                    Button("Cancel") {
                        editingKey = nil
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.dimText)
                }
            } else if isJSON && isExpanded {
                Text(prettyPrintJSON(value))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.codeBg, in: .rect(cornerRadius: 6))
            } else {
                Text(value)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(isExpanded ? nil : 3)
            }

            HStack(spacing: 8) {
                Text(dataTypeLabel(value))
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(dataTypeColor(value))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(dataTypeColor(value).opacity(0.12), in: Capsule())

                Text("\(value.utf8.count) bytes")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(Theme.dimText)

                Spacer()

                Button {
                    UIPasteboard.general.string = value
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.dimText)
                }
            }
        }
        .listRowBackground(Theme.cardBg)
        .swipeActions(edge: .trailing) {
            Button("Delete", role: .destructive) {
                Task { await viewModel.removeAsyncStorageItem(key: key) }
            }
        }
        .swipeActions(edge: .leading) {
            Button("Copy") {
                UIPasteboard.general.string = "\(key): \(value)"
            }
            .tint(.blue)
        }
    }

    private var addEntrySection: some View {
        Section("Add Entry") {
            TextField("Key", text: $newKey)
                .font(.system(.body, design: .monospaced))
                .listRowBackground(Theme.inputBg)
            TextField("Value", text: $newValue, axis: .vertical)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1...4)
                .listRowBackground(Theme.inputBg)
            Button {
                guard !newKey.isEmpty else { return }
                Task {
                    await viewModel.setAsyncStorageItem(key: newKey, value: newValue)
                    newKey = ""
                    newValue = ""
                }
            } label: {
                Label("Set Item", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.medium))
            }
            .disabled(newKey.isEmpty)
            .listRowBackground(Theme.cardBg)
        }
    }

    private var bulkActionsSection: some View {
        Section {
            Button {
                showImportSheet = true
            } label: {
                Label("Import JSON", systemImage: "square.and.arrow.down")
                    .font(.subheadline)
            }
            .listRowBackground(Theme.cardBg)

            if !viewModel.asyncStorageKeys.isEmpty {
                Button {
                    let export = exportAsJSON()
                    UIPasteboard.general.string = export
                } label: {
                    Label("Copy All as JSON", systemImage: "doc.on.clipboard")
                        .font(.subheadline)
                }
                .listRowBackground(Theme.cardBg)
            }

            Button("Clear All Storage", role: .destructive) {
                Task { await viewModel.clearAsyncStorage() }
            }
            .listRowBackground(Theme.cardBg)
        } header: {
            Text("Bulk Actions")
        }
    }

    private var importJSONSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Paste a JSON object to import key-value pairs into AsyncStorage.")
                    .font(.caption)
                    .foregroundStyle(Theme.dimText)

                TextEditor(text: $importJSON)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Theme.codeBg, in: .rect(cornerRadius: 8))
                    .frame(minHeight: 200)

                Spacer()
            }
            .padding(16)
            .background(Theme.surfaceBg)
            .navigationTitle("Import JSON")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showImportSheet = false }
                        .foregroundStyle(Theme.dimText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        Task {
                            await importJSONData()
                            showImportSheet = false
                            importJSON = ""
                        }
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.accent)
                    .disabled(importJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var totalStorageSize: Int {
        viewModel.asyncStorageData.reduce(0) { total, pair in
            total + pair.key.utf8.count + pair.value.utf8.count
        }
    }

    private func isJSONValue(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
               (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
    }

    private func prettyPrintJSON(_ value: String) -> String {
        guard let data = value.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8) else {
            return value
        }
        return str
    }

    private func dataTypeLabel(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "true" || trimmed == "false" { return "bool" }
        if trimmed == "null" { return "null" }
        if Double(trimmed) != nil { return "number" }
        if isJSONValue(trimmed) {
            return trimmed.hasPrefix("[") ? "array" : "object"
        }
        return "string"
    }

    private func dataTypeColor(_ value: String) -> Color {
        let label = dataTypeLabel(value)
        switch label {
        case "bool": return .orange
        case "null": return .gray
        case "number": return .purple
        case "array", "object": return .cyan
        default: return Theme.accent
        }
    }

    private func exportAsJSON() -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: viewModel.asyncStorageData,
            options: [.prettyPrinted, .sortedKeys]
        ), let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }

    private func importJSONData() async {
        let trimmed = importJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        for (key, value) in obj {
            let stringValue: String
            if let str = value as? String {
                stringValue = str
            } else if let num = value as? NSNumber {
                stringValue = num.stringValue
            } else if let jsonData = try? JSONSerialization.data(withJSONObject: value),
                      let jsonStr = String(data: jsonData, encoding: .utf8) {
                stringValue = jsonStr
            } else {
                stringValue = "\(value)"
            }
            await viewModel.setAsyncStorageItem(key: key, value: stringValue)
        }
    }
}
