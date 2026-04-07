import Foundation

enum ExpoProjectDetector {
    struct DetectionResult: Sendable {
        let isExpo: Bool
        let packageName: String?
        let entryFile: String?
        let hasExpoRouter: Bool
        let navigationLibrary: NavigationLibrary?
        let dependencies: [String]

        var projectKind: ProjectKind {
            guard isExpo else { return .importedGeneric }
            return .importedExpo
        }

        var navigationPreset: NavigationPreset {
            guard let nav = navigationLibrary else { return .none }
            switch nav {
            case .expoRouter: return .stack
            case .reactNavigationTabs: return .tabs
            case .reactNavigationStack: return .stack
            case .reactNavigationDrawer: return .drawer
            }
        }
    }

    enum NavigationLibrary: String, Sendable {
        case expoRouter = "expo-router"
        case reactNavigationTabs = "@react-navigation/bottom-tabs"
        case reactNavigationStack = "@react-navigation/native-stack"
        case reactNavigationDrawer = "@react-navigation/drawer"
    }

    static func detect(at url: URL, repoAccess: RepoAccessService) async -> DetectionResult {
        let packageURL = url.appendingPathComponent("package.json")
        let appJSONURL = url.appendingPathComponent("app.json")
        let appConfigJSURL = url.appendingPathComponent("app.config.js")
        let appConfigTSURL = url.appendingPathComponent("app.config.ts")
        let fm = FileManager.default

        var packageName: String?
        var hasExpoDependency = false
        var dependencies: [String] = []
        var navigationLibrary: NavigationLibrary?
        var hasExpoRouter = false

        if let packageData = await repoAccess.readData(at: packageURL),
           let root = try? JSONSerialization.jsonObject(with: packageData) as? [String: Any] {
            packageName = root["name"] as? String

            let depBlocks = ["dependencies", "devDependencies", "peerDependencies"]
                .compactMap { root[$0] as? [String: Any] }

            let allDeps = depBlocks.flatMap(\.keys)
            dependencies = allDeps.sorted()

            hasExpoDependency = allDeps.contains("expo")

            if !hasExpoDependency,
               let scripts = root["scripts"] as? [String: String] {
                hasExpoDependency = scripts.values.contains { $0.localizedCaseInsensitiveContains("expo") }
            }

            hasExpoRouter = allDeps.contains("expo-router")

            if hasExpoRouter {
                navigationLibrary = .expoRouter
            } else if allDeps.contains("@react-navigation/bottom-tabs") {
                navigationLibrary = .reactNavigationTabs
            } else if allDeps.contains("@react-navigation/native-stack") {
                navigationLibrary = .reactNavigationStack
            } else if allDeps.contains("@react-navigation/drawer") {
                navigationLibrary = .reactNavigationDrawer
            }
        }

        let hasExpoConfig = [appJSONURL, appConfigJSURL, appConfigTSURL].contains {
            fm.fileExists(atPath: $0.path(percentEncoded: false))
        }

        let entryCandidates = ["App.tsx", "App.js", "index.ts", "index.tsx", "index.js", "app/_layout.tsx", "app/_layout.js"]
        let entryFile = entryCandidates.first {
            fm.fileExists(atPath: url.appendingPathComponent($0).path(percentEncoded: false))
        }

        let isExpo = hasExpoDependency || hasExpoConfig

        return DetectionResult(
            isExpo: isExpo,
            packageName: packageName,
            entryFile: entryFile,
            hasExpoRouter: hasExpoRouter,
            navigationLibrary: navigationLibrary,
            dependencies: dependencies
        )
    }

    static func buildDependencyProfile(from result: DetectionResult) -> RNDependencyProfile {
        RNDependencyProfile(
            hasNavigation: result.navigationLibrary != nil,
            hasAsyncStorage: result.dependencies.contains("@react-native-async-storage/async-storage"),
            hasExpoRouter: result.hasExpoRouter,
            customDependencies: result.dependencies.filter { dep in
                !["expo", "react", "react-native", "typescript"].contains(where: { dep.hasPrefix($0) })
            }
        )
    }
}
