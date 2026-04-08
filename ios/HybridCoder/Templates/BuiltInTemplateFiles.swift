import Foundation

enum BlankExpoTSFiles {
    static let files: [TemplateFileBlueprint] = [
        TemplateFileBlueprint(name: "App.tsx", content: appTsx),
        TemplateFileBlueprint(name: "app.json", content: appJson, language: "json"),
        TemplateFileBlueprint(name: "package.json", content: packageJson, language: "json"),
        TemplateFileBlueprint(name: "tsconfig.json", content: tsconfig, language: "json"),
    ]

    private static let appTsx = """
    import React from 'react';
    import { View, Text, StyleSheet } from 'react-native';

    export default function App() {
      return (
        <View style={styles.container}>
          <Text style={styles.text}>Start building!</Text>
        </View>
      );
    }

    const styles = StyleSheet.create({
      container: { flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: '#0f0f23' },
      text: { color: '#00d97e', fontSize: 24, fontWeight: '600' },
    });
    """

    private static let appJson = """
    {
      "expo": {
        "name": "my-app",
        "slug": "my-app",
        "version": "1.0.0",
        "orientation": "portrait",
        "platforms": ["ios", "android"],
        "newArchEnabled": true
      }
    }
    """

    private static let packageJson = """
    {
      "name": "my-app",
      "version": "1.0.0",
      "main": "App.tsx",
      "scripts": {
        "start": "expo start",
        "ios": "expo start --ios",
        "android": "expo start --android"
      },
      "dependencies": {
        "expo": "~52.0.0",
        "react": "18.3.1",
        "react-native": "0.76.0"
      },
      "devDependencies": {
        "@types/react": "~18.3.0",
        "typescript": "~5.3.0"
      }
    }
    """

    private static let tsconfig = """
    {
      "extends": "expo/tsconfig.base",
      "compilerOptions": {
        "strict": true
      }
    }
    """
}

enum BlankExpoJSFiles {
    static let files: [TemplateFileBlueprint] = [
        TemplateFileBlueprint(name: "App.js", content: appJs, language: "javascript"),
        TemplateFileBlueprint(name: "app.json", content: BlankExpoTSFiles.files.first { $0.name == "app.json" }?.content ?? "{}", language: "json"),
        TemplateFileBlueprint(name: "package.json", content: packageJson, language: "json"),
    ]

    private static let appJs = """
    import React from 'react';
    import { View, Text, StyleSheet } from 'react-native';

    export default function App() {
      return (
        <View style={styles.container}>
          <Text style={styles.text}>Start building!</Text>
        </View>
      );
    }

    const styles = StyleSheet.create({
      container: { flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: '#0f0f23' },
      text: { color: '#00d97e', fontSize: 24, fontWeight: '600' },
    });
    """

    private static let packageJson = """
    {
      "name": "my-app",
      "version": "1.0.0",
      "main": "App.js",
      "scripts": {
        "start": "expo start",
        "ios": "expo start --ios",
        "android": "expo start --android"
      },
      "dependencies": {
        "expo": "~52.0.0",
        "react": "18.3.1",
        "react-native": "0.76.0"
      }
    }
    """
}

enum TabsStarterFiles {
    static let files: [TemplateFileBlueprint] = [
        TemplateFileBlueprint(name: "App.tsx", content: appTsx),
        TemplateFileBlueprint(name: "src/screens/HomeScreen.tsx", content: homeScreen),
        TemplateFileBlueprint(name: "src/screens/SearchScreen.tsx", content: searchScreen),
        TemplateFileBlueprint(name: "src/screens/ProfileScreen.tsx", content: profileScreen),
        TemplateFileBlueprint(name: "app.json", content: BlankExpoTSFiles.files.first { $0.name == "app.json" }?.content ?? "{}", language: "json"),
        TemplateFileBlueprint(name: "package.json", content: packageJson, language: "json"),
        TemplateFileBlueprint(name: "tsconfig.json", content: BlankExpoTSFiles.files.first { $0.name == "tsconfig.json" }?.content ?? "{}", language: "json"),
    ]

