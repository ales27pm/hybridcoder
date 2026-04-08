import Foundation

extension RNDocumentationCatalog {

    // MARK: - React Native Core Components

    static let rnViewDoc = """
    # View
    The most fundamental component for building a UI. View is a container that supports layout with Flexbox, style, touch handling, and accessibility controls. View maps directly to the native view equivalent on whatever platform React Native is running on (UIView on iOS, android.view on Android).

    ## Props
    - style: ViewStyle - Flexbox layout, transforms, opacity, backgroundColor, border
    - onLayout: (event: LayoutChangeEvent) => void - Invoked on mount and layout changes
    - accessible: boolean - When true, indicates the view is an accessibility element
    - accessibilityLabel: string - Overrides the text that's read by the screen reader
    - hitSlop: Insets - Defines how far a touch event can start away from the view
    - pointerEvents: 'auto' | 'none' | 'box-none' | 'box-only' - Controls whether the View can be the target of touch events
    - collapsable: boolean - Views used only to layout children may be removed from native hierarchy for optimization

    ## Flexbox Layout
    View uses Flexbox for layout. Key properties:
    - flex: number - How much of remaining space should be used (flex: 1 fills available space)
    - flexDirection: 'column' | 'row' | 'column-reverse' | 'row-reverse' (default: 'column')
    - justifyContent: 'flex-start' | 'center' | 'flex-end' | 'space-between' | 'space-around' | 'space-evenly'
    - alignItems: 'flex-start' | 'center' | 'flex-end' | 'stretch' | 'baseline'
    - flexWrap: 'wrap' | 'nowrap'
    - gap, rowGap, columnGap: number - Spacing between children
    - padding, margin: number or object with top/right/bottom/left/horizontal/vertical
    - position: 'relative' | 'absolute'

    ## Example
    ```tsx
    <View style={{ flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: '#f5f5f5' }}>
      <View style={{ width: 100, height: 100, backgroundColor: 'blue', borderRadius: 12 }} />
    </View>
    ```
    """

    static let rnTextDoc = """
    # Text
    A component for displaying text. Text supports nesting, styling, and touch handling. All text nodes must be wrapped in a <Text> component — you cannot have a text node directly under <View>.

    ## Props
    - style: TextStyle - fontFamily, fontSize, fontWeight, color, lineHeight, textAlign, textDecorationLine, letterSpacing
    - numberOfLines: number - Truncate text to this many lines (ellipsis at end)
    - ellipsizeMode: 'head' | 'middle' | 'tail' | 'clip'
    - selectable: boolean - Allow user to select text for copying
    - onPress: () => void - Called on press
    - onLongPress: () => void - Called on long press
    - adjustsFontSizeToFit: boolean - Auto-shrink font to fit container (iOS)

    ## Nesting
    ```tsx
    <Text style={{ fontSize: 16 }}>
      I am bold <Text style={{ fontWeight: 'bold' }}>and red</Text>
    </Text>
    ```

    ## Text Style Properties
    - color: string
    - fontFamily: string
    - fontSize: number (default 14)
    - fontStyle: 'normal' | 'italic'
    - fontWeight: 'normal' | 'bold' | '100'-'900'
    - lineHeight: number
    - textAlign: 'auto' | 'left' | 'right' | 'center' | 'justify'
    - textDecorationLine: 'none' | 'underline' | 'line-through' | 'underline line-through'
    - textTransform: 'none' | 'capitalize' | 'uppercase' | 'lowercase'
    """

    static let rnImageDoc = """
    # Image
    A component for displaying images from local assets, network URLs, or base64 data.

    ## Props
    - source: ImageSourcePropType - { uri: string } for remote, require('./path') for local
    - style: ImageStyle - width, height, resizeMode, borderRadius, tintColor
    - resizeMode: 'cover' | 'contain' | 'stretch' | 'repeat' | 'center'
    - onLoad: () => void - Called when image loads successfully
    - onError: (error) => void - Called when image fails to load
    - blurRadius: number - Blur radius of the blur filter
    - defaultSource: ImageSourcePropType - Static image to display while loading (iOS)
    - fadeDuration: number - Fade animation duration in ms (Android, default 300)

    ## Usage
    ```tsx
    // Remote image
    <Image source={{ uri: 'https://example.com/photo.jpg' }} style={{ width: 200, height: 200 }} />

    // Local image
    <Image source={require('./assets/logo.png')} style={{ width: 100, height: 100 }} />

    // With resizeMode
    <Image source={{ uri: imageUrl }} style={{ width: '100%', height: 200 }} resizeMode="cover" />
    ```

    Note: For better performance, use expo-image instead of React Native's built-in Image component. expo-image provides automatic caching, placeholder support, transitions, and blurhash placeholders.
    """

    static let rnTextInputDoc = """
    # TextInput
    A component for inputting text via keyboard. Supports auto-correction, auto-capitalization, placeholder text, and different keyboard types.

    ## Props
    - value: string - The value to show for the text input
    - onChangeText: (text: string) => void - Called when text changes
    - placeholder: string - Placeholder text when empty
    - placeholderTextColor: string - Color of placeholder text
    - keyboardType: 'default' | 'numeric' | 'email-address' | 'phone-pad' | 'decimal-pad' | 'url'
    - returnKeyType: 'done' | 'go' | 'next' | 'search' | 'send'
    - secureTextEntry: boolean - Obscure text for passwords
    - multiline: boolean - Allow multiple lines
    - numberOfLines: number - Set number of lines for multiline
    - maxLength: number - Max character count
    - autoCapitalize: 'none' | 'sentences' | 'words' | 'characters'
    - autoCorrect: boolean
    - autoComplete: various string options
    - editable: boolean - If false, text is not editable
    - onSubmitEditing: () => void - Called when submit button pressed
    - onFocus / onBlur: () => void

    ## Example
    ```tsx
    const [text, setText] = useState('');
    <TextInput
      style={{ height: 40, borderColor: 'gray', borderWidth: 1, padding: 10, borderRadius: 8 }}
      onChangeText={setText}
      value={text}
      placeholder="Enter text here"
    />
    ```
    """

    static let rnScrollViewDoc = """
    # ScrollView
    A generic scrolling container that can contain multiple components and views. Use ScrollView for small amounts of content. For long lists, use FlatList instead.

    ## Props
    - horizontal: boolean - Scroll horizontally instead of vertically
    - showsVerticalScrollIndicator: boolean
    - showsHorizontalScrollIndicator: boolean
    - contentContainerStyle: ViewStyle - Style of the inner content container
    - keyboardDismissMode: 'none' | 'on-drag' | 'interactive'
    - keyboardShouldPersistTaps: 'always' | 'never' | 'handled'
    - refreshControl: React element (RefreshControl)
    - scrollEnabled: boolean
    - pagingEnabled: boolean - Stops on multiples of scroll view's size when scrolling
    - onScroll: (event) => void
    - scrollEventThrottle: number - How often scroll events fire (ms)
    - stickyHeaderIndices: number[] - Indices of children that stick to top

    ## Important: Do NOT use ScrollView with .map() for dynamic lists. Use FlatList instead.

    ## Example
    ```tsx
    <ScrollView contentContainerStyle={{ padding: 16 }}>
      <Text>Item 1</Text>
      <Text>Item 2</Text>
      <Text>Item 3</Text>
    </ScrollView>
    ```
    """

