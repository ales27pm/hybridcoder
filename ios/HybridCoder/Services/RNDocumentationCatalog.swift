import Foundation

enum RNDocumentationCatalog {

    static func allSources() -> [DocumentationSource] {
        var sources: [DocumentationSource] = []
        sources.append(contentsOf: reactNativeCoreSources())
        sources.append(contentsOf: expoSDKSources())
        sources.append(contentsOf: navigationSources())
        sources.append(contentsOf: stateManagementSources())
        sources.append(contentsOf: animationSources())
        sources.append(contentsOf: uiLibrarySources())
        sources.append(contentsOf: formsSources())
        sources.append(contentsOf: networkingSources())
        sources.append(contentsOf: storageSources())
        sources.append(contentsOf: testingSources())
        sources.append(contentsOf: toolingSources())
        sources.append(contentsOf: typeScriptSources())
        return sources
    }

    static func reactNativeCoreSources() -> [DocumentationSource] {
        [
            DocumentationSource(
                name: "React Native Core Components",
                category: .reactNativeCore,
                baseURL: "https://reactnative.dev/docs",
                pages: [
                    .init(path: "components/view.md", title: "View", content: rnViewDoc),
                    .init(path: "components/text.md", title: "Text", content: rnTextDoc),
                    .init(path: "components/image.md", title: "Image", content: rnImageDoc),
                    .init(path: "components/textinput.md", title: "TextInput", content: rnTextInputDoc),
                    .init(path: "components/scrollview.md", title: "ScrollView", content: rnScrollViewDoc),
                    .init(path: "components/flatlist.md", title: "FlatList", content: rnFlatListDoc),
                    .init(path: "components/sectionlist.md", title: "SectionList", content: rnSectionListDoc),
                    .init(path: "components/pressable.md", title: "Pressable", content: rnPressableDoc),
                    .init(path: "components/modal.md", title: "Modal", content: rnModalDoc),
                    .init(path: "components/activityindicator.md", title: "ActivityIndicator", content: rnActivityIndicatorDoc),
                    .init(path: "components/switch.md", title: "Switch", content: rnSwitchDoc),
                    .init(path: "components/statusbar.md", title: "StatusBar", content: rnStatusBarDoc),
                ],
                priority: 100,
                isEnabled: true
            ),
            DocumentationSource(
                name: "React Native APIs",
                category: .reactNativeCore,
                baseURL: "https://reactnative.dev/docs",
                pages: [
                    .init(path: "apis/stylesheet.md", title: "StyleSheet", content: rnStyleSheetDoc),
                    .init(path: "apis/platform.md", title: "Platform", content: rnPlatformDoc),
                    .init(path: "apis/dimensions.md", title: "Dimensions", content: rnDimensionsDoc),
                    .init(path: "apis/appearance.md", title: "Appearance", content: rnAppearanceDoc),
                    .init(path: "apis/keyboard.md", title: "Keyboard", content: rnKeyboardDoc),
                    .init(path: "apis/linking.md", title: "Linking", content: rnLinkingDoc),
                    .init(path: "apis/alert.md", title: "Alert", content: rnAlertDoc),
                    .init(path: "apis/animated.md", title: "Animated", content: rnAnimatedDoc),
                    .init(path: "apis/layoutanimation.md", title: "LayoutAnimation", content: rnLayoutAnimationDoc),
                ],
                priority: 95,
                isEnabled: true
            ),
            DocumentationSource(
                name: "React Hooks",
                category: .reactNativeCore,
                baseURL: "https://react.dev/reference/react",
                pages: [
                    .init(path: "hooks/useState.md", title: "useState", content: reactUseStateDoc),
                    .init(path: "hooks/useEffect.md", title: "useEffect", content: reactUseEffectDoc),
                    .init(path: "hooks/useContext.md", title: "useContext", content: reactUseContextDoc),
                    .init(path: "hooks/useReducer.md", title: "useReducer", content: reactUseReducerDoc),
                    .init(path: "hooks/useCallback.md", title: "useCallback", content: reactUseCallbackDoc),
                    .init(path: "hooks/useMemo.md", title: "useMemo", content: reactUseMemoDoc),
                    .init(path: "hooks/useRef.md", title: "useRef", content: reactUseRefDoc),
                ],
                priority: 98,
                isEnabled: true
            ),
        ]
    }