    private static let appTsx = """
    import React from 'react';
    import { NavigationContainer } from '@react-navigation/native';
    import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
    import HomeScreen from './src/screens/HomeScreen';
    import SearchScreen from './src/screens/SearchScreen';
    import ProfileScreen from './src/screens/ProfileScreen';

    const Tab = createBottomTabNavigator();

    export default function App() {
      return (
        <NavigationContainer>
          <Tab.Navigator
            screenOptions={{
              headerStyle: { backgroundColor: '#0f0f23' },
              headerTintColor: '#fff',
              tabBarStyle: { backgroundColor: '#0f0f23', borderTopColor: '#1a1a3e' },
              tabBarActiveTintColor: '#00d97e',
              tabBarInactiveTintColor: '#666',
            }}
          >
            <Tab.Screen name="Home" component={HomeScreen} />
            <Tab.Screen name="Search" component={SearchScreen} />
            <Tab.Screen name="Profile" component={ProfileScreen} />
          </Tab.Navigator>
        </NavigationContainer>
      );
    }
    """

    private static let homeScreen = """
    import React from 'react';
    import { View, Text, StyleSheet } from 'react-native';

    export default function HomeScreen() {
      return (
        <View style={styles.container}>
          <Text style={styles.title}>Home</Text>
          <Text style={styles.subtitle}>Welcome back!</Text>
        </View>
      );
    }

    const styles = StyleSheet.create({
      container: { flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: '#0f0f23' },
      title: { color: '#fff', fontSize: 28, fontWeight: 'bold', marginBottom: 8 },
      subtitle: { color: '#aaa', fontSize: 16 },
    });
    """

    private static let searchScreen = """
    import React from 'react';
    import { View, Text, StyleSheet } from 'react-native';

    export default function SearchScreen() {
      return (
        <View style={styles.container}>
          <Text style={styles.title}>Search</Text>
          <Text style={styles.subtitle}>Find anything</Text>
        </View>
      );
    }

    const styles = StyleSheet.create({
      container: { flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: '#0f0f23' },
      title: { color: '#fff', fontSize: 28, fontWeight: 'bold', marginBottom: 8 },
      subtitle: { color: '#aaa', fontSize: 16 },
    });
    """

    private static let profileScreen = """
    import React from 'react';
    import { View, Text, StyleSheet } from 'react-native';

    export default function ProfileScreen() {
      return (
        <View style={styles.container}>
          <Text style={styles.title}>Profile</Text>
          <Text style={styles.subtitle}>Your settings</Text>
        </View>
      );
    }

    const styles = StyleSheet.create({
      container: { flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: '#0f0f23' },
      title: { color: '#fff', fontSize: 28, fontWeight: 'bold', marginBottom: 8 },
      subtitle: { color: '#aaa', fontSize: 16 },
    });
    """

    private static let packageJson = """
    {
      "name": "my-app",
      "version": "1.0.0",
      "main": "App.tsx",
      "scripts": {
        "start": "expo start",
        "ios": "expo start --ios",
        "android": "expo start --android"
      },
      "dependencies": {
        "expo": "~52.0.0",
        "react": "18.3.1",
        "react-native": "0.76.0",
        "@react-navigation/native": "^7.0.0",
        "@react-navigation/bottom-tabs": "^7.0.0",
        "react-native-screens": "~4.0.0",
        "react-native-safe-area-context": "~5.0.0"
      },
      "devDependencies": {
        "@types/react": "~18.3.0",
        "typescript": "~5.3.0"
      }
    }
    """
}

enum StackStarterFiles {
    static let files: [TemplateFileBlueprint] = [
        TemplateFileBlueprint(name: "App.tsx", content: appTsx),
        TemplateFileBlueprint(name: "src/screens/HomeScreen.tsx", content: homeScreen),
        TemplateFileBlueprint(name: "src/screens/DetailsScreen.tsx", content: detailsScreen),
        TemplateFileBlueprint(name: "app.json", content: BlankExpoTSFiles.files.first { $0.name == "app.json" }?.content ?? "{}", language: "json"),
        TemplateFileBlueprint(name: "package.json", content: packageJson, language: "json"),
        TemplateFileBlueprint(name: "tsconfig.json", content: BlankExpoTSFiles.files.first { $0.name == "tsconfig.json" }?.content ?? "{}", language: "json"),
    ]

    private static let appTsx = """
    import React from 'react';
    import { NavigationContainer } from '@react-navigation/native';
    import { createNativeStackNavigator } from '@react-navigation/native-stack';
    import HomeScreen from './src/screens/HomeScreen';
    import DetailsScreen from './src/screens/DetailsScreen';

    const Stack = createNativeStackNavigator();

    export default function App() {
      return (
        <NavigationContainer>
          <Stack.Navigator
            screenOptions={{
              headerStyle: { backgroundColor: '#0f0f23' },
              headerTintColor: '#00d97e',
            }}
          >
            <Stack.Screen name="Home" component={HomeScreen} />
            <Stack.Screen name="Details" component={DetailsScreen} />
          </Stack.Navigator>
        </NavigationContainer>
      );
    }
    """