    static let rnFlatListDoc = """
    # FlatList
    A performant interface for rendering flat lists. Only renders items currently visible on screen. Use FlatList for long scrollable lists of data.

    ## Props
    - data: T[] - Array of items to render
    - renderItem: ({ item, index, separators }) => React.ReactElement
    - keyExtractor: (item: T, index: number) => string - Unique key for each item
    - ListHeaderComponent: React component - Rendered at top
    - ListFooterComponent: React component - Rendered at bottom
    - ListEmptyComponent: React component - Rendered when data is empty
    - ItemSeparatorComponent: React component - Rendered between items
    - numColumns: number - Multiple columns (masonry-like)
    - horizontal: boolean - Render horizontally
    - initialNumToRender: number - Items to render initially (default 10)
    - onEndReached: () => void - Called when scroll reaches end
    - onEndReachedThreshold: number - How far from end to trigger onEndReached (0-1)
    - refreshing: boolean - Show refresh indicator
    - onRefresh: () => void - Pull-to-refresh callback
    - getItemLayout: (data, index) => { length, offset, index } - Skip measurement for performance
    - contentContainerStyle: ViewStyle
    - extraData: any - Re-render when this value changes

    ## Best Practices
    - Always provide keyExtractor with unique string keys (NOT array index)
    - Use useCallback for renderItem to prevent unnecessary re-renders
    - Never wrap FlatList in ScrollView — FlatList IS a ScrollView
    - Use getItemLayout for fixed-height items for better performance
    - Use React.memo on renderItem components

    ## Example
    ```tsx
    const renderItem = useCallback(({ item }: { item: User }) => (
      <View style={styles.card}>
        <Text style={styles.name}>{item.name}</Text>
      </View>
    ), []);

    <FlatList
      data={users}
      keyExtractor={item => item.id}
      renderItem={renderItem}
      ListEmptyComponent={<Text>No users found</Text>}
      contentContainerStyle={users.length === 0 ? styles.empty : undefined}
    />
    ```
    """

    static let rnSectionListDoc = """
    # SectionList
    A performant interface for rendering sectioned lists. Like FlatList but with section headers.

    ## Props
    - sections: Array<{ title: string, data: T[] }> - Array of section objects
    - renderItem: ({ item, index, section }) => React.ReactElement
    - renderSectionHeader: ({ section }) => React.ReactElement
    - renderSectionFooter: ({ section }) => React.ReactElement
    - keyExtractor: (item, index) => string
    - stickySectionHeadersEnabled: boolean (default true on iOS)
    - All FlatList props also apply

    ## Example
    ```tsx
    <SectionList
      sections={[
        { title: 'Fruits', data: ['Apple', 'Banana'] },
        { title: 'Vegetables', data: ['Carrot', 'Potato'] },
      ]}
      keyExtractor={(item, index) => item + index}
      renderItem={({ item }) => <Text style={styles.item}>{item}</Text>}
      renderSectionHeader={({ section: { title } }) => (
        <Text style={styles.header}>{title}</Text>
      )}
    />
    ```
    """

    static let rnPressableDoc = """
    # Pressable
    A core component wrapper that detects press interactions. Replaces TouchableOpacity/TouchableHighlight.

    ## Props
    - onPress: () => void
    - onPressIn: () => void
    - onPressOut: () => void
    - onLongPress: () => void
    - delayLongPress: number (default 500ms)
    - disabled: boolean
    - hitSlop: number | Insets
    - pressRetentionOffset: Insets
    - style: ViewStyle | ((state: PressableStateCallbackType) => ViewStyle)
    - android_ripple: { color, borderless, radius, foreground }

    ## Style Function
    The style prop can be a function that receives { pressed } for dynamic styling:
    ```tsx
    <Pressable
      onPress={() => console.log('Pressed!')}
      style={({ pressed }) => [
        styles.button,
        { opacity: pressed ? 0.7 : 1 }
      ]}
    >
      <Text>Press Me</Text>
    </Pressable>
    ```
    """

    static let rnModalDoc = """
    # Modal
    A basic way to present content above an enclosing view.

    ## Props
    - visible: boolean - Whether the modal is visible
    - animationType: 'none' | 'slide' | 'fade'
    - transparent: boolean - Whether the modal fills the entire view
    - presentationStyle: 'fullScreen' | 'pageSheet' | 'formSheet' | 'overFullScreen' (iOS)
    - onRequestClose: () => void - Called when user taps back button (Android) or swipes down (iOS 13+)
    - onShow: () => void - Called after modal is shown
    - statusBarTranslucent: boolean (Android)

    ## Example
    ```tsx
    <Modal visible={isVisible} animationType="slide" transparent onRequestClose={() => setIsVisible(false)}>
      <View style={styles.overlay}>
        <View style={styles.modalContent}>
          <Text>Modal Content</Text>
          <Button title="Close" onPress={() => setIsVisible(false)} />
        </View>
      </View>
    </Modal>
    ```
    """

    static let rnActivityIndicatorDoc = """
    # ActivityIndicator
    Displays a circular loading indicator.

    ## Props
    - animating: boolean (default true)
    - color: string (default system default)
    - size: 'small' | 'large' | number (Android)

    ## Example
    ```tsx
    {loading && <ActivityIndicator size="large" color="#0000ff" />}
    ```
    """

    static let rnSwitchDoc = """
    # Switch
    A boolean input toggle.

    ## Props
    - value: boolean
    - onValueChange: (value: boolean) => void
    - trackColor: { false: string, true: string }
    - thumbColor: string
    - ios_backgroundColor: string
    - disabled: boolean

    ## Example
    ```tsx
    <Switch value={isEnabled} onValueChange={setIsEnabled} trackColor={{ false: '#767577', true: '#81b0ff' }} thumbColor={isEnabled ? '#f5dd4b' : '#f4f3f4'} />
    ```
    """

    static let rnStatusBarDoc = """
    # StatusBar
    Component to control the app status bar. Use expo-status-bar for Expo projects.

    ## Props
    - barStyle: 'default' | 'light-content' | 'dark-content'
    - hidden: boolean
    - backgroundColor: string (Android)
    - translucent: boolean (Android)
    - animated: boolean
    """

    // MARK: - React Native APIs

    static let rnStyleSheetDoc = """
    # StyleSheet
    An abstraction similar to CSS StyleSheets. Creates optimized style objects.

    ## API
    - StyleSheet.create(styles) - Creates a StyleSheet reference from an object of style properties
    - StyleSheet.flatten(style) - Flattens an array of style objects into one
    - StyleSheet.absoluteFill - A convenient shortcut for { position: 'absolute', left: 0, right: 0, top: 0, bottom: 0 }
    - StyleSheet.hairlineWidth - The thinnest line the platform can render

    ## Best Practices
    - Always use StyleSheet.create instead of inline objects
    - Define styles at the bottom of the file, outside the component
    - Use semantic names for style keys
    - Group related styles together

    ## Example
    ```tsx
    const styles = StyleSheet.create({
      container: { flex: 1, backgroundColor: '#fff', padding: 16 },
      title: { fontSize: 24, fontWeight: 'bold', color: '#333', marginBottom: 8 },
      card: { backgroundColor: '#f9f9f9', borderRadius: 12, padding: 16, marginBottom: 12,
        ...Platform.select({
          ios: { shadowColor: '#000', shadowOffset: { width: 0, height: 2 }, shadowOpacity: 0.1, shadowRadius: 4 },
          android: { elevation: 4 },
        })
      },
    });
    ```
    """

    static let rnPlatformDoc = """
    # Platform
    Module for detecting the platform the app is running on and applying platform-specific code.

    ## API
    - Platform.OS: 'ios' | 'android' | 'web'
    - Platform.Version: number (iOS version) or number (Android API level)
    - Platform.select({ ios: value, android: value, default: value }) - Returns platform-specific value
    - Platform.isPad: boolean (iOS only)
    - Platform.isTV: boolean

    ## Platform-specific files
    Create files with platform extensions: MyComponent.ios.tsx, MyComponent.android.tsx
    Import as: import MyComponent from './MyComponent' — React Native auto-resolves the correct file.
    """

    static let rnDimensionsDoc = """
    # Dimensions
    API for getting device screen dimensions. Prefer useWindowDimensions hook for reactive updates.

    ## API
    - Dimensions.get('window') - Returns { width, height, scale, fontScale }
    - Dimensions.get('screen') - Returns full screen dimensions including status bar
    - useWindowDimensions() - Hook that updates when dimensions change (rotation, split screen)

    ## Example
    ```tsx
    import { useWindowDimensions } from 'react-native';
    const { width, height } = useWindowDimensions();
    const isTablet = width >= 768;
    ```
    """

