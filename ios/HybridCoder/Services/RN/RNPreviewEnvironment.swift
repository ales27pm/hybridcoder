import Foundation
import OSLog

actor RNPreviewEnvironment {
    private let storage: AsyncStorageService
    private let logger = Logger(subsystem: "com.hybridcoder.app", category: "RNPreviewEnvironment")
    private let projectID: UUID

    private static let stateKeyPrefix = "rn_preview_state_"
    private static let asyncStorageKeyPrefix = "rn_async_storage_"
    private static let parseCacheKeyPrefix = "rn_parse_cache_"

    init(projectID: UUID, storage: AsyncStorageService) {
        self.projectID = projectID
        self.storage = storage
    }

    func loadPreviewState() async -> RNPreviewState {
        let key = Self.stateKeyPrefix + projectID.uuidString
        do {
            if let state: RNPreviewState = try await storage.getObject(key, as: RNPreviewState.self) {
                logger.debug("Loaded preview state for \(self.projectID.uuidString.prefix(8))")
                return state
            }
        } catch {
            logger.error("Failed to load preview state: \(error.localizedDescription)")
        }
        return RNPreviewState(projectID: projectID)
    }

    func savePreviewState(_ state: RNPreviewState) async {
        let key = Self.stateKeyPrefix + projectID.uuidString
        do {
            try await storage.setObject(key, value: state)
            logger.debug("Saved preview state for \(self.projectID.uuidString.prefix(8))")
        } catch {
            logger.error("Failed to save preview state: \(error.localizedDescription)")
        }
    }

    func setAsyncStorageItem(_ key: String, value: String) async {
        let storageKey = Self.asyncStorageKeyPrefix + projectID.uuidString + "_" + key
        do {
            try await storage.setItem(storageKey, value: value)
        } catch {
            logger.error("AsyncStorage setItem failed for \(key): \(error.localizedDescription)")
        }
    }

    func getAsyncStorageItem(_ key: String) async -> String? {
        let storageKey = Self.asyncStorageKeyPrefix + projectID.uuidString + "_" + key
        do {
            return try await storage.getItem(storageKey)
        } catch {
            logger.error("AsyncStorage getItem failed for \(key): \(error.localizedDescription)")
            return nil
        }
    }

    func removeAsyncStorageItem(_ key: String) async {
        let storageKey = Self.asyncStorageKeyPrefix + projectID.uuidString + "_" + key
        do {
            try await storage.removeItem(storageKey)
        } catch {
            logger.error("AsyncStorage removeItem failed for \(key): \(error.localizedDescription)")
        }
    }

    func getAllAsyncStorageKeys() async -> [String] {
        let prefix = Self.asyncStorageKeyPrefix + projectID.uuidString + "_"
        do {
            let allKeys = try await storage.getAllKeys()
            return allKeys
                .filter { $0.hasPrefix(prefix) }
                .map { String($0.dropFirst(prefix.count)) }
        } catch {
            logger.error("AsyncStorage getAllKeys failed: \(error.localizedDescription)")
            return []
        }
    }

    func multiGetAsyncStorage(_ keys: [String]) async -> [String: String] {
        let prefix = Self.asyncStorageKeyPrefix + projectID.uuidString + "_"
        let prefixedKeys = keys.map { prefix + $0 }
        do {
            let results = try await storage.multiGet(prefixedKeys)
            var mapped: [String: String] = [:]
            for (prefixedKey, value) in results {
                let originalKey = String(prefixedKey.dropFirst(prefix.count))
                mapped[originalKey] = value
            }
            return mapped
        } catch {
            logger.error("AsyncStorage multiGet failed: \(error.localizedDescription)")
            return [:]
        }
    }

    func multiSetAsyncStorage(_ pairs: [String: String]) async {
        let prefix = Self.asyncStorageKeyPrefix + projectID.uuidString + "_"
        let prefixedPairs = Dictionary(uniqueKeysWithValues: pairs.map { (prefix + $0.key, $0.value) })
        do {
            try await storage.multiSet(prefixedPairs)
        } catch {
            logger.error("AsyncStorage multiSet failed: \(error.localizedDescription)")
        }
    }

    func clearAsyncStorage() async {
        let prefix = Self.asyncStorageKeyPrefix + projectID.uuidString + "_"
        do {
            let allKeys = try await storage.getAllKeys()
            let projectKeys = allKeys.filter { $0.hasPrefix(prefix) }
            if !projectKeys.isEmpty {
                try await storage.multiRemove(projectKeys)
            }
            logger.info("Cleared AsyncStorage for project \(self.projectID.uuidString.prefix(8))")
        } catch {
            logger.error("AsyncStorage clear failed: \(error.localizedDescription)")
        }
    }

    func cacheParseResult(_ screens: [RNParsedScreen]) async {
        let key = Self.parseCacheKeyPrefix + projectID.uuidString
        let cacheEntry = ParseCacheEntry(
            screenNames: screens.map(\.name),
            screenCount: screens.count,
            cachedAt: Date()
        )
        do {
            try await storage.setObject(key, value: cacheEntry)
        } catch {
            logger.error("Failed to cache parse result: \(error.localizedDescription)")
        }
    }

    func loadCachedParseInfo() async -> ParseCacheEntry? {
        let key = Self.parseCacheKeyPrefix + projectID.uuidString
        do {
            return try await storage.getObject(key, as: ParseCacheEntry.self)
        } catch {
            logger.error("Failed to load parse cache: \(error.localizedDescription)")
            return nil
        }
    }

    func updateNavigationStack(_ stack: [String]) async {
        var state = await loadPreviewState()
        state.navigationStack = stack
        state.lastPreviewedAt = Date()
        await savePreviewState(state)
    }

    func setActiveScreen(_ screenName: String) async {
        var state = await loadPreviewState()
        state.activeScreenName = screenName
        state.lastPreviewedAt = Date()
        await savePreviewState(state)
    }

    func saveComponentState(componentID: String, stateJSON: String) async {
        var state = await loadPreviewState()
        state.componentStates[componentID] = stateJSON
        await savePreviewState(state)
    }

    func clearAllPreviewData() async {
        await clearAsyncStorage()
        let stateKey = Self.stateKeyPrefix + projectID.uuidString
        let cacheKey = Self.parseCacheKeyPrefix + projectID.uuidString
        do {
            try await storage.removeItem(stateKey)
            try await storage.removeItem(cacheKey)
            logger.info("Cleared all preview data for project \(self.projectID.uuidString.prefix(8))")
        } catch {
            logger.error("Failed to clear preview data: \(error.localizedDescription)")
        }
    }
}

nonisolated struct ParseCacheEntry: Codable, Sendable {
    let screenNames: [String]
    let screenCount: Int
    let cachedAt: Date
}