    private static let homeScreen = """
    import React from 'react';
    import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';

    export default function HomeScreen({ navigation }: any) {
      return (
        <View style={styles.container}>
          <Text style={styles.title}>Home</Text>
          <TouchableOpacity style={styles.button} onPress={() => navigation.navigate('Details')}>
            <Text style={styles.buttonText}>Go to Details</Text>
          </TouchableOpacity>
        </View>
      );
    }

    const styles = StyleSheet.create({
      container: { flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: '#0f0f23' },
      title: { color: '#fff', fontSize: 28, fontWeight: 'bold', marginBottom: 24 },
      button: { backgroundColor: '#00d97e', paddingHorizontal: 24, paddingVertical: 12, borderRadius: 10 },
      buttonText: { color: '#0f0f23', fontSize: 16, fontWeight: '600' },
    });
    """

    private static let detailsScreen = """
    import React from 'react';
    import { View, Text, StyleSheet } from 'react-native';

    export default function DetailsScreen() {
      return (
        <View style={styles.container}>
          <Text style={styles.title}>Details</Text>
          <Text style={styles.subtitle}>You navigated here!</Text>
        </View>
      );
    }

    const styles = StyleSheet.create({
      container: { flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: '#0f0f23' },
      title: { color: '#fff', fontSize: 28, fontWeight: 'bold', marginBottom: 8 },
      subtitle: { color: '#aaa', fontSize: 16 },
    });
    """

    private static let packageJson = """
    {
      "name": "my-app",
      "version": "1.0.0",
      "main": "App.tsx",
      "scripts": {
        "start": "expo start",
        "ios": "expo start --ios",
        "android": "expo start --android"
      },
      "dependencies": {
        "expo": "~52.0.0",
        "react": "18.3.1",
        "react-native": "0.76.0",
        "@react-navigation/native": "^7.0.0",
        "@react-navigation/native-stack": "^7.0.0",
        "react-native-screens": "~4.0.0",
        "react-native-safe-area-context": "~5.0.0"
      },
      "devDependencies": {
        "@types/react": "~18.3.0",
        "typescript": "~5.3.0"
      }
    }
    """
}

enum AuthStarterFiles {
    static let files: [TemplateFileBlueprint] = [
        TemplateFileBlueprint(name: "App.tsx", content: appTsx),
        TemplateFileBlueprint(name: "src/screens/SignInScreen.tsx", content: signInScreen),
        TemplateFileBlueprint(name: "src/screens/SignUpScreen.tsx", content: signUpScreen),
        TemplateFileBlueprint(name: "src/screens/HomeScreen.tsx", content: homeScreen),
        TemplateFileBlueprint(name: "src/context/AuthContext.tsx", content: authContext),
        TemplateFileBlueprint(name: "app.json", content: BlankExpoTSFiles.files.first { $0.name == "app.json" }?.content ?? "{}", language: "json"),
        TemplateFileBlueprint(name: "package.json", content: StackStarterFiles.files.first { $0.name == "package.json" }?.content ?? "{}", language: "json"),
        TemplateFileBlueprint(name: "tsconfig.json", content: BlankExpoTSFiles.files.first { $0.name == "tsconfig.json" }?.content ?? "{}", language: "json"),
    ]

    private static let appTsx = """
    import React from 'react';
    import { NavigationContainer } from '@react-navigation/native';
    import { createNativeStackNavigator } from '@react-navigation/native-stack';
    import { AuthProvider, useAuth } from './src/context/AuthContext';
    import SignInScreen from './src/screens/SignInScreen';
    import SignUpScreen from './src/screens/SignUpScreen';
    import HomeScreen from './src/screens/HomeScreen';

    const Stack = createNativeStackNavigator();

    function AppNavigator() {
      const { user } = useAuth();
      return (
        <Stack.Navigator screenOptions={{ headerStyle: { backgroundColor: '#0f0f23' }, headerTintColor: '#00d97e' }}>
          {user ? (
            <Stack.Screen name="Home" component={HomeScreen} />
          ) : (
            <>
              <Stack.Screen name="SignIn" component={SignInScreen} options={{ title: 'Sign In' }} />
              <Stack.Screen name="SignUp" component={SignUpScreen} options={{ title: 'Sign Up' }} />
            </>
          )}
        </Stack.Navigator>
      );
    }

    export default function App() {
      return (
        <AuthProvider>
          <NavigationContainer>
            <AppNavigator />
          </NavigationContainer>
        </AuthProvider>
      );
    }
    """