    static let rnAppearanceDoc = """
    # Appearance
    Module for detecting the user's preferred color scheme.

    ## API
    - Appearance.getColorScheme() - Returns 'light' | 'dark' | null
    - useColorScheme() - Hook that returns current color scheme and updates on change

    ## Example
    ```tsx
    const colorScheme = useColorScheme();
    const isDark = colorScheme === 'dark';
    const backgroundColor = isDark ? '#000' : '#fff';
    ```
    """

    static let rnKeyboardDoc = """
    # Keyboard
    API for controlling keyboard behavior.

    ## API
    - Keyboard.dismiss() - Dismiss the keyboard
    - Keyboard.addListener('keyboardDidShow', callback) - Listen for keyboard events
    - Keyboard.addListener('keyboardDidHide', callback)
    - KeyboardAvoidingView - Component that adjusts its height/position based on keyboard

    ## KeyboardAvoidingView
    ```tsx
    <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : 'height'} style={{ flex: 1 }}>
      <ScrollView keyboardShouldPersistTaps="handled">
        <TextInput ... />
      </ScrollView>
    </KeyboardAvoidingView>
    ```
    """

    static let rnLinkingDoc = """
    # Linking
    API for interacting with incoming and outgoing links.

    ## API
    - Linking.openURL(url) - Open a URL in the default browser or app
    - Linking.canOpenURL(url) - Check if a URL can be opened
    - Linking.getInitialURL() - Get the URL that opened the app
    - Linking.addEventListener('url', callback) - Listen for incoming URLs

    ## Example
    ```tsx
    await Linking.openURL('https://example.com');
    await Linking.openURL('tel:+1234567890');
    await Linking.openURL('mailto:user@example.com');
    ```
    """

    static let rnAlertDoc = """
    # Alert
    Launches an alert dialog with the specified title, message, and buttons.

    ## API
    - Alert.alert(title, message?, buttons?, options?)

    ## Example
    ```tsx
    Alert.alert('Confirm', 'Are you sure?', [
      { text: 'Cancel', style: 'cancel' },
      { text: 'OK', onPress: () => handleConfirm() },
    ]);
    ```
    """

    static let rnAnimatedDoc = """
    # Animated
    Library for creating animations. For complex animations, use react-native-reanimated instead.

    ## Core API
    - Animated.Value - Represents a single animated value
    - Animated.ValueXY - Represents a 2D animated value
    - Animated.timing(value, config) - Animate a value over time
    - Animated.spring(value, config) - Spring physics animation
    - Animated.decay(value, config) - Start with initial velocity and gradually slow
    - Animated.sequence(animations) - Run animations in sequence
    - Animated.parallel(animations) - Run animations simultaneously
    - Animated.stagger(delay, animations) - Run animations in parallel with staggered starts
    - Animated.loop(animation) - Loop an animation

    ## Animated Components
    Animated.View, Animated.Text, Animated.Image, Animated.ScrollView, Animated.FlatList

    ## Example
    ```tsx
    const fadeAnim = useRef(new Animated.Value(0)).current;
    useEffect(() => {
      Animated.timing(fadeAnim, { toValue: 1, duration: 1000, useNativeDriver: true }).start();
    }, []);
    <Animated.View style={{ opacity: fadeAnim }}>...</Animated.View>
    ```

    Note: For performance-critical animations, use react-native-reanimated which runs animations on the UI thread.
    """

    static let rnLayoutAnimationDoc = """
    # LayoutAnimation
    Automatically animates views to their new positions when the next layout happens.

    ## API
    - LayoutAnimation.configureNext(config) - Schedule animation for next layout
    - LayoutAnimation.spring() - Use spring animation preset
    - LayoutAnimation.linear() - Use linear animation preset
    - LayoutAnimation.easeInEaseOut() - Use easeInEaseOut preset

    ## Example
    ```tsx
    const toggleExpanded = () => {
      LayoutAnimation.configureNext(LayoutAnimation.Presets.easeInEaseOut);
      setExpanded(!expanded);
    };
    ```

    Note: On Android, you need to enable LayoutAnimation: UIManager.setLayoutAnimationEnabledExperimental?.(true)
    """

    // MARK: - React Hooks

    static let reactUseStateDoc = """
    # useState
    Hook that adds state to functional components. Returns a stateful value and a function to update it.

    ## Signature
    const [state, setState] = useState<T>(initialState: T | (() => T))

    ## Rules
    - Call at the top level of your component — never inside conditions, loops, or nested functions
    - setState triggers a re-render with the new state value
    - setState can accept a function for updates based on previous state: setState(prev => prev + 1)
    - State updates are batched — multiple setState calls in one event handler result in a single re-render
    - State is preserved between re-renders

    ## Patterns
    ```tsx
    // Simple state
    const [count, setCount] = useState(0);

    // Object state
    const [form, setForm] = useState({ name: '', email: '' });
    setForm(prev => ({ ...prev, name: 'John' }));

    // Array state
    const [items, setItems] = useState<string[]>([]);
    setItems(prev => [...prev, 'new item']);

    // Lazy initialization (expensive computation)
    const [data, setData] = useState(() => computeExpensiveValue());
    ```
    """

    static let reactUseEffectDoc = """
    # useEffect
    Hook for performing side effects in functional components. Runs after render.

    ## Signature
    useEffect(setup: () => (() => void) | void, dependencies?: any[])

    ## Rules
    - Runs after every render if no dependency array is provided
    - Runs only once (on mount) if dependency array is empty []
    - Runs when any dependency changes if dependencies are specified
    - Return a cleanup function to clean up subscriptions, timers, etc.
    - The cleanup runs before the effect runs again and on unmount

    ## Common Patterns
    ```tsx
    // Run once on mount
    useEffect(() => {
      fetchData();
    }, []);

    // Run when dependency changes
    useEffect(() => {
      const results = filterItems(searchQuery);
      setFiltered(results);
    }, [searchQuery]);

    // With cleanup
    useEffect(() => {
      const subscription = eventEmitter.subscribe(handler);
      return () => subscription.unsubscribe();
    }, []);

    // Async pattern (useEffect callback cannot be async directly)
    useEffect(() => {
      let cancelled = false;
      async function load() {
        const data = await fetchData();
        if (!cancelled) setData(data);
      }
      load();
      return () => { cancelled = true; };
    }, []);
    ```
    """

    static let reactUseContextDoc = """
    # useContext
    Hook to read and subscribe to context from a component.

    ## Signature
    const value = useContext(SomeContext)

    ## Pattern
    ```tsx
    // Create context
    const ThemeContext = createContext<'light' | 'dark'>('light');

    // Provider
    <ThemeContext.Provider value={theme}>
      <App />
    </ThemeContext.Provider>

    // Consumer
    function ThemedButton() {
      const theme = useContext(ThemeContext);
      return <View style={{ backgroundColor: theme === 'dark' ? '#333' : '#fff' }} />;
    }
    ```

    ## Auth Context Example
    ```tsx
    interface AuthContextType {
      user: User | null;
      signIn: (email: string, password: string) => Promise<void>;
      signOut: () => Promise<void>;
    }
    const AuthContext = createContext<AuthContextType | undefined>(undefined);

    function useAuth() {
      const context = useContext(AuthContext);
      if (!context) throw new Error('useAuth must be used within AuthProvider');
      return context;
    }
    ```
    """

    static let reactUseReducerDoc = """
    # useReducer
    Hook for managing complex state logic. Alternative to useState when state has multiple sub-values or next state depends on previous state.

    ## Signature
    const [state, dispatch] = useReducer(reducer, initialState, init?)

    ## Example
    ```tsx
    type State = { count: number; step: number };
    type Action = { type: 'increment' } | { type: 'decrement' } | { type: 'setStep'; payload: number };

    function reducer(state: State, action: Action): State {
      switch (action.type) {
        case 'increment': return { ...state, count: state.count + state.step };
        case 'decrement': return { ...state, count: state.count - state.step };
        case 'setStep': return { ...state, step: action.payload };
      }
    }

    const [state, dispatch] = useReducer(reducer, { count: 0, step: 1 });
    dispatch({ type: 'increment' });
    ```
    """

