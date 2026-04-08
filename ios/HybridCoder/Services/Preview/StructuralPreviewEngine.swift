import Foundation

enum StructuralPreviewEngine {
    static func buildSnapshot(from project: StudioProject) -> StructuralSnapshot {
        let fileNames = project.files.map(\.path)

        let entryCandidates = ["App.tsx", "App.js", "App.ts", "index.tsx", "index.ts", "index.js", "app/_layout.tsx", "app/_layout.js"]
        let entryFile = entryCandidates.first { name in fileNames.contains(name) }

        let screenFiles = project.files.filter { file in
            let lower = file.path.lowercased()
            return lower.contains("screen") || lower.contains("page") ||
                   lower.hasPrefix("src/screens/") || lower.hasPrefix("app/") ||
                   lower.hasPrefix("screens/") || lower.hasPrefix("src/pages/")
        }

        let screens = screenFiles.enumerated().map { index, file in
            let screenName = extractScreenName(from: file.path)
            return StructuralSnapshot.ScreenNode(
                id: file.path,
                name: screenName,
                filePath: file.path,
                isEntry: index == 0 && entryFile == nil
            )
        }

        let navigationKind = detectNavigationKind(from: project)
        let componentCount = project.files.filter { isComponentFile($0.path) }.count

        return StructuralSnapshot(
            screens: screens,
            entryFile: entryFile,
            navigationKind: navigationKind,
            componentCount: componentCount,
            fileCount: project.files.count
        )
    }

    static func buildSnapshot(from project: SandboxProject) -> StructuralSnapshot {
        buildSnapshot(from: project.asStudioProject)
    }

    private static func extractScreenName(from filePath: String) -> String {
        let fileName = (filePath as NSString).lastPathComponent
        let name = (fileName as NSString).deletingPathExtension
        return name
            .replacingOccurrences(of: "Screen", with: "")
            .replacingOccurrences(of: "Page", with: "")
    }

    private static func detectNavigationKind(from project: StudioProject) -> NavigationPreset {
        let allContent = project.files.map(\.content).joined(separator: "\n")

        if allContent.contains("createBottomTabNavigator") || allContent.contains("Tab.Navigator") {
            return .tabs
        }
        if allContent.contains("createDrawerNavigator") || allContent.contains("Drawer.Navigator") {
            return .drawer
        }
        if allContent.contains("createNativeStackNavigator") || allContent.contains("Stack.Navigator") {
            return .stack
        }
        if allContent.contains("expo-router") || allContent.contains("app/_layout") {
            return .stack
        }
        return .none
    }

    private static func isComponentFile(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        guard ["tsx", "jsx", "ts", "js"].contains(ext) else { return false }
        let fileName = (name as NSString).lastPathComponent
        guard let first = fileName.first else { return false }
        return first.isUppercase
    }
}
