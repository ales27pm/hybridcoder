import Foundation
import OSLog

@Observable
@MainActor
final class RNComponentStateManager {
    private(set) var componentStates: [String: ComponentState] = [:]
    private(set) var asyncStorageBindings: [String: AsyncStorageBinding] = [:]
    private(set) var hookDetections: [String: [DetectedHook]] = [:]

    private var environment: RNPreviewEnvironment?
    private let logger = Logger(subsystem: "com.hybridcoder.app", category: "RNComponentStateManager")

    nonisolated struct ComponentState: Sendable {
        var textInputs: [String: String] = [:]
        var toggleStates: [String: Bool] = [:]
        var counterValues: [String: Int] = [:]
        var selectedIndices: [String: Int] = [:]
        var customValues: [String: String] = [:]
    }

    nonisolated struct AsyncStorageBinding: Sendable {
        let componentID: String
        let stateKey: String
        let storageKey: String
        let defaultValue: String
    }

    nonisolated struct DetectedHook: Sendable {
        let hookType: HookType
        let stateVariable: String
        let storageKey: String?
        let defaultValue: String?
    }

    nonisolated enum HookType: String, Sendable {
        case useState
        case useAsyncStorage
        case useEffect
        case useCallback
    }

    func attach(environment: RNPreviewEnvironment) {
        self.environment = environment
    }

    func analyzeAndBind(screens: [RNParsedScreen], projectFiles: [StudioProjectFile]) async {
        hookDetections.removeAll()
        asyncStorageBindings.removeAll()

        for file in projectFiles {
            let hooks = detectHooks(in: file.content, filePath: file.path)
            if !hooks.isEmpty {
                hookDetections[file.path] = hooks
            }

            for hook in hooks where hook.hookType == .useAsyncStorage {
                if let storageKey = hook.storageKey {
                    let binding = AsyncStorageBinding(
                        componentID: file.path,
                        stateKey: hook.stateVariable,
                        storageKey: storageKey,
                        defaultValue: hook.defaultValue ?? ""
                    )
                    asyncStorageBindings[storageKey] = binding

                    let existing = await environment?.getAsyncStorageItem(storageKey)
                    if existing == nil, let defaultValue = hook.defaultValue {
                        await environment?.setAsyncStorageItem(storageKey, value: defaultValue)
                    }
                }
            }
        }

        await loadPersistedStates()
    }

    func getTextInput(componentID: String, inputKey: String) -> String {
        componentStates[componentID]?.textInputs[inputKey] ?? ""
    }

    func setTextInput(componentID: String, inputKey: String, value: String) {
        ensureState(for: componentID)
        componentStates[componentID]?.textInputs[inputKey] = value
        Task { await persistComponentState(componentID) }
    }

    func getToggle(componentID: String, toggleKey: String) -> Bool {
        componentStates[componentID]?.toggleStates[toggleKey] ?? false
    }

    func setToggle(componentID: String, toggleKey: String, value: Bool) {
        ensureState(for: componentID)
        componentStates[componentID]?.toggleStates[toggleKey] = value
        Task { await persistComponentState(componentID) }
    }

    func getCounter(componentID: String, counterKey: String) -> Int {
        componentStates[componentID]?.counterValues[counterKey] ?? 0
    }

    func incrementCounter(componentID: String, counterKey: String) {
        ensureState(for: componentID)
        let current = componentStates[componentID]?.counterValues[counterKey] ?? 0
        componentStates[componentID]?.counterValues[counterKey] = current + 1
        Task { await persistComponentState(componentID) }
    }

    func decrementCounter(componentID: String, counterKey: String) {
        ensureState(for: componentID)
        let current = componentStates[componentID]?.counterValues[counterKey] ?? 0
        componentStates[componentID]?.counterValues[counterKey] = current - 1
        Task { await persistComponentState(componentID) }
    }

    func getSelectedIndex(componentID: String, listKey: String) -> Int {
        componentStates[componentID]?.selectedIndices[listKey] ?? -1
    }

    func setSelectedIndex(componentID: String, listKey: String, index: Int) {
        ensureState(for: componentID)
        componentStates[componentID]?.selectedIndices[listKey] = index
        Task { await persistComponentState(componentID) }
    }

    func setAsyncStorageValue(key: String, value: String) async {
        await environment?.setAsyncStorageItem(key, value: value)
    }

    func getAsyncStorageValue(key: String) async -> String? {
        await environment?.getAsyncStorageItem(key)
    }

    func resetState(for componentID: String) {
        componentStates[componentID] = ComponentState()
        Task {
            await environment?.saveComponentState(componentID: componentID, stateJSON: "{}")
        }
    }

    func resetAllStates() {
        componentStates.removeAll()
        Task {
            await environment?.clearAllPreviewData()
        }
    }

    private func ensureState(for componentID: String) {
        if componentStates[componentID] == nil {
            componentStates[componentID] = ComponentState()
        }
    }

    private func persistComponentState(_ componentID: String) async {
        guard let state = componentStates[componentID] else { return }
        let serializable = SerializableComponentState(
            textInputs: state.textInputs,
            toggleStates: state.toggleStates,
            counterValues: state.counterValues,
            selectedIndices: state.selectedIndices,
            customValues: state.customValues
        )
        do {
            let data = try JSONEncoder().encode(serializable)
            if let json = String(data: data, encoding: .utf8) {
                await environment?.saveComponentState(componentID: componentID, stateJSON: json)
            }
        } catch {
            logger.error("Failed to persist component state: \(error.localizedDescription)")
        }
    }

