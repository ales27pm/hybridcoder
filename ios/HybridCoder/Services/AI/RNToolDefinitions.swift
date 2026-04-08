import Foundation

nonisolated enum RNToolDefinitions: Sendable {

    static func toolGuidance(for profile: RNDependencyProfile?) -> String {
        var sections: [String] = []

        sections.append("""

        Available React Native tools and capabilities:
        - read_file: Read source files (.tsx, .ts, .js, .json, .css) from the workspace
        - search_code: Semantic search for components, hooks, styles, navigation, and API patterns
        - list_files: List project files, filter by directory (src/screens/, app/, src/hooks/) or extension (.tsx, .ts)

        When to use tools:
        - Use read_file to inspect a component's props, hooks, or style definitions before modifying it
        - Use search_code to find where a hook is used, how navigation is wired, or where state is managed
        - Use list_files to understand project structure, find screens, or discover existing components
        """)

        if let deps = profile {
            if deps.hasExpoRouter {
                sections.append("""
                Expo Router project detected:
                - Routes are defined by file structure in app/ directory
                - Use list_files with filter "app/" to see all routes
                - _layout.tsx files define navigation layout (Tabs, Stack, Drawer)
                - Dynamic routes use [param].tsx naming
                - Use read_file on app/_layout.tsx to understand navigation structure
                """)
            }

            if deps.hasNavigation {
                sections.append("""
                React Navigation project detected:
                - Navigation is configured imperatively in App.tsx or a navigation/ directory
                - Use search_code for "createNativeStackNavigator" or "createBottomTabNavigator" to find navigator setup
                - Use read_file on App.tsx to understand the navigation tree
                - Screen components receive navigation and route props
                """)
            }

            if deps.hasAsyncStorage {
                sections.append("""
                AsyncStorage available:
                - Use search_code for "AsyncStorage" to find existing persistence patterns
                - Always wrap AsyncStorage calls in try/catch
                - Use JSON.stringify/JSON.parse for complex values
                - Consider creating a typed storage wrapper in services/ or utils/
                """)
            }

            if !deps.customDependencies.isEmpty {
                let reanimated = deps.customDependencies.contains("react-native-reanimated")
                let gestureHandler = deps.customDependencies.contains("react-native-gesture-handler")
                let reactQuery = deps.customDependencies.contains { $0.contains("react-query") || $0.contains("tanstack") }
                let zustand = deps.customDependencies.contains("zustand")

                if reanimated {
                    sections.append("""
                    react-native-reanimated available:
                    - Use useSharedValue, useAnimatedStyle, withSpring, withTiming for animations
                    - Prefer Reanimated over Animated from react-native for performance
                    - Use worklets for running animations on the UI thread
                    """)
                }

                if gestureHandler {
                    sections.append("""
                    react-native-gesture-handler available:
                    - Use Gesture.Pan(), Gesture.Tap(), Gesture.Pinch() for gesture handling
                    - Wrap app in GestureHandlerRootView
                    - Combine with reanimated for gesture-driven animations
                    """)
                }

                if reactQuery {
                    sections.append("""
                    React Query / TanStack Query available:
                    - Use useQuery for data fetching with caching
                    - Use useMutation for write operations
                    - Wrap app in QueryClientProvider
                    - Use queryClient.invalidateQueries for cache invalidation
                    """)
                }

                if zustand {
                    sections.append("""
                    Zustand available:
                    - Use create() to define stores
                    - Access state with useStore hook
                    - Use persist middleware for AsyncStorage integration
                    - Split stores by domain (useAuthStore, useCartStore, etc.)
                    """)
                }
            }
        }

        return sections.joined(separator: "\n")
    }

    static let expoRouterGuidance = """
    <expo_router_guidance>
    Expo Router file-based routing rules:
    - app/_layout.tsx: Root layout, defines top-level navigation (Tabs, Stack, Drawer)
    - app/index.tsx: Home screen (maps to "/" route)
    - app/[param].tsx: Dynamic route parameter
    - app/(group)/: Route groups for shared layouts without affecting URL
    - app/(tabs)/_layout.tsx: Tab navigator layout
    - app/+not-found.tsx: 404 fallback screen

    Navigation API:
    - import { router } from 'expo-router' for imperative navigation
    - router.push('/details/123') to navigate
    - router.replace('/home') to replace current screen
    - router.back() to go back
    - <Link href="/profile"> for declarative navigation
    - useLocalSearchParams<{ id: string }>() for route params
    - useSegments() for active route segments
    - usePathname() for current path

    Layout patterns:
    - <Stack> for stack navigation in _layout.tsx
    - <Tabs> for bottom tab navigation
    - <Drawer> for drawer navigation
    - Nest layouts for complex navigation hierarchies
    </expo_router_guidance>
    """

    static let reactNavigationGuidance = """
    <react_navigation_guidance>
    React Navigation v7 rules:
    - Type all navigators with ParamList types
    - createNativeStackNavigator<ParamList>() for stack flows
    - createBottomTabNavigator<ParamList>() for tab layouts
    - NavigationContainer wraps the entire navigator tree

    Type-safe navigation:
    ```
    type RootStackParamList = {
      Home: undefined;
      Details: { id: string; title: string };
    };

    type Props = NativeStackScreenProps<RootStackParamList, 'Details'>;

    function DetailsScreen({ route, navigation }: Props) {
      const { id, title } = route.params;
    }
    ```

    Navigation patterns:
    - navigation.navigate('ScreenName', { params }) for navigation
    - navigation.goBack() to go back
    - navigation.setOptions({}) for dynamic screen options
    - useNavigation<NativeStackNavigationProp<ParamList>>() for hook-based navigation
    - useFocusEffect() for screen focus side effects
    - useIsFocused() to check if screen is focused
    </react_navigation_guidance>
    """

    static let asyncStorageGuidance = """
    <async_storage_guidance>
    AsyncStorage patterns:
    - Always wrap in try/catch — storage operations can fail
    - Use JSON.stringify for objects, JSON.parse for retrieval
    - Create a typed wrapper for type-safe access
    - Use multiGet/multiSet for batch operations
    - Clear specific keys, not all storage
    - Consider expo-secure-store for sensitive data (tokens, passwords)

    Recommended wrapper pattern:
    ```
    const storage = {
      get: async <T>(key: string): Promise<T | null> => {
        try {
          const raw = await AsyncStorage.getItem(key);
          return raw ? JSON.parse(raw) : null;
        } catch { return null; }
      },
      set: async <T>(key: string, value: T) => {
        try { await AsyncStorage.setItem(key, JSON.stringify(value)); }
        catch (e) { console.error('Storage error:', e); }
      },
    };
    ```
    </async_storage_guidance>
    """

    static let componentScaffoldTemplate = """
    <component_scaffold>
    Standard React Native component structure:

    import React from 'react';
    import { View, Text, StyleSheet } from 'react-native';

    interface ComponentNameProps {
      title: string;
      onAction?: () => void;
    }

    export function ComponentName({ title, onAction }: ComponentNameProps) {
      return (
        <View style={styles.container}>
          <Text style={styles.title}>{title}</Text>
        </View>
      );
    }

    const styles = StyleSheet.create({
      container: {
        // layout styles
      },
      title: {
        // text styles
      },
    });
    </component_scaffold>
    """

    static let screenScaffoldTemplate = """
    <screen_scaffold>
    Standard React Native screen structure:

    import React, { useState, useEffect } from 'react';
    import { View, Text, FlatList, ActivityIndicator, StyleSheet } from 'react-native';
    import { useSafeAreaInsets } from 'react-native-safe-area-context';

    interface Item {
      id: string;
      // fields
    }

    export default function ScreenNameScreen() {
      const insets = useSafeAreaInsets();
      const [items, setItems] = useState<Item[]>([]);
      const [loading, setLoading] = useState(true);
      const [error, setError] = useState<string | null>(null);

      useEffect(() => {
        loadData();
      }, []);

      const loadData = async () => {
        try {
          setLoading(true);
          // fetch data
          setItems(data);
        } catch (e) {
          setError(e instanceof Error ? e.message : 'Something went wrong');
        } finally {
          setLoading(false);
        }
      };

      if (loading) return <ActivityIndicator style={styles.center} />;
      if (error) return <Text style={styles.error}>{error}</Text>;

      return (
        <View style={[styles.container, { paddingTop: insets.top }]}>
          <FlatList
            data={items}
            keyExtractor={item => item.id}
            renderItem={({ item }) => (
              <View style={styles.card}>
                <Text style={styles.cardTitle}>{item.id}</Text>
              </View>
            )}
            ListEmptyComponent={<Text style={styles.empty}>No items yet</Text>}
          />
        </View>
      );
    }

    const styles = StyleSheet.create({
      container: { flex: 1, backgroundColor: '#0f0f23' },
      center: { flex: 1, justifyContent: 'center', alignItems: 'center' },
      error: { color: '#ff4444', textAlign: 'center', marginTop: 40 },
      empty: { color: '#666', textAlign: 'center', marginTop: 40 },
      card: { backgroundColor: '#1a1a3e', padding: 16, borderRadius: 12, marginHorizontal: 16, marginBottom: 8 },
      cardTitle: { color: '#fff', fontSize: 16, fontWeight: '600' },
    });
    </screen_scaffold>
    """

    static let hookScaffoldTemplate = """
    <hook_scaffold>
    Standard React Native custom hook structure:

    import { useState, useEffect, useCallback } from 'react';

    interface UseHookNameOptions {
      // config options
    }

    interface UseHookNameReturn {
      data: DataType | null;
      loading: boolean;
      error: string | null;
      refresh: () => Promise<void>;
    }

    export function useHookName(options?: UseHookNameOptions): UseHookNameReturn {
      const [data, setData] = useState<DataType | null>(null);
      const [loading, setLoading] = useState(true);
      const [error, setError] = useState<string | null>(null);

      const refresh = useCallback(async () => {
        try {
          setLoading(true);
          setError(null);
          // fetch/compute data
          setData(result);
        } catch (e) {
          setError(e instanceof Error ? e.message : 'Unknown error');
        } finally {
          setLoading(false);
        }
      }, [/* deps */]);

      useEffect(() => {
        refresh();
      }, [refresh]);

      return { data, loading, error, refresh };
    }
    </hook_scaffold>
    """
}