    static let reactUseCallbackDoc = """
    # useCallback
    Hook that caches a function definition between re-renders. Use when passing callbacks to optimized child components (React.memo) or as dependencies in other hooks.

    ## Signature
    const memoizedFn = useCallback(fn, dependencies)

    ## When to use
    - Passing a callback to a child wrapped in React.memo
    - The callback is a dependency of useEffect or useMemo
    - The function is used in a FlatList renderItem

    ## Example
    ```tsx
    const handlePress = useCallback((id: string) => {
      navigation.navigate('Details', { id });
    }, [navigation]);

    const renderItem = useCallback(({ item }: { item: Item }) => (
      <ItemCard item={item} onPress={() => handlePress(item.id)} />
    ), [handlePress]);
    ```
    """

    static let reactUseMemoDoc = """
    # useMemo
    Hook that caches the result of a calculation between re-renders. Use for expensive computations.

    ## Signature
    const memoizedValue = useMemo(() => computeExpensiveValue(a, b), [a, b])

    ## When to use
    - Filtering/sorting large lists
    - Complex calculations that don't need to rerun every render
    - Creating objects/arrays that are used as dependencies in other hooks

    ## Example
    ```tsx
    const filteredItems = useMemo(() =>
      items.filter(item => item.name.toLowerCase().includes(search.toLowerCase())),
      [items, search]
    );
    ```

    ## When NOT to use
    - Simple calculations (overhead of useMemo > the computation itself)
    - Values not used as dependencies elsewhere
    """

    static let reactUseRefDoc = """
    # useRef
    Hook that creates a mutable ref object that persists across renders. Commonly used for DOM/native element references and storing mutable values that don't trigger re-renders.

    ## Signature
    const ref = useRef<T>(initialValue)

    ## Use Cases
    ```tsx
    // Reference to a component
    const inputRef = useRef<TextInput>(null);
    <TextInput ref={inputRef} />
    inputRef.current?.focus();

    // Store mutable value without re-rendering
    const intervalRef = useRef<NodeJS.Timeout | null>(null);
    useEffect(() => {
      intervalRef.current = setInterval(() => tick(), 1000);
      return () => { if (intervalRef.current) clearInterval(intervalRef.current); };
    }, []);

    // Track previous value
    const prevCountRef = useRef(count);
    useEffect(() => { prevCountRef.current = count; });
    ```
    """

    // MARK: - Expo Router

    static let expoRouterIntroDoc = """
    # Expo Router
    File-based routing for React Native and web apps. Routes are defined by the file structure in the app/ directory.

    ## Key Concepts
    - Every file in app/ becomes a route
    - _layout.tsx files define navigation layouts (Stack, Tabs, Drawer)
    - Dynamic routes: [param].tsx, [...catchAll].tsx
    - Route groups: (group)/ for shared layouts without URL impact
    - +not-found.tsx for 404 pages

    ## Installation
    ```bash
    npx expo install expo-router expo-linking expo-constants expo-status-bar
    ```

    ## app.json config
    ```json
    { "expo": { "scheme": "myapp", "web": { "bundler": "metro" } } }
    ```
    """

    static let expoRouterPagesDoc = """
    # Create Pages
    Files in app/ directory automatically become routes.

    ## File Structure → Routes
    - app/index.tsx → / (home)
    - app/about.tsx → /about
    - app/user/[id].tsx → /user/123
    - app/blog/[...slug].tsx → /blog/any/nested/path
    - app/(tabs)/_layout.tsx → Tab navigation layout
    - app/+not-found.tsx → 404 fallback

    ## Example Page
    ```tsx
    import { Text, View, StyleSheet } from 'react-native';

    export default function HomeScreen() {
      return (
        <View style={styles.container}>
          <Text style={styles.title}>Welcome</Text>
        </View>
      );
    }

    const styles = StyleSheet.create({
      container: { flex: 1, justifyContent: 'center', alignItems: 'center' },
      title: { fontSize: 24, fontWeight: 'bold' },
    });
    ```
    """

    static let expoRouterNavigateDoc = """
    # Navigate Between Pages
    Expo Router provides multiple ways to navigate between routes.

    ## Link Component (Declarative)
    ```tsx
    import { Link } from 'expo-router';
    <Link href="/about">Go to About</Link>
    <Link href={{ pathname: '/user/[id]', params: { id: '123' } }}>User Profile</Link>
    ```

    ## router API (Imperative)
    ```tsx
    import { router } from 'expo-router';
    router.push('/about');
    router.replace('/home');
    router.back();
    router.canGoBack();
    router.dismiss(); // Close modal
    router.dismissAll(); // Close all modals
    ```

    ## Route Parameters
    ```tsx
    import { useLocalSearchParams, useGlobalSearchParams } from 'expo-router';
    const { id } = useLocalSearchParams<{ id: string }>();
    ```

    ## Hooks
    - usePathname() - Current route path
    - useSegments() - Array of route segments
    - useRouter() - Router object with push, replace, back, etc.
    """

    static let expoRouterLayoutsDoc = """
    # Layouts
    _layout.tsx files define how screens are arranged within a directory.

    ## Stack Layout
    ```tsx
    import { Stack } from 'expo-router';
    export default function Layout() {
      return (
        <Stack screenOptions={{ headerStyle: { backgroundColor: '#f5f5f5' }, headerTintColor: '#333' }}>
          <Stack.Screen name="index" options={{ title: 'Home' }} />
          <Stack.Screen name="details" options={{ title: 'Details' }} />
        </Stack>
      );
    }
    ```

    ## Tab Layout
    ```tsx
    import { Tabs } from 'expo-router';
    import { Ionicons } from '@expo/vector-icons';
    export default function Layout() {
      return (
        <Tabs screenOptions={{ tabBarActiveTintColor: '#007AFF' }}>
          <Tabs.Screen name="index" options={{ title: 'Home', tabBarIcon: ({ color }) => <Ionicons name="home" size={24} color={color} /> }} />
          <Tabs.Screen name="profile" options={{ title: 'Profile', tabBarIcon: ({ color }) => <Ionicons name="person" size={24} color={color} /> }} />
        </Tabs>
      );
    }
    ```
    """

    static let expoRouterTabsDoc = """
    # Tabs
    Bottom tab navigation using Expo Router.

    ## Setup
    Create app/(tabs)/_layout.tsx:
    ```tsx
    import { Tabs } from 'expo-router';
    export default function TabsLayout() {
      return (
        <Tabs>
          <Tabs.Screen name="index" options={{ title: 'Home' }} />
          <Tabs.Screen name="explore" options={{ title: 'Explore' }} />
          <Tabs.Screen name="profile" options={{ title: 'Profile' }} />
        </Tabs>
      );
    }
    ```

    ## Tab Options
    - title, tabBarLabel, tabBarIcon, tabBarBadge, tabBarBadgeStyle
    - headerShown, tabBarShowLabel, tabBarActiveTintColor, tabBarInactiveTintColor
    - tabBarStyle, tabBarLabelStyle, tabBarItemStyle
    """

    static let expoRouterStackDoc = """
    # Stack
    Stack navigation with push/pop transitions.

    ## Screen Options
    - title: string
    - headerShown: boolean
    - headerTitle: string | React component
    - headerLeft / headerRight: React component
    - headerStyle, headerTintColor, headerTitleStyle
    - presentation: 'card' | 'modal' | 'transparentModal' | 'containedModal' | 'containedTransparentModal' | 'fullScreenModal' | 'formSheet'
    - animation: 'default' | 'fade' | 'flip' | 'slide_from_right' | 'slide_from_left' | 'slide_from_bottom' | 'none'
    - gestureEnabled: boolean
    """

    static let expoRouterDrawerDoc = """
    # Drawer
    Side drawer navigation using Expo Router.

    ## Setup
    ```bash
    npx expo install @react-navigation/drawer react-native-gesture-handler react-native-reanimated
    ```

    ## Layout
    ```tsx
    import { Drawer } from 'expo-router/drawer';
    export default function Layout() {
      return (
        <Drawer>
          <Drawer.Screen name="index" options={{ drawerLabel: 'Home', title: 'Home' }} />
          <Drawer.Screen name="settings" options={{ drawerLabel: 'Settings', title: 'Settings' }} />
        </Drawer>
      );
    }
    ```
    """