    private func loadPersistedStates() async {
        guard let env = environment else { return }
        let previewState = await env.loadPreviewState()
        for (componentID, json) in previewState.componentStates {
            guard let data = json.data(using: .utf8) else { continue }
            do {
                let serialized = try JSONDecoder().decode(SerializableComponentState.self, from: data)
                componentStates[componentID] = ComponentState(
                    textInputs: serialized.textInputs,
                    toggleStates: serialized.toggleStates,
                    counterValues: serialized.counterValues,
                    selectedIndices: serialized.selectedIndices,
                    customValues: serialized.customValues
                )
            } catch {
                logger.error("Failed to deserialize state for \(componentID): \(error.localizedDescription)")
            }
        }
    }

    private func detectHooks(in content: String, filePath: String) -> [DetectedHook] {
        var hooks: [DetectedHook] = []

        let useStatePattern = #"const\s+\[(\w+),\s*\w+\]\s*=\s*useState\s*(?:<[^>]*>)?\s*\(([^)]*)\)"#
        if let regex = try? NSRegularExpression(pattern: useStatePattern) {
            let range = NSRange(content.startIndex..., in: content)
            let matches = regex.matches(in: content, range: range)
            for match in matches {
                if let nameRange = Range(match.range(at: 1), in: content) {
                    let name = String(content[nameRange])
                    var defaultVal: String?
                    if let valRange = Range(match.range(at: 2), in: content) {
                        defaultVal = String(content[valRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    hooks.append(DetectedHook(
                        hookType: .useState,
                        stateVariable: name,
                        storageKey: nil,
                        defaultValue: defaultVal
                    ))
                }
            }
        }

        let asyncGetPattern = #"AsyncStorage\.getItem\s*\(\s*['"]([^'"]+)['"]\s*\)"#
        if let regex = try? NSRegularExpression(pattern: asyncGetPattern) {
            let range = NSRange(content.startIndex..., in: content)
            let matches = regex.matches(in: content, range: range)
            for match in matches {
                if let keyRange = Range(match.range(at: 1), in: content) {
                    let storageKey = String(content[keyRange])
                    let stateVar = findAssociatedStateVar(for: storageKey, in: content)
                    hooks.append(DetectedHook(
                        hookType: .useAsyncStorage,
                        stateVariable: stateVar ?? storageKey,
                        storageKey: storageKey,
                        defaultValue: nil
                    ))
                }
            }
        }

        let asyncSetPattern = #"AsyncStorage\.setItem\s*\(\s*['"]([^'"]+)['"]\s*,\s*([^)]+)\)"#
        if let regex = try? NSRegularExpression(pattern: asyncSetPattern) {
            let range = NSRange(content.startIndex..., in: content)
            let matches = regex.matches(in: content, range: range)
            for match in matches {
                if let keyRange = Range(match.range(at: 1), in: content) {
                    let storageKey = String(content[keyRange])
                    let alreadyTracked = hooks.contains { $0.storageKey == storageKey }
                    if !alreadyTracked {
                        hooks.append(DetectedHook(
                            hookType: .useAsyncStorage,
                            stateVariable: storageKey,
                            storageKey: storageKey,
                            defaultValue: nil
                        ))
                    }
                }
            }
        }

        let multiGetPattern = #"AsyncStorage\.multiGet\s*\(\s*\[([^\]]+)\]"#
        if let regex = try? NSRegularExpression(pattern: multiGetPattern) {
            let range = NSRange(content.startIndex..., in: content)
            let matches = regex.matches(in: content, range: range)
            for match in matches {
                if let keysRange = Range(match.range(at: 1), in: content) {
                    let keysStr = String(content[keysRange])
                    let keyExtractor = #"['"]([^'"]+)['"]"#
                    if let keyRegex = try? NSRegularExpression(pattern: keyExtractor) {
                        let keyMatches = keyRegex.matches(in: keysStr, range: NSRange(keysStr.startIndex..., in: keysStr))
                        for km in keyMatches {
                            if let kr = Range(km.range(at: 1), in: keysStr) {
                                let key = String(keysStr[kr])
                                let alreadyTracked = hooks.contains { $0.storageKey == key }
                                if !alreadyTracked {
                                    hooks.append(DetectedHook(
                                        hookType: .useAsyncStorage,
                                        stateVariable: key,
                                        storageKey: key,
                                        defaultValue: nil
                                    ))
                                }
                            }
                        }
                    }
                }
            }
        }

        return hooks
    }

    private func findAssociatedStateVar(for storageKey: String, in content: String) -> String? {
        let pattern = #"const\s+\[(\w+),\s*\w+\]\s*=\s*useState"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let lines = content.components(separatedBy: .newlines)
        var stateVars: [String] = []

        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            if let match = regex.firstMatch(in: line, range: range),
               let nameRange = Range(match.range(at: 1), in: line) {
                stateVars.append(String(line[nameRange]))
            }
        }

        let storageKeyLower = storageKey.lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "")
        for v in stateVars {
            if v.lowercased().contains(storageKeyLower) || storageKeyLower.contains(v.lowercased()) {
                return v
            }
        }

        return stateVars.first
    }
}

nonisolated struct SerializableComponentState: Codable, Sendable {
    var textInputs: [String: String] = [:]
    var toggleStates: [String: Bool] = [:]
    var counterValues: [String: Int] = [:]
    var selectedIndices: [String: Int] = [:]
    var customValues: [String: String] = [:]
}