    static func expoSDKSources() -> [DocumentationSource] {
        [
            DocumentationSource(
                name: "Expo Router",
                category: .expo,
                baseURL: "https://docs.expo.dev/router",
                pages: [
                    .init(path: "introduction.md", title: "Expo Router Introduction", content: expoRouterIntroDoc),
                    .init(path: "create-pages.md", title: "Create Pages", content: expoRouterPagesDoc),
                    .init(path: "navigate.md", title: "Navigate Between Pages", content: expoRouterNavigateDoc),
                    .init(path: "layouts.md", title: "Layouts", content: expoRouterLayoutsDoc),
                    .init(path: "tabs.md", title: "Tabs", content: expoRouterTabsDoc),
                    .init(path: "stack.md", title: "Stack", content: expoRouterStackDoc),
                    .init(path: "drawer.md", title: "Drawer", content: expoRouterDrawerDoc),
                ],
                priority: 90,
                isEnabled: true
            ),
            DocumentationSource(
                name: "Expo SDK Modules",
                category: .expo,
                baseURL: "https://docs.expo.dev/versions/latest",
                pages: [
                    .init(path: "sdk/image.md", title: "expo-image", content: expoImageDoc),
                    .init(path: "sdk/camera.md", title: "expo-camera", content: expoCameraDoc),
                    .init(path: "sdk/location.md", title: "expo-location", content: expoLocationDoc),
                    .init(path: "sdk/notifications.md", title: "expo-notifications", content: expoNotificationsDoc),
                    .init(path: "sdk/file-system.md", title: "expo-file-system", content: expoFileSystemDoc),
                    .init(path: "sdk/secure-store.md", title: "expo-secure-store", content: expoSecureStoreDoc),
                    .init(path: "sdk/haptics.md", title: "expo-haptics", content: expoHapticsDoc),
                    .init(path: "sdk/av.md", title: "expo-av", content: expoAVDoc),
                    .init(path: "sdk/constants.md", title: "expo-constants", content: expoConstantsDoc),
                    .init(path: "sdk/font.md", title: "expo-font", content: expoFontDoc),
                    .init(path: "sdk/splash-screen.md", title: "expo-splash-screen", content: expoSplashScreenDoc),
                    .init(path: "sdk/linear-gradient.md", title: "expo-linear-gradient", content: expoLinearGradientDoc),
                    .init(path: "sdk/blur.md", title: "expo-blur", content: expoBlurDoc),
                    .init(path: "sdk/clipboard.md", title: "expo-clipboard", content: expoClipboardDoc),
                    .init(path: "sdk/web-browser.md", title: "expo-web-browser", content: expoWebBrowserDoc),
                ],
                priority: 88,
                isEnabled: true
            ),
        ]
    }

    static func navigationSources() -> [DocumentationSource] {
        [
            DocumentationSource(
                name: "React Navigation v7",
                category: .navigation,
                baseURL: "https://reactnavigation.org/docs/7.x",
                pages: [
                    .init(path: "getting-started.md", title: "Getting Started", content: reactNavGettingStartedDoc),
                    .init(path: "native-stack.md", title: "Native Stack Navigator", content: reactNavNativeStackDoc),
                    .init(path: "bottom-tabs.md", title: "Bottom Tab Navigator", content: reactNavBottomTabsDoc),
                    .init(path: "drawer.md", title: "Drawer Navigator", content: reactNavDrawerDoc),
                    .init(path: "navigation-prop.md", title: "Navigation Prop", content: reactNavPropDoc),
                    .init(path: "route-prop.md", title: "Route Prop", content: reactNavRouteDoc),
                    .init(path: "typescript.md", title: "TypeScript", content: reactNavTypeScriptDoc),
                    .init(path: "deep-linking.md", title: "Deep Linking", content: reactNavDeepLinkingDoc),
                    .init(path: "screen-options.md", title: "Screen Options", content: reactNavScreenOptionsDoc),
                ],
                priority: 85,
                isEnabled: true
            ),
        ]
    }

    static func stateManagementSources() -> [DocumentationSource] {
        [
            DocumentationSource(
                name: "Zustand",
                category: .stateManagement,
                baseURL: "https://docs.pmnd.rs/zustand",
                pages: [
                    .init(path: "getting-started.md", title: "Zustand Getting Started", content: zustandDoc),
                ],
                priority: 75,
                isEnabled: true
            ),
            DocumentationSource(
                name: "TanStack React Query",
                category: .stateManagement,
                baseURL: "https://tanstack.com/query/latest/docs",
                pages: [
                    .init(path: "overview.md", title: "React Query Overview", content: reactQueryDoc),
                ],
                priority: 75,
                isEnabled: true
            ),
        ]
    }