    // MARK: - Expo SDK Modules

    static let expoImageDoc = """
    # expo-image
    A performant image component with caching, placeholder support, and transitions. Recommended over React Native's built-in Image.

    ## Installation
    npx expo install expo-image

    ## Usage
    ```tsx
    import { Image } from 'expo-image';
    <Image source={{ uri: 'https://example.com/image.jpg' }} style={{ width: 200, height: 200 }} contentFit="cover" placeholder={{ blurhash: 'LKO2?U%2Tw=w]~RBVZRi};RPxuwH' }} transition={200} />
    ```

    ## Props
    - source: string | ImageSource | ImageSource[]
    - contentFit: 'cover' | 'contain' | 'fill' | 'none' | 'scale-down'
    - placeholder: string | ImageSource (blurhash or thumbhash)
    - transition: number | ImageTransition (ms)
    - cachePolicy: 'none' | 'disk' | 'memory' | 'memory-disk'
    - recyclingKey: string
    - onLoad, onError, onLoadStart, onLoadEnd
    """

    static let expoCameraDoc = """
    # expo-camera
    Camera access for taking photos and recording video.

    ## Installation
    npx expo install expo-camera

    ## Permissions
    ```tsx
    const [permission, requestPermission] = useCameraPermissions();
    if (!permission?.granted) { requestPermission(); }
    ```

    ## Usage
    ```tsx
    import { CameraView, useCameraPermissions } from 'expo-camera';
    <CameraView style={{ flex: 1 }} facing="back" ref={cameraRef}>
      <Button title="Take Photo" onPress={async () => { const photo = await cameraRef.current?.takePictureAsync(); }} />
    </CameraView>
    ```
    """

    static let expoLocationDoc = """
    # expo-location
    Access device geolocation.

    ## Installation
    npx expo install expo-location

    ## Usage
    ```tsx
    import * as Location from 'expo-location';
    const { status } = await Location.requestForegroundPermissionsAsync();
    if (status === 'granted') {
      const location = await Location.getCurrentPositionAsync({});
      console.log(location.coords.latitude, location.coords.longitude);
    }
    ```

    ## API
    - getCurrentPositionAsync(options) - Get current position
    - watchPositionAsync(options, callback) - Watch position changes
    - getLastKnownPositionAsync() - Last known position (no GPS request)
    - reverseGeocodeAsync(location) - Convert coordinates to address
    - geocodeAsync(address) - Convert address to coordinates
    """

    static let expoNotificationsDoc = """
    # expo-notifications
    Push and local notifications.

    ## Installation
    npx expo install expo-notifications expo-device expo-constants

    ## Local Notification
    ```tsx
    import * as Notifications from 'expo-notifications';
    await Notifications.scheduleNotificationAsync({
      content: { title: 'Reminder', body: 'Don\\'t forget!' },
      trigger: { seconds: 60 },
    });
    ```

    ## Push Token
    ```tsx
    const token = (await Notifications.getExpoPushTokenAsync({ projectId: Constants.expoConfig?.extra?.eas?.projectId })).data;
    ```
    """

    static let expoFileSystemDoc = """
    # expo-file-system
    File system access for reading, writing, and managing files.

    ## API
    ```tsx
    import * as FileSystem from 'expo-file-system';
    const content = await FileSystem.readAsStringAsync(FileSystem.documentDirectory + 'file.txt');
    await FileSystem.writeAsStringAsync(FileSystem.documentDirectory + 'file.txt', 'Hello World');
    const info = await FileSystem.getInfoAsync(uri);
    await FileSystem.deleteAsync(uri);
    await FileSystem.downloadAsync(remoteUri, FileSystem.documentDirectory + 'file.pdf');
    ```
    """

    static let expoSecureStoreDoc = """
    # expo-secure-store
    Encrypted key-value storage for sensitive data (tokens, passwords). Uses Keychain on iOS, EncryptedSharedPreferences on Android.

    ## Installation
    npx expo install expo-secure-store

    ## API
    ```tsx
    import * as SecureStore from 'expo-secure-store';
    await SecureStore.setItemAsync('token', 'abc123');
    const token = await SecureStore.getItemAsync('token');
    await SecureStore.deleteItemAsync('token');
    ```

    Note: Values are limited to 2048 bytes on iOS. Use for auth tokens and secrets only — use AsyncStorage for general persistence.
    """

    static let expoHapticsDoc = """
    # expo-haptics
    Haptic feedback for touch interactions.

    ## API
    ```tsx
    import * as Haptics from 'expo-haptics';
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light); // Light, Medium, Heavy
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success); // Success, Warning, Error
    Haptics.selectionAsync(); // Selection feedback
    ```
    """

    static let expoAVDoc = """
    # expo-av
    Audio and video playback and recording.

    ## Audio Playback
    ```tsx
    import { Audio } from 'expo-av';
    const { sound } = await Audio.Sound.createAsync(require('./assets/audio.mp3'));
    await sound.playAsync();
    await sound.pauseAsync();
    await sound.unloadAsync(); // Always unload when done
    ```

    ## Video
    ```tsx
    import { Video } from 'expo-av';
    <Video source={{ uri: videoUrl }} style={{ width: 300, height: 200 }} useNativeControls resizeMode="contain" />
    ```
    """

    static let expoConstantsDoc = """
    # expo-constants
    System information and app configuration values.

    ## API
    ```tsx
    import Constants from 'expo-constants';
    Constants.expoConfig?.name; // App name from app.json
    Constants.expoConfig?.version; // App version
    Constants.expoConfig?.extra; // Extra config from app.config.js
    Constants.platform?.ios?.buildNumber;
    Constants.platform?.android?.versionCode;
    ```
    """

    static let expoFontDoc = """
    # expo-font
    Custom font loading.

    ## Usage
    ```tsx
    import { useFonts } from 'expo-font';
    import * as SplashScreen from 'expo-splash-screen';

    SplashScreen.preventAutoHideAsync();

    export default function App() {
      const [loaded] = useFonts({ 'Inter-Bold': require('./assets/fonts/Inter-Bold.ttf') });
      useEffect(() => { if (loaded) SplashScreen.hideAsync(); }, [loaded]);
      if (!loaded) return null;
      return <Text style={{ fontFamily: 'Inter-Bold' }}>Hello</Text>;
    }
    ```
    """

    static let expoSplashScreenDoc = """
    # expo-splash-screen
    Control the splash screen visibility.

    ## API
    ```tsx
    import * as SplashScreen from 'expo-splash-screen';
    SplashScreen.preventAutoHideAsync(); // Keep splash visible
    SplashScreen.hideAsync(); // Hide splash when ready
    ```
    """

    static let expoLinearGradientDoc = """
    # expo-linear-gradient
    Linear gradient backgrounds.

    ## Usage
    ```tsx
    import { LinearGradient } from 'expo-linear-gradient';
    <LinearGradient colors={['#4c669f', '#3b5998', '#192f6a']} style={{ flex: 1, padding: 16 }}>
      <Text style={{ color: '#fff' }}>Gradient Background</Text>
    </LinearGradient>
    ```
    """

    static let expoBlurDoc = """
    # expo-blur
    Blur view effects.

    ## Usage
    ```tsx
    import { BlurView } from 'expo-blur';
    <BlurView intensity={50} tint="dark" style={StyleSheet.absoluteFill}>
      <Text style={{ color: '#fff' }}>Blurred Background</Text>
    </BlurView>
    ```
    """

    static let expoClipboardDoc = """
    # expo-clipboard
    Read and write to the system clipboard.

    ## API
    ```tsx
    import * as Clipboard from 'expo-clipboard';
    await Clipboard.setStringAsync('Hello World');
    const text = await Clipboard.getStringAsync();
    const hasString = await Clipboard.hasStringAsync();
    ```
    """

