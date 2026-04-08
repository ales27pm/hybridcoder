import Foundation
import OSLog

@Observable
@MainActor
final class RNPreviewViewModel {
    private(set) var screens: [RNParsedScreen] = []
    private(set) var activeScreen: RNParsedScreen?
    private(set) var navigationStack: [String] = []
    private(set) var parseState: ParseState = .idle
    private(set) var asyncStorageKeys: [String] = []
    private(set) var asyncStorageData: [String: String] = [:]
    private(set) var errorMessage: String?
    private(set) var lastParsedAt: Date?
    private(set) var hookSummary: HookSummary = HookSummary()

    let stateManager = RNComponentStateManager()

    var showAsyncStorageInspector: Bool = false
    var showScreenPicker: Bool = false
    var showHookInspector: Bool = false

    private var environment: RNPreviewEnvironment?
    private var currentProjectID: UUID?
    private let logger = Logger(subsystem: "com.hybridcoder.app", category: "RNPreviewViewModel")

    struct HookSummary: Sendable {
        var totalHooks: Int = 0
        var useStateCount: Int = 0
        var asyncStorageCount: Int = 0
        var boundStorageKeys: [String] = []
    }

    enum ParseState: Sendable {
        case idle
        case parsing
        case ready
        case failed(String)

        var isReady: Bool {
            if case .ready = self { return true }
            return false
        }
    }

    func loadPreview(for project: StudioProject) async {
        guard currentProjectID != project.id || !parseState.isReady else { return }

        parseState = .parsing
        errorMessage = nil
        currentProjectID = project.id

        do {
            let storage = try AsyncStorageService(name: "rn_preview_\(project.id.uuidString.prefix(8)).sqlite")
            let env = RNPreviewEnvironment(projectID: project.id, storage: storage)
            environment = env
            stateManager.attach(environment: env)

            let parsedScreens = RNComponentParser.parseMultipleScreens(from: project)

            guard !parsedScreens.isEmpty else {
                parseState = .failed("No parseable JSX components found in project files.")
                return
            }

            screens = parsedScreens
            await env.cacheParseResult(parsedScreens)

            await stateManager.analyzeAndBind(screens: parsedScreens, projectFiles: project.files)
            updateHookSummary()

            let savedState = await env.loadPreviewState()
            navigationStack = savedState.navigationStack

            if let savedScreenName = savedState.activeScreenName,
               let savedScreen = parsedScreens.first(where: { $0.name == savedScreenName }) {
                activeScreen = savedScreen
            } else {
                activeScreen = resolveEntryScreen(parsedScreens, project: project)
            }

            if let active = activeScreen, !navigationStack.contains(active.name) {
                navigationStack = [active.name]
            }

            await refreshAsyncStorageData()

            lastParsedAt = Date()
            parseState = .ready
            logger.info("Parsed \(parsedScreens.count) screens for \(project.name)")
        } catch {
            parseState = .failed("Preview setup failed: \(error.localizedDescription)")
            logger.error("Preview load failed: \(error.localizedDescription)")
        }
    }

    func reparse(project: StudioProject) async {
        currentProjectID = nil
        await loadPreview(for: project)
    }

    func navigateToScreen(_ screenName: String) async {
        guard let screen = screens.first(where: { $0.name == screenName }) else { return }
        activeScreen = screen
        navigationStack.append(screenName)
        await environment?.setActiveScreen(screenName)
        await environment?.updateNavigationStack(navigationStack)
    }

    func navigateBack() async {
        guard navigationStack.count > 1 else { return }
        navigationStack.removeLast()
        if let prevName = navigationStack.last,
           let prevScreen = screens.first(where: { $0.name == prevName }) {
            activeScreen = prevScreen
            await environment?.setActiveScreen(prevName)
        }
        await environment?.updateNavigationStack(navigationStack)
    }

    func selectScreen(_ screen: RNParsedScreen) async {
        activeScreen = screen
        navigationStack = [screen.name]
        await environment?.setActiveScreen(screen.name)
        await environment?.updateNavigationStack(navigationStack)
    }

    func setAsyncStorageItem(key: String, value: String) async {
        await environment?.setAsyncStorageItem(key, value: value)
        await refreshAsyncStorageData()
    }

    func removeAsyncStorageItem(key: String) async {
        await environment?.removeAsyncStorageItem(key)
        await refreshAsyncStorageData()
    }

    func clearAsyncStorage() async {
        await environment?.clearAsyncStorage()
        await refreshAsyncStorageData()
    }

    func updateAsyncStorageItem(key: String, value: String) async {
        await environment?.setAsyncStorageItem(key, value: value)
        await refreshAsyncStorageData()
    }

    func refreshAsyncStorageData() async {
        guard let env = environment else { return }
        let keys = await env.getAllAsyncStorageKeys()
        asyncStorageKeys = keys.sorted()
        if !keys.isEmpty {
            asyncStorageData = await env.multiGetAsyncStorage(keys)
        } else {
            asyncStorageData = [:]
        }
    }

    func clearAllPreviewData() async {
        await environment?.clearAllPreviewData()
        stateManager.resetAllStates()
        screens = []
        activeScreen = nil
        navigationStack = []
        asyncStorageKeys = []
        asyncStorageData = [:]
        hookSummary = HookSummary()
        parseState = .idle
        currentProjectID = nil
    }

    func resetComponentStates() {
        stateManager.resetAllStates()
    }

    var activeScreenID: String {
        activeScreen?.filePath ?? activeScreen?.name ?? ""
    }

    private func updateHookSummary() {
        var summary = HookSummary()
        for (_, hooks) in stateManager.hookDetections {
            summary.totalHooks += hooks.count
            summary.useStateCount += hooks.filter { $0.hookType == .useState }.count
            summary.asyncStorageCount += hooks.filter { $0.hookType == .useAsyncStorage }.count
        }
        summary.boundStorageKeys = stateManager.asyncStorageBindings.keys.sorted()
        hookSummary = summary
    }

    private func resolveEntryScreen(_ screens: [RNParsedScreen], project: StudioProject) -> RNParsedScreen? {
        if let entryFile = project.entryFile,
           let entryScreen = screens.first(where: { $0.filePath == entryFile }) {
            return entryScreen
        }

        let entryNames = ["App", "Home", "HomeScreen", "Main", "Index"]
        for name in entryNames {
            if let match = screens.first(where: { $0.name == name }) {
                return match
            }
        }

        return screens.first
    }
}