    private static let authContext = """
    import React, { createContext, useContext, useState, ReactNode } from 'react';

    interface User { email: string; name: string; }
    interface AuthContextType {
      user: User | null;
      signIn: (email: string, password: string) => Promise<void>;
      signUp: (email: string, password: string, name: string) => Promise<void>;
      signOut: () => void;
    }

    const AuthContext = createContext<AuthContextType | undefined>(undefined);

    export function AuthProvider({ children }: { children: ReactNode }) {
      const [user, setUser] = useState<User | null>(null);

      const signIn = async (email: string, _password: string) => {
        await new Promise(r => setTimeout(r, 800));
        setUser({ email, name: email.split('@')[0] });
      };

      const signUp = async (email: string, _password: string, name: string) => {
        await new Promise(r => setTimeout(r, 800));
        setUser({ email, name });
      };

      const signOut = () => setUser(null);

      return (
        <AuthContext.Provider value={{ user, signIn, signUp, signOut }}>
          {children}
        </AuthContext.Provider>
      );
    }

    export function useAuth() {
      const ctx = useContext(AuthContext);
      if (!ctx) throw new Error('useAuth must be inside AuthProvider');
      return ctx;
    }
    """

    private static let signInScreen = """
    import React, { useState } from 'react';
    import { View, Text, TextInput, TouchableOpacity, ActivityIndicator, StyleSheet } from 'react-native';
    import { useAuth } from '../context/AuthContext';

    export default function SignInScreen({ navigation }: any) {
      const { signIn } = useAuth();
      const [email, setEmail] = useState('');
      const [password, setPassword] = useState('');
      const [loading, setLoading] = useState(false);

      const handleSignIn = async () => {
        setLoading(true);
        await signIn(email, password);
        setLoading(false);
      };

      return (
        <View style={styles.container}>
          <Text style={styles.title}>Welcome Back</Text>
          <TextInput style={styles.input} value={email} onChangeText={setEmail} placeholder="Email" placeholderTextColor="#555" autoCapitalize="none" keyboardType="email-address" />
          <TextInput style={styles.input} value={password} onChangeText={setPassword} placeholder="Password" placeholderTextColor="#555" secureTextEntry />
          <TouchableOpacity style={styles.button} onPress={handleSignIn} disabled={loading}>
            {loading ? <ActivityIndicator color="#0f0f23" /> : <Text style={styles.buttonText}>Sign In</Text>}
          </TouchableOpacity>
          <TouchableOpacity onPress={() => navigation.navigate('SignUp')}>
            <Text style={styles.link}>Don't have an account? Sign Up</Text>
          </TouchableOpacity>
        </View>
      );
    }

    const styles = StyleSheet.create({
      container: { flex: 1, padding: 24, justifyContent: 'center', backgroundColor: '#0f0f23' },
      title: { color: '#fff', fontSize: 32, fontWeight: 'bold', marginBottom: 32, textAlign: 'center' },
      input: { backgroundColor: '#1a1a3e', color: '#fff', padding: 14, borderRadius: 10, fontSize: 16, marginBottom: 12 },
      button: { backgroundColor: '#00d97e', padding: 16, borderRadius: 12, alignItems: 'center', marginTop: 8 },
      buttonText: { color: '#0f0f23', fontSize: 18, fontWeight: '700' },
      link: { color: '#00d97e', textAlign: 'center', marginTop: 20, fontSize: 14 },
    });
    """