    static let expoWebBrowserDoc = """
    # expo-web-browser
    Open URLs in an in-app browser (SFSafariViewController on iOS, Chrome Custom Tabs on Android).

    ## API
    ```tsx
    import * as WebBrowser from 'expo-web-browser';
    await WebBrowser.openBrowserAsync('https://example.com');
    ```
    """

    // MARK: - React Navigation v7

    static let reactNavGettingStartedDoc = """
    # React Navigation v7 - Getting Started
    React Navigation is the most popular navigation library for React Native.

    ## Installation
    ```bash
    npm install @react-navigation/native @react-navigation/native-stack
    npx expo install react-native-screens react-native-safe-area-context
    ```

    ## Setup
    ```tsx
    import { NavigationContainer } from '@react-navigation/native';
    import { createNativeStackNavigator } from '@react-navigation/native-stack';

    const Stack = createNativeStackNavigator();

    export default function App() {
      return (
        <NavigationContainer>
          <Stack.Navigator>
            <Stack.Screen name="Home" component={HomeScreen} />
            <Stack.Screen name="Details" component={DetailsScreen} />
          </Stack.Navigator>
        </NavigationContainer>
      );
    }
    ```
    """

    static let reactNavNativeStackDoc = """
    # Native Stack Navigator
    Uses native navigation primitives (UINavigationController on iOS, Fragment on Android) for the best performance.

    ## Options
    - title, headerShown, headerTitle, headerLeft, headerRight
    - headerStyle, headerTintColor, headerTitleStyle
    - presentation: 'card' | 'modal' | 'transparentModal' | 'containedModal' | 'containedTransparentModal' | 'fullScreenModal' | 'formSheet'
    - animation: 'default' | 'fade' | 'flip' | 'simple_push' | 'slide_from_right' | 'slide_from_left' | 'slide_from_bottom' | 'none'
    - gestureEnabled: boolean
    - headerLargeTitle: boolean (iOS)
    - headerSearchBarOptions: object (iOS)
    """

    static let reactNavBottomTabsDoc = """
    # Bottom Tab Navigator
    Tab bar at the bottom of the screen.

    ## Installation
    npm install @react-navigation/bottom-tabs

    ## Usage
    ```tsx
    import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
    const Tab = createBottomTabNavigator();

    <Tab.Navigator screenOptions={({ route }) => ({
      tabBarIcon: ({ focused, color, size }) => {
        const iconName = route.name === 'Home' ? 'home' : 'settings';
        return <Ionicons name={iconName} size={size} color={color} />;
      },
      tabBarActiveTintColor: '#007AFF',
    })}>
      <Tab.Screen name="Home" component={HomeScreen} />
      <Tab.Screen name="Settings" component={SettingsScreen} />
    </Tab.Navigator>
    ```
    """

    static let reactNavDrawerDoc = """
    # Drawer Navigator
    Side drawer navigation.

    ## Installation
    ```bash
    npm install @react-navigation/drawer
    npx expo install react-native-gesture-handler react-native-reanimated
    ```

    ## Usage
    ```tsx
    import { createDrawerNavigator } from '@react-navigation/drawer';
    const Drawer = createDrawerNavigator();

    <Drawer.Navigator>
      <Drawer.Screen name="Home" component={HomeScreen} />
      <Drawer.Screen name="Profile" component={ProfileScreen} />
    </Drawer.Navigator>
    ```
    """

    static let reactNavPropDoc = """
    # Navigation Prop
    The navigation object provides methods for navigating between screens.

    ## Methods
    - navigation.navigate(name, params?) - Navigate to a screen
    - navigation.goBack() - Go back to previous screen
    - navigation.reset(state) - Reset navigation state
    - navigation.setOptions(options) - Update screen options dynamically
    - navigation.setParams(params) - Update route params
    - navigation.dispatch(action) - Dispatch a navigation action
    - navigation.addListener(event, callback) - Listen to navigation events
    - navigation.getParent(id?) - Get parent navigator
    - navigation.isFocused() - Check if screen is focused

    ## Hooks
    - useNavigation() - Access navigation object in any component
    - useFocusEffect(callback) - Run effect when screen is focused
    - useIsFocused() - Returns boolean indicating focus state
    """

    static let reactNavRouteDoc = """
    # Route Prop
    The route object contains information about the current route.

    ## Properties
    - route.key: string - Unique key for the route
    - route.name: string - Name of the route
    - route.params: object - Parameters passed to the route
    - route.path: string - Path from deep link

    ## Hook
    ```tsx
    import { useRoute } from '@react-navigation/native';
    const route = useRoute();
    const { id, title } = route.params as { id: string; title: string };
    ```
    """

    static let reactNavTypeScriptDoc = """
    # TypeScript with React Navigation
    Type-safe navigation requires defining ParamList types.

    ## Setup
    ```tsx
    type RootStackParamList = {
      Home: undefined;
      Details: { id: string; title: string };
      Profile: { userId: string };
    };

    // Typed navigator
    const Stack = createNativeStackNavigator<RootStackParamList>();

    // Typed screen props
    type DetailsScreenProps = NativeStackScreenProps<RootStackParamList, 'Details'>;
    function DetailsScreen({ route, navigation }: DetailsScreenProps) {
      const { id, title } = route.params;
    }

    // Typed hook
    const navigation = useNavigation<NativeStackNavigationProp<RootStackParamList>>();
    navigation.navigate('Details', { id: '123', title: 'Hello' });
    ```

    ## Global type declaration (for useNavigation without explicit type)
    ```tsx
    declare global {
      namespace ReactNavigation {
        interface RootParamList extends RootStackParamList {}
      }
    }
    ```
    """

    static let reactNavDeepLinkingDoc = """
    # Deep Linking
    Configure deep linking to navigate to specific screens from URLs.

    ## Configuration
    ```tsx
    const linking = {
      prefixes: ['myapp://', 'https://myapp.com'],
      config: {
        screens: {
          Home: '',
          Details: 'details/:id',
          Profile: 'profile/:userId',
        },
      },
    };

    <NavigationContainer linking={linking}>...</NavigationContainer>
    ```
    """

    static let reactNavScreenOptionsDoc = """
    # Screen Options
    Customize the appearance and behavior of screens.

    ## Setting Options
    ```tsx
    // Static (in navigator)
    <Stack.Screen name="Home" component={HomeScreen} options={{ title: 'My App', headerStyle: { backgroundColor: '#f4511e' } }} />

    // Dynamic (from screen component)
    navigation.setOptions({ title: route.params?.title ?? 'Default' });

    // Function (receives { route, navigation })
    <Stack.Screen name="Details" options={({ route }) => ({ title: route.params.title })} />
    ```
    """

    // MARK: - State Management

    static let zustandDoc = """
    # Zustand
    Lightweight state management for React. Simpler than Redux with minimal boilerplate.

    ## Installation
    npm install zustand

    ## Create Store
    ```tsx
    import { create } from 'zustand';

    interface BearStore {
      bears: number;
      increase: () => void;
      reset: () => void;
    }

    const useBearStore = create<BearStore>((set) => ({
      bears: 0,
      increase: () => set((state) => ({ bears: state.bears + 1 })),
      reset: () => set({ bears: 0 }),
    }));
    ```

    ## Usage in Components
    ```tsx
    function BearCounter() {
      const bears = useBearStore((state) => state.bears);
      return <Text>{bears} bears</Text>;
    }

    function Controls() {
      const increase = useBearStore((state) => state.increase);
      return <Button onPress={increase} title="Add bear" />;
    }
    ```

    ## Persist Middleware (AsyncStorage)
    ```tsx
    import { persist, createJSONStorage } from 'zustand/middleware';
    import AsyncStorage from '@react-native-async-storage/async-storage';

    const useStore = create(
      persist<StoreState>(
        (set) => ({ ... }),
        { name: 'app-storage', storage: createJSONStorage(() => AsyncStorage) }
      )
    );
    ```

    ## Selectors
    Use selectors to subscribe only to specific state slices (avoids unnecessary re-renders):
    ```tsx
    const bears = useBearStore((state) => state.bears); // Only re-renders when bears changes
    ```
    """

