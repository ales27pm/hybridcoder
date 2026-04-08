import Foundation
import SwiftUI

nonisolated struct RNComponentNode: Identifiable, Sendable {
    let id: UUID
    let type: ComponentType
    var props: [String: PropValue]
    var children: [RNComponentNode]
    var resolvedStyles: [String: String]
    var textContent: String?

    init(
        id: UUID = UUID(),
        type: ComponentType,
        props: [String: PropValue] = [:],
        children: [RNComponentNode] = [],
        resolvedStyles: [String: String] = [:],
        textContent: String? = nil
    ) {
        self.id = id
        self.type = type
        self.props = props
        self.children = children
        self.resolvedStyles = resolvedStyles
        self.textContent = textContent
    }

    nonisolated enum ComponentType: String, Sendable, CaseIterable {
        case view = "View"
        case text = "Text"
        case image = "Image"
        case scrollView = "ScrollView"
        case flatList = "FlatList"
        case touchableOpacity = "TouchableOpacity"
        case pressable = "Pressable"
        case textInput = "TextInput"
        case button = "Button"
        case activityIndicator = "ActivityIndicator"
        case safeAreaView = "SafeAreaView"
        case statusBar = "StatusBar"
        case keyboardAvoidingView = "KeyboardAvoidingView"
        case modal = "Modal"
        case switchComponent = "Switch"
        case sectionList = "SectionList"
        case navigationContainer = "NavigationContainer"
        case stackNavigator = "Stack.Navigator"
        case stackScreen = "Stack.Screen"
        case tabNavigator = "Tab.Navigator"
        case tabScreen = "Tab.Screen"
        case fragment = "Fragment"
        case unknown = "Unknown"

        static func from(_ tag: String) -> ComponentType {
            let cleaned = tag.trimmingCharacters(in: .whitespaces)
            if let match = allCases.first(where: { $0.rawValue == cleaned }) {
                return match
            }
            if cleaned.hasSuffix(".Navigator") { return .stackNavigator }
            if cleaned.hasSuffix(".Screen") { return .stackScreen }
            return .unknown
        }
    }

    nonisolated enum PropValue: Sendable {
        case string(String)
        case number(Double)
        case bool(Bool)
        case styleRef(String)
        case expression(String)
        case array([PropValue])

        var stringValue: String? {
            if case .string(let v) = self { return v }
            if case .expression(let v) = self { return v }
            return nil
        }

        var numberValue: Double? {
            if case .number(let v) = self { return v }
            return nil
        }

        var boolValue: Bool? {
            if case .bool(let v) = self { return v }
            return nil
        }
    }
}

nonisolated struct RNParsedScreen: Identifiable, Sendable {
    let id: UUID
    let name: String
    let filePath: String
    let rootNode: RNComponentNode
    let styleDefinitions: [String: [String: String]]

    init(
        id: UUID = UUID(),
        name: String,
        filePath: String,
        rootNode: RNComponentNode,
        styleDefinitions: [String: [String: String]] = [:]
    ) {
        self.id = id
        self.name = name
        self.filePath = filePath
        self.rootNode = rootNode
        self.styleDefinitions = styleDefinitions
    }
}

nonisolated struct RNPreviewState: Codable, Sendable {
    var projectID: UUID
    var activeScreenName: String?
    var navigationStack: [String]
    var asyncStorageData: [String: String]
    var componentStates: [String: String]
    var lastPreviewedAt: Date

    init(
        projectID: UUID,
        activeScreenName: String? = nil,
        navigationStack: [String] = [],
        asyncStorageData: [String: String] = [:],
        componentStates: [String: String] = [:],
        lastPreviewedAt: Date = Date()
    ) {
        self.projectID = projectID
        self.activeScreenName = activeScreenName
        self.navigationStack = navigationStack
        self.asyncStorageData = asyncStorageData
        self.componentStates = componentStates
        self.lastPreviewedAt = lastPreviewedAt
    }
}