    static func animationSources() -> [DocumentationSource] {
        [
            DocumentationSource(
                name: "React Native Reanimated",
                category: .animation,
                baseURL: "https://docs.swmansion.com/react-native-reanimated",
                pages: [
                    .init(path: "fundamentals.md", title: "Reanimated Fundamentals", content: reanimatedDoc),
                ],
                priority: 70,
                isEnabled: true
            ),
            DocumentationSource(
                name: "React Native Gesture Handler",
                category: .animation,
                baseURL: "https://docs.swmansion.com/react-native-gesture-handler",
                pages: [
                    .init(path: "fundamentals.md", title: "Gesture Handler Fundamentals", content: gestureHandlerDoc),
                ],
                priority: 70,
                isEnabled: true
            ),
        ]
    }

    static func uiLibrarySources() -> [DocumentationSource] {
        [
            DocumentationSource(
                name: "Flash List",
                category: .uiLibrary,
                baseURL: "https://shopify.github.io/flash-list",
                pages: [
                    .init(path: "fundamentals.md", title: "FlashList Fundamentals", content: flashListDoc),
                ],
                priority: 60,
                isEnabled: true
            ),
            DocumentationSource(
                name: "React Native Bottom Sheet",
                category: .uiLibrary,
                baseURL: "https://gorhom.github.io/react-native-bottom-sheet",
                pages: [
                    .init(path: "usage.md", title: "Bottom Sheet Usage", content: bottomSheetDoc),
                ],
                priority: 60,
                isEnabled: true
            ),
            DocumentationSource(
                name: "Safe Area Context",
                category: .uiLibrary,
                baseURL: "https://github.com/th3rdwave/react-native-safe-area-context",
                pages: [
                    .init(path: "usage.md", title: "Safe Area Context", content: safeAreaContextDoc),
                ],
                priority: 65,
                isEnabled: true
            ),
        ]
    }

    static func formsSources() -> [DocumentationSource] {
        [
            DocumentationSource(
                name: "React Hook Form",
                category: .forms,
                baseURL: "https://react-hook-form.com",
                pages: [
                    .init(path: "get-started.md", title: "React Hook Form", content: reactHookFormDoc),
                ],
                priority: 55,
                isEnabled: true
            ),
            DocumentationSource(
                name: "Zod Validation",
                category: .forms,
                baseURL: "https://zod.dev",
                pages: [
                    .init(path: "introduction.md", title: "Zod Validation", content: zodDoc),
                ],
                priority: 55,
                isEnabled: true
            ),
        ]
    }

    static func networkingSources() -> [DocumentationSource] {
        [
            DocumentationSource(
                name: "Fetch API & Networking",
                category: .networking,
                baseURL: "https://reactnative.dev/docs/network",
                pages: [
                    .init(path: "networking.md", title: "React Native Networking", content: rnNetworkingDoc),
                ],
                priority: 70,
                isEnabled: true
            ),
        ]
    }

    static func storageSources() -> [DocumentationSource] {
        [
            DocumentationSource(
                name: "AsyncStorage",
                category: .storage,
                baseURL: "https://react-native-async-storage.github.io/async-storage",
                pages: [
                    .init(path: "usage.md", title: "AsyncStorage Usage", content: asyncStorageDoc),
                ],
                priority: 75,
                isEnabled: true
            ),
        ]
    }

    static func testingSources() -> [DocumentationSource] {
        [
            DocumentationSource(
                name: "React Native Testing Library",
                category: .testing,
                baseURL: "https://callstack.github.io/react-native-testing-library",
                pages: [
                    .init(path: "getting-started.md", title: "RNTL Getting Started", content: rntlDoc),
                ],
                priority: 45,
                isEnabled: true
            ),
        ]
    }

    static func toolingSources() -> [DocumentationSource] {
        [
            DocumentationSource(
                name: "Expo CLI & Config",
                category: .tooling,
                baseURL: "https://docs.expo.dev",
                pages: [
                    .init(path: "workflow/configuration.md", title: "Expo Configuration", content: expoConfigDoc),
                    .init(path: "workflow/development.md", title: "Expo Development", content: expoDevelopmentDoc),
                ],
                priority: 50,
                isEnabled: true
            ),
        ]
    }

    static func typeScriptSources() -> [DocumentationSource] {
        [
            DocumentationSource(
                name: "TypeScript with React Native",
                category: .typescript,
                baseURL: "https://reactnative.dev/docs/typescript",
                pages: [
                    .init(path: "guide.md", title: "TypeScript Guide", content: tsReactNativeDoc),
                ],
                priority: 65,
                isEnabled: true
            ),
        ]
    }
}