    static let reactQueryDoc = """
    # TanStack React Query
    Powerful async state management for fetching, caching, synchronizing, and updating server state.

    ## Installation
    npm install @tanstack/react-query

    ## Setup
    ```tsx
    import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
    const queryClient = new QueryClient();

    <QueryClientProvider client={queryClient}>
      <App />
    </QueryClientProvider>
    ```

    ## useQuery (Data Fetching)
    ```tsx
    import { useQuery } from '@tanstack/react-query';

    function UserProfile({ userId }: { userId: string }) {
      const { data, isLoading, error, refetch } = useQuery({
        queryKey: ['user', userId],
        queryFn: () => fetch(`/api/users/${userId}`).then(res => res.json()),
        staleTime: 5 * 60 * 1000, // 5 minutes
      });

      if (isLoading) return <ActivityIndicator />;
      if (error) return <Text>Error: {error.message}</Text>;
      return <Text>{data.name}</Text>;
    }
    ```

    ## useMutation (Write Operations)
    ```tsx
    const mutation = useMutation({
      mutationFn: (newUser: NewUser) => fetch('/api/users', { method: 'POST', body: JSON.stringify(newUser) }),
      onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['users'] }); },
    });

    mutation.mutate({ name: 'John', email: 'john@example.com' });
    ```

    ## Key Concepts
    - queryKey: Unique key for caching (array). Queries with same key share cache.
    - staleTime: How long data is considered fresh (default 0)
    - gcTime: How long inactive data stays in cache (default 5 min)
    - refetchOnWindowFocus: Auto-refetch when app comes to foreground
    - invalidateQueries: Mark queries as stale and refetch
    """

    // MARK: - Animation Libraries

    static let reanimatedDoc = """
    # React Native Reanimated
    Performant animations that run on the UI thread. Replacement for React Native's built-in Animated API.

    ## Installation
    npx expo install react-native-reanimated
    Add 'react-native-reanimated/plugin' to babel.config.js plugins.

    ## Core Concepts
    - Shared Values: useSharedValue() - Values shared between JS and UI threads
    - Animated Styles: useAnimatedStyle() - Styles derived from shared values
    - Animations: withSpring(), withTiming(), withDecay(), withSequence(), withRepeat()
    - Animated Components: Animated.View, Animated.Text, Animated.ScrollView

    ## Example
    ```tsx
    import Animated, { useSharedValue, useAnimatedStyle, withSpring } from 'react-native-reanimated';

    function Box() {
      const offset = useSharedValue(0);
      const animatedStyle = useAnimatedStyle(() => ({
        transform: [{ translateX: offset.value }],
      }));

      return (
        <Animated.View style={[styles.box, animatedStyle]}>
          <Pressable onPress={() => { offset.value = withSpring(offset.value + 50); }}>
            <Text>Move</Text>
          </Pressable>
        </Animated.View>
      );
    }
    ```

    ## Entering/Exiting Animations
    ```tsx
    import { FadeIn, FadeOut, SlideInLeft } from 'react-native-reanimated';
    <Animated.View entering={FadeIn.duration(500)} exiting={FadeOut}>
      <Text>Animated!</Text>
    </Animated.View>
    ```
    """

    static let gestureHandlerDoc = """
    # React Native Gesture Handler
    Native-driven gesture handling for React Native.

    ## Installation
    npx expo install react-native-gesture-handler

    ## Setup
    Wrap your app in GestureHandlerRootView:
    ```tsx
    import { GestureHandlerRootView } from 'react-native-gesture-handler';
    <GestureHandlerRootView style={{ flex: 1 }}>
      <App />
    </GestureHandlerRootView>
    ```

    ## Gesture API
    ```tsx
    import { Gesture, GestureDetector } from 'react-native-gesture-handler';
    import Animated, { useSharedValue, useAnimatedStyle } from 'react-native-reanimated';

    const translateX = useSharedValue(0);
    const pan = Gesture.Pan().onUpdate((e) => { translateX.value = e.translationX; });
    const animatedStyle = useAnimatedStyle(() => ({
      transform: [{ translateX: translateX.value }],
    }));

    <GestureDetector gesture={pan}>
      <Animated.View style={[styles.box, animatedStyle]} />
    </GestureDetector>
    ```

    ## Available Gestures
    - Gesture.Tap() - Single/double/multi-tap
    - Gesture.Pan() - Drag/swipe
    - Gesture.Pinch() - Scale with two fingers
    - Gesture.Rotation() - Rotate with two fingers
    - Gesture.LongPress() - Long press
    - Gesture.Fling() - Quick directional swipe
    - Gesture.Simultaneous() - Combine gestures
    - Gesture.Exclusive() - Only one gesture wins
    """

    // MARK: - UI Libraries

    static let flashListDoc = """
    # FlashList (@shopify/flash-list)
    High-performance replacement for FlatList by Shopify. 5-10x faster for large lists.

    ## Installation
    npx expo install @shopify/flash-list

    ## Usage
    ```tsx
    import { FlashList } from '@shopify/flash-list';

    <FlashList
      data={items}
      renderItem={({ item }) => <ItemComponent item={item} />}
      estimatedItemSize={80}
      keyExtractor={item => item.id}
    />
    ```

    ## Key Difference from FlatList
    - estimatedItemSize is REQUIRED (estimate average item height in dp)
    - Uses recycling instead of creating new cells (like UITableView on iOS)
    - Much better scroll performance for large datasets
    """

    static let bottomSheetDoc = """
    # React Native Bottom Sheet (@gorhom/bottom-sheet)
    Performant bottom sheet component.

    ## Installation
    npx expo install @gorhom/bottom-sheet react-native-reanimated react-native-gesture-handler

    ## Usage
    ```tsx
    import BottomSheet from '@gorhom/bottom-sheet';

    const bottomSheetRef = useRef<BottomSheet>(null);
    const snapPoints = useMemo(() => ['25%', '50%', '90%'], []);

    <BottomSheet ref={bottomSheetRef} index={0} snapPoints={snapPoints}>
      <View style={{ padding: 16 }}>
        <Text>Bottom Sheet Content</Text>
      </View>
    </BottomSheet>
    ```

    ## Methods
    - bottomSheetRef.current?.expand()
    - bottomSheetRef.current?.collapse()
    - bottomSheetRef.current?.close()
    - bottomSheetRef.current?.snapToIndex(index)
    """

    static let safeAreaContextDoc = """
    # react-native-safe-area-context
    Access safe area insets for proper layout around notches, status bar, and home indicator.

    ## Installation
    npx expo install react-native-safe-area-context

    ## Setup
    ```tsx
    import { SafeAreaProvider } from 'react-native-safe-area-context';
    <SafeAreaProvider>
      <App />
    </SafeAreaProvider>
    ```

    ## Usage
    ```tsx
    // Hook (recommended)
    import { useSafeAreaInsets } from 'react-native-safe-area-context';
    const insets = useSafeAreaInsets();
    <View style={{ paddingTop: insets.top, paddingBottom: insets.bottom }}>...</View>

    // Component
    import { SafeAreaView } from 'react-native-safe-area-context';
    <SafeAreaView style={{ flex: 1 }}>...</SafeAreaView>
    ```

    ## Insets
    - insets.top: number (status bar + notch)
    - insets.bottom: number (home indicator)
    - insets.left: number
    - insets.right: number
    """

    // MARK: - Forms & Validation

    static let reactHookFormDoc = """
    # React Hook Form
    Performant form state management with minimal re-renders.

    ## Installation
    npm install react-hook-form

    ## Usage with React Native
    ```tsx
    import { useForm, Controller } from 'react-hook-form';

    interface FormData { email: string; password: string; }

    function LoginForm() {
      const { control, handleSubmit, formState: { errors } } = useForm<FormData>();

      const onSubmit = (data: FormData) => { console.log(data); };

      return (
        <View>
          <Controller
            control={control}
            name="email"
            rules={{ required: 'Email is required', pattern: { value: /^\\S+@\\S+$/i, message: 'Invalid email' } }}
            render={({ field: { onChange, onBlur, value } }) => (
              <TextInput onBlur={onBlur} onChangeText={onChange} value={value} placeholder="Email" keyboardType="email-address" autoCapitalize="none" />
            )}
          />
          {errors.email && <Text style={{ color: 'red' }}>{errors.email.message}</Text>}

          <Controller
            control={control}
            name="password"
            rules={{ required: 'Password is required', minLength: { value: 8, message: 'Min 8 characters' } }}
            render={({ field: { onChange, onBlur, value } }) => (
              <TextInput onBlur={onBlur} onChangeText={onChange} value={value} placeholder="Password" secureTextEntry />
            )}
          />

          <Button title="Login" onPress={handleSubmit(onSubmit)} />
        </View>
      );
    }
    ```
    """