    private static let signUpScreen = """
    import React, { useState } from 'react';
    import { View, Text, TextInput, TouchableOpacity, ActivityIndicator, StyleSheet } from 'react-native';
    import { useAuth } from '../context/AuthContext';

    export default function SignUpScreen({ navigation }: any) {
      const { signUp } = useAuth();
      const [name, setName] = useState('');
      const [email, setEmail] = useState('');
      const [password, setPassword] = useState('');
      const [loading, setLoading] = useState(false);

      const handleSignUp = async () => {
        setLoading(true);
        await signUp(email, password, name);
        setLoading(false);
      };

      return (
        <View style={styles.container}>
          <Text style={styles.title}>Create Account</Text>
          <TextInput style={styles.input} value={name} onChangeText={setName} placeholder="Name" placeholderTextColor="#555" />
          <TextInput style={styles.input} value={email} onChangeText={setEmail} placeholder="Email" placeholderTextColor="#555" autoCapitalize="none" keyboardType="email-address" />
          <TextInput style={styles.input} value={password} onChangeText={setPassword} placeholder="Password" placeholderTextColor="#555" secureTextEntry />
          <TouchableOpacity style={styles.button} onPress={handleSignUp} disabled={loading}>
            {loading ? <ActivityIndicator color="#0f0f23" /> : <Text style={styles.buttonText}>Sign Up</Text>}
          </TouchableOpacity>
          <TouchableOpacity onPress={() => navigation.goBack()}>
            <Text style={styles.link}>Already have an account? Sign In</Text>
          </TouchableOpacity>
        </View>
      );
    }

    const styles = StyleSheet.create({
      container: { flex: 1, padding: 24, justifyContent: 'center', backgroundColor: '#0f0f23' },
      title: { color: '#fff', fontSize: 32, fontWeight: 'bold', marginBottom: 32, textAlign: 'center' },
      input: { backgroundColor: '#1a1a3e', color: '#fff', padding: 14, borderRadius: 10, fontSize: 16, marginBottom: 12 },
      button: { backgroundColor: '#00d97e', padding: 16, borderRadius: 12, alignItems: 'center', marginTop: 8 },
      buttonText: { color: '#0f0f23', fontSize: 18, fontWeight: '700' },
      link: { color: '#00d97e', textAlign: 'center', marginTop: 20, fontSize: 14 },
    });
    """

    private static let homeScreen = """
    import React from 'react';
    import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
    import { useAuth } from '../context/AuthContext';

    export default function HomeScreen() {
      const { user, signOut } = useAuth();
      return (
        <View style={styles.container}>
          <Text style={styles.title}>Welcome, {user?.name}!</Text>
          <Text style={styles.subtitle}>{user?.email}</Text>
          <TouchableOpacity style={styles.button} onPress={signOut}>
            <Text style={styles.buttonText}>Sign Out</Text>
          </TouchableOpacity>
        </View>
      );
    }

    const styles = StyleSheet.create({
      container: { flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: '#0f0f23' },
      title: { color: '#fff', fontSize: 28, fontWeight: 'bold', marginBottom: 8 },
      subtitle: { color: '#aaa', fontSize: 16, marginBottom: 32 },
      button: { backgroundColor: '#ff4444', paddingHorizontal: 24, paddingVertical: 12, borderRadius: 10 },
      buttonText: { color: '#fff', fontSize: 16, fontWeight: '600' },
    });
    """
}

enum APIClientFiles {
    static let files: [TemplateFileBlueprint] = [
        TemplateFileBlueprint(name: "App.tsx", content: SandboxProject.TemplateType.apiExample.defaultCode, language: "typescript"),
        TemplateFileBlueprint(name: "app.json", content: BlankExpoTSFiles.files.first { $0.name == "app.json" }?.content ?? "{}", language: "json"),
        TemplateFileBlueprint(name: "package.json", content: BlankExpoTSFiles.files.first { $0.name == "package.json" }?.content ?? "{}", language: "json"),
        TemplateFileBlueprint(name: "tsconfig.json", content: BlankExpoTSFiles.files.first { $0.name == "tsconfig.json" }?.content ?? "{}", language: "json"),
    ]
}

enum TodoAppFiles {
    static let files: [TemplateFileBlueprint] = [
        TemplateFileBlueprint(name: "App.tsx", content: SandboxProject.TemplateType.todoApp.defaultCode, language: "typescript"),
        TemplateFileBlueprint(name: "app.json", content: BlankExpoTSFiles.files.first { $0.name == "app.json" }?.content ?? "{}", language: "json"),
        TemplateFileBlueprint(name: "package.json", content: BlankExpoTSFiles.files.first { $0.name == "package.json" }?.content ?? "{}", language: "json"),
        TemplateFileBlueprint(name: "tsconfig.json", content: BlankExpoTSFiles.files.first { $0.name == "tsconfig.json" }?.content ?? "{}", language: "json"),
    ]
}

