import Foundation

nonisolated enum RNCodeConventions: Sendable {

    static let coreConventions = """
    <react_native_conventions>
    Framework: React Native with Expo (managed workflow)
    Language: TypeScript by default, JavaScript for legacy projects

    Component patterns:
    - Functional components with hooks exclusively — no class components
    - Use React.FC<Props> or typed function signatures for prop types
    - Prefer named exports for components, default export only for screens
    - One component per file, colocate styles at bottom with StyleSheet.create
    - Destructure props in function signature: ({ title, onPress }: Props) =>

    Hooks:
    - useState for local state, useReducer for complex state
    - useEffect with proper dependency arrays — never omit deps
    - useMemo/useCallback only when passing to memoized children or expensive computations
    - Custom hooks in hooks/ directory with use* prefix
    - useRef for imperative handles and animation values

    State management:
    - React Context + useReducer for global state (auth, theme, settings)
    - Zustand for complex shared state (prefer over Redux)
    - React Query / TanStack Query for server state and caching
    - AsyncStorage for persistence — always wrap in try/catch

    Styling:
    - StyleSheet.create at file bottom — never inline styles in JSX
    - Use constants for colors, spacing, typography in a theme file
    - Platform.select or Platform.OS for platform-specific styles
    - Dimensions.get('window') or useWindowDimensions for responsive layouts
    - Safe area handling: useSafeAreaInsets from react-native-safe-area-context

    Navigation (React Navigation v7+):
    - Type-safe navigation with ParamList types
    - createNativeStackNavigator for stack flows
    - createBottomTabNavigator for tab layouts
    - Deep linking configuration in NavigationContainer
    - Screen options in navigator, not on individual screens

    Navigation (Expo Router):
    - File-based routing in app/ directory
    - _layout.tsx for layout routes (Tabs, Stack, Drawer)
    - Dynamic routes with [param].tsx
    - Typed routes with expo-router useLocalSearchParams<>()
    - Link component for declarative navigation

    File structure:
    - src/screens/ or app/ for screen components
    - src/components/ for reusable components
    - src/hooks/ for custom hooks
    - src/context/ for React Context providers
    - src/services/ or src/api/ for API calls
    - src/utils/ for pure utility functions
    - src/types/ for TypeScript interfaces/types
    - src/constants/ for theme, config, enums

    Error handling:
    - ErrorBoundary component at app root
    - try/catch in async operations with user-friendly error states
    - Loading/error/empty states for every data-fetching screen
    - Proper error typing with custom error classes

    Performance:
    - FlatList for long lists, never ScrollView with map
    - React.memo for expensive pure components
    - Avoid anonymous functions in renderItem
    - useCallback for event handlers passed as props
    - Image caching with expo-image or react-native-fast-image
    - Avoid unnecessary re-renders: split context providers

    Testing patterns:
    - Jest + React Native Testing Library
    - Test user interactions, not implementation details
    - Mock navigation with @react-navigation/native mock
    - Snapshot tests for UI regression
    </react_native_conventions>
    """

    static let libraryReference = """
    <react_native_libraries>
    Core Expo SDK:
    - expo-router: file-based routing
    - expo-image: performant image component with caching
    - expo-font: custom font loading
    - expo-splash-screen: splash screen control
    - expo-status-bar: status bar styling
    - expo-constants: app constants and config
    - expo-secure-store: encrypted key-value storage
    - expo-file-system: file system access
    - expo-camera: camera access
    - expo-location: geolocation
    - expo-notifications: push notifications
    - expo-haptics: haptic feedback
    - expo-linear-gradient: gradient backgrounds
    - expo-blur: blur effects
    - expo-av: audio/video playback
    - expo-clipboard: clipboard access
    - expo-sharing: share sheet
    - expo-web-browser: in-app browser
    - expo-linking: deep linking
    - expo-device: device info

    Navigation:
    - @react-navigation/native: core navigation
    - @react-navigation/native-stack: native stack navigator
    - @react-navigation/bottom-tabs: bottom tab navigator
    - @react-navigation/drawer: drawer navigator
    - @react-navigation/material-top-tabs: top tab navigator

    State & Data:
    - @tanstack/react-query: server state management
    - zustand: lightweight state management
    - @react-native-async-storage/async-storage: local persistence
    - react-native-mmkv: fast key-value storage

    UI & Animation:
    - react-native-reanimated: performant animations
    - react-native-gesture-handler: gesture handling
    - @shopify/flash-list: high-performance lists
    - react-native-safe-area-context: safe area insets
    - react-native-screens: native screen primitives
    - react-native-svg: SVG rendering
    - @expo/vector-icons: icon sets (Ionicons, MaterialIcons, etc.)
    - react-native-maps: map views
    - react-native-bottom-sheet: bottom sheet component
    - react-native-toast-message: toast notifications
    - nativewind: Tailwind CSS for React Native

    Forms & Input:
    - react-hook-form: form state management
    - zod: schema validation
    - react-native-keyboard-aware-scroll-view: keyboard handling

    Networking:
    - axios: HTTP client (alternative to fetch)
    - socket.io-client: WebSocket communication

    Auth:
    - expo-auth-session: OAuth flows
    - @react-native-firebase/auth: Firebase auth
    - @supabase/supabase-js: Supabase client
    </react_native_libraries>
    """

    static let codePatterns = """
    <react_native_patterns>
    Typed navigation:
    ```typescript
    type RootStackParamList = {
      Home: undefined;
      Details: { id: string };
      Profile: { userId: string };
    };

    const Stack = createNativeStackNavigator<RootStackParamList>();
    ```

    Custom hook pattern:
    ```typescript
    function useApi<T>(url: string) {
      const [data, setData] = useState<T | null>(null);
      const [loading, setLoading] = useState(true);
      const [error, setError] = useState<string | null>(null);

      useEffect(() => {
        fetch(url)
          .then(res => res.json())
          .then(setData)
          .catch(e => setError(e.message))
          .finally(() => setLoading(false));
      }, [url]);

      return { data, loading, error };
    }
    ```

    Context + reducer pattern:
    ```typescript
    interface State { user: User | null; loading: boolean; }
    type Action = { type: 'SET_USER'; payload: User } | { type: 'LOGOUT' };

    const reducer = (state: State, action: Action): State => {
      switch (action.type) {
        case 'SET_USER': return { ...state, user: action.payload, loading: false };
        case 'LOGOUT': return { ...state, user: null };
      }
    };

    const AuthContext = createContext<{ state: State; dispatch: Dispatch<Action> } | undefined>(undefined);
    ```

    AsyncStorage wrapper:
    ```typescript
    const storage = {
      get: async <T>(key: string): Promise<T | null> => {
        try {
          const value = await AsyncStorage.getItem(key);
          return value ? JSON.parse(value) : null;
        } catch { return null; }
      },
      set: async <T>(key: string, value: T): Promise<void> => {
        try { await AsyncStorage.setItem(key, JSON.stringify(value)); }
        catch (e) { console.error('Storage set error:', e); }
      },
      remove: async (key: string): Promise<void> => {
        try { await AsyncStorage.removeItem(key); }
        catch (e) { console.error('Storage remove error:', e); }
      },
    };
    ```

    FlatList with typed renderItem:
    ```typescript
    const renderItem = useCallback(({ item }: { item: ItemType }) => (
      <ItemCard item={item} onPress={() => navigate('Details', { id: item.id })} />
    ), [navigate]);

    <FlatList
      data={items}
      keyExtractor={item => item.id}
      renderItem={renderItem}
      ItemSeparatorComponent={() => <View style={styles.separator} />}
      ListEmptyComponent={<EmptyState message="No items yet" />}
      contentContainerStyle={items.length === 0 ? styles.emptyContainer : undefined}
    />
    ```

    Platform-specific code:
    ```typescript
    const styles = StyleSheet.create({
      shadow: Platform.select({
        ios: { shadowColor: '#000', shadowOffset: { width: 0, height: 2 }, shadowOpacity: 0.1, shadowRadius: 4 },
        android: { elevation: 4 },
      }),
    });
    ```
    </react_native_patterns>
    """

    static let antiPatterns = """
    <react_native_anti_patterns>
    NEVER do these in React Native code:
    - Do NOT use ScrollView + .map() for dynamic lists — use FlatList
    - Do NOT use inline styles — use StyleSheet.create
    - Do NOT use class components — use functional components with hooks
    - Do NOT import from 'react-native-web' — this is a mobile app
    - Do NOT use window.* or document.* — no DOM in React Native
    - Do NOT use CSS class names or className prop — use style prop
    - Do NOT use <div>, <span>, <p> — use View, Text
    - Do NOT use onClick — use onPress
    - Do NOT use px/em/rem units — use plain numbers (dp)
    - Do NOT use percentage strings for flex layout — use flex numbers
    - Do NOT mutate state directly — always use setter functions
    - Do NOT use require() for images in production — use expo-image or URI
    - Do NOT put async logic in useEffect without cleanup
    - Do NOT use index as key in FlatList when items can reorder
    - Do NOT wrap FlatList in ScrollView — FlatList IS a ScrollView
    - Do NOT use Animated from react-native for complex animations — use react-native-reanimated
    - Do NOT use Alert.alert for complex UI — use modal components
    - Do NOT use setTimeout for navigation — use navigation.addListener
    - Do NOT store sensitive data in AsyncStorage — use expo-secure-store
    - Do NOT skip error boundaries — wrap screens in ErrorBoundary
    </react_native_anti_patterns>
    """

    static func conventionsBlock(includePatterns: Bool = false, includeLibraries: Bool = false) -> String {
        var parts = [coreConventions]
        if includeLibraries {
            parts.append(libraryReference)
        }
        if includePatterns {
            parts.append(codePatterns)
        }
        parts.append(antiPatterns)
        return parts.joined(separator: "\n\n")
    }
}