    static let zodDoc = """
    # Zod
    TypeScript-first schema validation. Commonly used with React Hook Form via @hookform/resolvers.

    ## Installation
    npm install zod @hookform/resolvers

    ## Schema Definition
    ```tsx
    import { z } from 'zod';

    const userSchema = z.object({
      name: z.string().min(2, 'Name must be at least 2 characters'),
      email: z.string().email('Invalid email'),
      age: z.number().min(18, 'Must be 18 or older').optional(),
      role: z.enum(['admin', 'user', 'moderator']),
    });

    type User = z.infer<typeof userSchema>;
    ```

    ## With React Hook Form
    ```tsx
    import { zodResolver } from '@hookform/resolvers/zod';
    const { control, handleSubmit } = useForm<User>({ resolver: zodResolver(userSchema) });
    ```
    """

    // MARK: - Networking & Storage

    static let rnNetworkingDoc = """
    # React Native Networking
    React Native provides the Fetch API and XMLHttpRequest for network requests.

    ## Fetch API
    ```tsx
    // GET
    const response = await fetch('https://api.example.com/data');
    const json = await response.json();

    // POST
    const response = await fetch('https://api.example.com/users', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer token' },
      body: JSON.stringify({ name: 'John', email: 'john@example.com' }),
    });

    // Error handling
    try {
      const response = await fetch(url);
      if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
      const data = await response.json();
    } catch (error) {
      console.error('Network error:', error);
    }
    ```

    ## Custom Hook Pattern
    ```tsx
    function useApi<T>(url: string) {
      const [data, setData] = useState<T | null>(null);
      const [loading, setLoading] = useState(true);
      const [error, setError] = useState<string | null>(null);

      const fetchData = useCallback(async () => {
        try {
          setLoading(true);
          setError(null);
          const res = await fetch(url);
          if (!res.ok) throw new Error(`HTTP ${res.status}`);
          setData(await res.json());
        } catch (e) {
          setError(e instanceof Error ? e.message : 'Unknown error');
        } finally {
          setLoading(false);
        }
      }, [url]);

      useEffect(() => { fetchData(); }, [fetchData]);
      return { data, loading, error, refetch: fetchData };
    }
    ```
    """

    static let asyncStorageDoc = """
    # AsyncStorage (@react-native-async-storage/async-storage)
    Asynchronous, persistent, key-value storage. For sensitive data, use expo-secure-store instead.

    ## Installation
    npx expo install @react-native-async-storage/async-storage

    ## API
    ```tsx
    import AsyncStorage from '@react-native-async-storage/async-storage';

    // Store data
    await AsyncStorage.setItem('key', 'value');
    await AsyncStorage.setItem('user', JSON.stringify({ name: 'John', age: 30 }));

    // Read data
    const value = await AsyncStorage.getItem('key');
    const user = JSON.parse(await AsyncStorage.getItem('user') ?? 'null');

    // Remove
    await AsyncStorage.removeItem('key');

    // Multi operations
    await AsyncStorage.multiSet([['key1', 'val1'], ['key2', 'val2']]);
    const values = await AsyncStorage.multiGet(['key1', 'key2']);

    // Clear all
    await AsyncStorage.clear();
    ```

    ## Best Practices
    - Always wrap in try/catch — operations can fail
    - Use JSON.stringify/parse for objects
    - Create a typed wrapper for type safety
    - Never store sensitive data (tokens, passwords) — use expo-secure-store
    - Use meaningful key names with prefixes (e.g. '@myapp/user')
    """

    // MARK: - Testing

    static let rntlDoc = """
    # React Native Testing Library
    Test React Native components focusing on user interactions.

    ## Installation
    npm install --save-dev @testing-library/react-native

    ## Example
    ```tsx
    import { render, screen, fireEvent } from '@testing-library/react-native';

    test('counter increments', () => {
      render(<Counter />);
      const button = screen.getByText('Increment');
      fireEvent.press(button);
      expect(screen.getByText('Count: 1')).toBeTruthy();
    });
    ```

    ## Query Methods
    - getByText, queryByText, findByText
    - getByTestId, queryByTestId
    - getByPlaceholderText, queryByPlaceholderText
    - getByDisplayValue, queryByDisplayValue

    ## Actions
    - fireEvent.press(element)
    - fireEvent.changeText(element, 'new text')
    - fireEvent.scroll(element, eventData)
    - waitFor(() => expect(...))
    """

    // MARK: - Tooling

    static let expoConfigDoc = """
    # Expo Configuration
    Configure your app using app.json or app.config.ts.

    ## app.json
    ```json
    {
      "expo": {
        "name": "My App",
        "slug": "my-app",
        "version": "1.0.0",
        "orientation": "portrait",
        "icon": "./assets/icon.png",
        "splash": { "image": "./assets/splash.png", "resizeMode": "contain", "backgroundColor": "#ffffff" },
        "ios": { "bundleIdentifier": "com.myapp", "supportsTablet": true },
        "android": { "package": "com.myapp", "adaptiveIcon": { "foregroundImage": "./assets/adaptive-icon.png" } },
        "plugins": [],
        "extra": { "eas": { "projectId": "..." } }
      }
    }
    ```

    ## app.config.ts (Dynamic)
    ```tsx
    import { ExpoConfig } from 'expo/config';
    const config: ExpoConfig = {
      name: process.env.APP_NAME || 'My App',
      slug: 'my-app',
      extra: { apiUrl: process.env.API_URL },
    };
    export default config;
    ```
    """

    static let expoDevelopmentDoc = """
    # Expo Development Workflow
    - npx expo start - Start development server
    - npx expo start --clear - Clear bundler cache
    - npx expo install <package> - Install Expo-compatible packages
    - npx expo prebuild - Generate native projects
    - npx expo run:ios - Build and run on iOS
    - npx expo run:android - Build and run on Android
    - npx eas build - Build with Expo Application Services
    - npx eas submit - Submit to app stores
    """

    // MARK: - TypeScript

    static let tsReactNativeDoc = """
    # TypeScript with React Native
    TypeScript provides type safety for React Native applications.

    ## Component Types
    ```tsx
    // Props interface
    interface CardProps {
      title: string;
      subtitle?: string;
      onPress: () => void;
      children: React.ReactNode;
    }

    // Functional component
    const Card: React.FC<CardProps> = ({ title, subtitle, onPress, children }) => (
      <Pressable onPress={onPress}>
        <Text>{title}</Text>
        {subtitle && <Text>{subtitle}</Text>}
        {children}
      </Pressable>
    );

    // Or without React.FC (preferred)
    function Card({ title, subtitle, onPress, children }: CardProps) { ... }
    ```

    ## Common Types
    ```tsx
    // Event types
    onChangeText: (text: string) => void
    onPress: () => void
    onLayout: (event: LayoutChangeEvent) => void
    onScroll: (event: NativeSyntheticEvent<NativeScrollEvent>) => void

    // Style types
    style: ViewStyle | TextStyle | ImageStyle
    style: StyleProp<ViewStyle>

    // Ref types
    const ref = useRef<TextInput>(null);
    const ref = useRef<FlatList<ItemType>>(null);

    // State types
    const [items, setItems] = useState<Item[]>([]);
    const [user, setUser] = useState<User | null>(null);
    ```

    ## Utility Types
    - Partial<T> - All properties optional
    - Required<T> - All properties required
    - Pick<T, K> - Select specific properties
    - Omit<T, K> - Exclude specific properties
    - Record<K, V> - Object with keys K and values V
    """
}