enum NotesTasksFiles {
    static let files: [TemplateFileBlueprint] = [
        TemplateFileBlueprint(name: "App.tsx", content: appTsx),
        TemplateFileBlueprint(name: "src/screens/NotesScreen.tsx", content: notesScreen),
        TemplateFileBlueprint(name: "src/screens/TasksScreen.tsx", content: tasksScreen),
        TemplateFileBlueprint(name: "app.json", content: BlankExpoTSFiles.files.first { $0.name == "app.json" }?.content ?? "{}", language: "json"),
        TemplateFileBlueprint(name: "package.json", content: TabsStarterFiles.files.first { $0.name == "package.json" }?.content ?? "{}", language: "json"),
        TemplateFileBlueprint(name: "tsconfig.json", content: BlankExpoTSFiles.files.first { $0.name == "tsconfig.json" }?.content ?? "{}", language: "json"),
    ]

    private static let appTsx = """
    import React from 'react';
    import { NavigationContainer } from '@react-navigation/native';
    import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
    import NotesScreen from './src/screens/NotesScreen';
    import TasksScreen from './src/screens/TasksScreen';

    const Tab = createBottomTabNavigator();

    export default function App() {
      return (
        <NavigationContainer>
          <Tab.Navigator screenOptions={{
            headerStyle: { backgroundColor: '#0f0f23' },
            headerTintColor: '#fff',
            tabBarStyle: { backgroundColor: '#0f0f23', borderTopColor: '#1a1a3e' },
            tabBarActiveTintColor: '#00d97e',
            tabBarInactiveTintColor: '#666',
          }}>
            <Tab.Screen name="Notes" component={NotesScreen} />
            <Tab.Screen name="Tasks" component={TasksScreen} />
          </Tab.Navigator>
        </NavigationContainer>
      );
    }
    """

    private static let notesScreen = """
    import React, { useState } from 'react';
    import { View, Text, TextInput, TouchableOpacity, FlatList, StyleSheet } from 'react-native';

    interface Note { id: string; title: string; body: string; updatedAt: string; }

    export default function NotesScreen() {
      const [notes, setNotes] = useState<Note[]>([]);
      const [title, setTitle] = useState('');
      const [body, setBody] = useState('');
      const [editingId, setEditingId] = useState<string | null>(null);

      const saveNote = () => {
        if (!title.trim()) return;
        if (editingId) {
          setNotes(notes.map(n => n.id === editingId ? { ...n, title, body, updatedAt: new Date().toLocaleString() } : n));
        } else {
          setNotes([{ id: Date.now().toString(), title, body, updatedAt: new Date().toLocaleString() }, ...notes]);
        }
        setTitle(''); setBody(''); setEditingId(null);
      };

      return (
        <View style={styles.container}>
          <View style={styles.editor}>
            <TextInput style={styles.titleInput} value={title} onChangeText={setTitle} placeholder="Note title" placeholderTextColor="#555" />
            <TextInput style={styles.bodyInput} value={body} onChangeText={setBody} placeholder="Write something..." placeholderTextColor="#555" multiline />
            <TouchableOpacity style={styles.saveBtn} onPress={saveNote}>
              <Text style={styles.saveBtnText}>{editingId ? 'Update' : 'Save'}</Text>
            </TouchableOpacity>
          </View>
          <FlatList data={notes} keyExtractor={i => i.id} renderItem={({ item }) => (
            <TouchableOpacity style={styles.card} onPress={() => { setEditingId(item.id); setTitle(item.title); setBody(item.body); }}>
              <Text style={styles.cardTitle}>{item.title}</Text>
              <Text style={styles.cardBody} numberOfLines={2}>{item.body}</Text>
              <Text style={styles.cardDate}>{item.updatedAt}</Text>
            </TouchableOpacity>
          )} />
        </View>
      );
    }

    const styles = StyleSheet.create({
      container: { flex: 1, backgroundColor: '#0f0f23', padding: 16 },
      editor: { backgroundColor: '#1a1a3e', borderRadius: 12, padding: 14, marginBottom: 16 },
      titleInput: { color: '#fff', fontSize: 18, fontWeight: '600', marginBottom: 8 },
      bodyInput: { color: '#ccc', fontSize: 15, minHeight: 60, textAlignVertical: 'top' },
      saveBtn: { backgroundColor: '#00d97e', padding: 12, borderRadius: 10, alignItems: 'center', marginTop: 10 },
      saveBtnText: { color: '#0f0f23', fontSize: 16, fontWeight: '700' },
      card: { backgroundColor: '#1a1a3e', padding: 14, borderRadius: 10, marginBottom: 8 },
      cardTitle: { color: '#fff', fontSize: 16, fontWeight: '600', marginBottom: 4 },
      cardBody: { color: '#aaa', fontSize: 14, marginBottom: 6 },
      cardDate: { color: '#555', fontSize: 11 },
    });
    """

    private static let tasksScreen = """
    import React, { useState } from 'react';
    import { View, Text, TextInput, TouchableOpacity, FlatList, StyleSheet } from 'react-native';

    interface Task { id: string; text: string; done: boolean; }

    export default function TasksScreen() {
      const [tasks, setTasks] = useState<Task[]>([]);
      const [text, setText] = useState('');

      const addTask = () => {
        if (!text.trim()) return;
        setTasks([...tasks, { id: Date.now().toString(), text: text.trim(), done: false }]);
        setText('');
      };

      const toggleTask = (id: string) => {
        setTasks(tasks.map(t => t.id === id ? { ...t, done: !t.done } : t));
      };

      const deleteTask = (id: string) => {
        setTasks(tasks.filter(t => t.id !== id));
      };

      return (
        <View style={styles.container}>
          <View style={styles.inputRow}>
            <TextInput style={styles.input} value={text} onChangeText={setText} placeholder="Add task..." placeholderTextColor="#555" onSubmitEditing={addTask} />
            <TouchableOpacity style={styles.addBtn} onPress={addTask}>
              <Text style={styles.addText}>+</Text>
            </TouchableOpacity>
          </View>
          <FlatList data={tasks} keyExtractor={i => i.id} renderItem={({ item }) => (
            <TouchableOpacity style={styles.task} onPress={() => toggleTask(item.id)} onLongPress={() => deleteTask(item.id)}>
              <Text style={[styles.taskText, item.done && styles.done]}>{item.text}</Text>
              {item.done && <Text style={styles.check}>✓</Text>}
            </TouchableOpacity>
          )} />
        </View>
      );
    }

    const styles = StyleSheet.create({
      container: { flex: 1, backgroundColor: '#0f0f23', padding: 16 },
      inputRow: { flexDirection: 'row', marginBottom: 16 },
      input: { flex: 1, backgroundColor: '#1a1a3e', color: '#fff', padding: 14, borderRadius: 10, fontSize: 16 },
      addBtn: { backgroundColor: '#00d97e', width: 50, marginLeft: 10, borderRadius: 10, justifyContent: 'center', alignItems: 'center' },
      addText: { color: '#0f0f23', fontSize: 24, fontWeight: 'bold' },
      task: { backgroundColor: '#1a1a3e', padding: 16, borderRadius: 10, marginBottom: 8, flexDirection: 'row', alignItems: 'center' },
      taskText: { color: '#fff', fontSize: 16, flex: 1 },
      done: { textDecorationLine: 'line-through', color: '#666' },
      check: { color: '#00d97e', fontSize: 18, fontWeight: 'bold' },
    });
    """
}

enum DashboardFiles {
    static let files: [TemplateFileBlueprint] = [
        TemplateFileBlueprint(name: "App.tsx", content: appTsx),
        TemplateFileBlueprint(name: "src/screens/DashboardScreen.tsx", content: dashboardScreen),
        TemplateFileBlueprint(name: "src/screens/ActivityScreen.tsx", content: activityScreen),
        TemplateFileBlueprint(name: "app.json", content: BlankExpoTSFiles.files.first { $0.name == "app.json" }?.content ?? "{}", language: "json"),
        TemplateFileBlueprint(name: "package.json", content: TabsStarterFiles.files.first { $0.name == "package.json" }?.content ?? "{}", language: "json"),
        TemplateFileBlueprint(name: "tsconfig.json", content: BlankExpoTSFiles.files.first { $0.name == "tsconfig.json" }?.content ?? "{}", language: "json"),
    ]

    private static let appTsx = """
    import React from 'react';
    import { NavigationContainer } from '@react-navigation/native';
    import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
    import DashboardScreen from './src/screens/DashboardScreen';
    import ActivityScreen from './src/screens/ActivityScreen';

    const Tab = createBottomTabNavigator();

    export default function App() {
      return (
        <NavigationContainer>
          <Tab.Navigator screenOptions={{
            headerStyle: { backgroundColor: '#0f0f23' },
            headerTintColor: '#fff',
            tabBarStyle: { backgroundColor: '#0f0f23', borderTopColor: '#1a1a3e' },
            tabBarActiveTintColor: '#00d97e',
            tabBarInactiveTintColor: '#666',
          }}>
            <Tab.Screen name="Dashboard" component={DashboardScreen} />
            <Tab.Screen name="Activity" component={ActivityScreen} />
          </Tab.Navigator>
        </NavigationContainer>
      );
    }
    """

    private static let dashboardScreen = """
    import React from 'react';
    import { View, Text, ScrollView, StyleSheet } from 'react-native';

    function StatCard({ label, value, change }: { label: string; value: string; change: string }) {
      const isPositive = change.startsWith('+');
      return (
        <View style={styles.statCard}>
          <Text style={styles.statLabel}>{label}</Text>
          <Text style={styles.statValue}>{value}</Text>
          <Text style={[styles.statChange, { color: isPositive ? '#00d97e' : '#ff4444' }]}>{change}</Text>
        </View>
      );
    }

    export default function DashboardScreen() {
      return (
        <ScrollView style={styles.container} contentContainerStyle={styles.content}>
          <Text style={styles.greeting}>Good morning!</Text>
          <View style={styles.statsGrid}>
            <StatCard label="Revenue" value="$12,450" change="+12.5%" />
            <StatCard label="Users" value="1,234" change="+5.2%" />
            <StatCard label="Orders" value="89" change="-2.1%" />
            <StatCard label="Conversion" value="3.2%" change="+0.8%" />
          </View>
          <Text style={styles.sectionTitle}>Recent Activity</Text>
          {['New user signed up', 'Order #1234 completed', 'Payment received $250', 'New review posted'].map((item, i) => (
            <View key={i} style={styles.activityItem}>
              <View style={styles.activityDot} />
              <Text style={styles.activityText}>{item}</Text>
            </View>
          ))}
        </ScrollView>
      );
    }

    const styles = StyleSheet.create({
      container: { flex: 1, backgroundColor: '#0f0f23' },
      content: { padding: 16 },
      greeting: { color: '#fff', fontSize: 28, fontWeight: 'bold', marginBottom: 20 },
      statsGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: 10, marginBottom: 24 },
      statCard: { backgroundColor: '#1a1a3e', borderRadius: 12, padding: 16, width: '48%' as any },
      statLabel: { color: '#888', fontSize: 13, marginBottom: 4 },
      statValue: { color: '#fff', fontSize: 24, fontWeight: 'bold', marginBottom: 4 },
      statChange: { fontSize: 13, fontWeight: '600' },
      sectionTitle: { color: '#fff', fontSize: 18, fontWeight: '600', marginBottom: 12 },
      activityItem: { flexDirection: 'row', alignItems: 'center', paddingVertical: 12, borderBottomWidth: 1, borderBottomColor: '#1a1a3e' },
      activityDot: { width: 8, height: 8, borderRadius: 4, backgroundColor: '#00d97e', marginRight: 12 },
      activityText: { color: '#ccc', fontSize: 15 },
    });
    """

    private static let activityScreen = """
    import React from 'react';
    import { View, Text, FlatList, StyleSheet } from 'react-native';

    const activities = [
      { id: '1', type: 'user', message: 'New user signed up', time: '2 min ago' },
      { id: '2', type: 'order', message: 'Order #1234 completed', time: '15 min ago' },
      { id: '3', type: 'payment', message: 'Payment received $250', time: '1 hour ago' },
      { id: '4', type: 'review', message: 'New 5-star review', time: '2 hours ago' },
      { id: '5', type: 'user', message: 'User updated profile', time: '3 hours ago' },
    ];

    export default function ActivityScreen() {
      return (
        <FlatList
          style={styles.container}
          data={activities}
          keyExtractor={i => i.id}
          renderItem={({ item }) => (
            <View style={styles.row}>
              <View style={styles.iconContainer}>
                <Text style={styles.icon}>{item.type === 'user' ? '👤' : item.type === 'order' ? '📦' : item.type === 'payment' ? '💰' : '⭐'}</Text>
              </View>
              <View style={styles.info}>
                <Text style={styles.message}>{item.message}</Text>
                <Text style={styles.time}>{item.time}</Text>
              </View>
            </View>
          )}
        />
      );
    }

    const styles = StyleSheet.create({
      container: { flex: 1, backgroundColor: '#0f0f23' },
      row: { flexDirection: 'row', padding: 16, borderBottomWidth: 1, borderBottomColor: '#1a1a3e' },
      iconContainer: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#1a1a3e', justifyContent: 'center', alignItems: 'center', marginRight: 12 },
      icon: { fontSize: 18 },
      info: { flex: 1, justifyContent: 'center' },
      message: { color: '#fff', fontSize: 15, marginBottom: 2 },
      time: { color: '#666', fontSize: 12 },
    });
    """
}
