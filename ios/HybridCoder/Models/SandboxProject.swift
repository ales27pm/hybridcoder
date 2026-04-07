import Foundation

nonisolated struct SandboxProject: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var name: String
    var templateType: TemplateType
    var snackID: String?
    var createdAt: Date
    var lastOpenedAt: Date
    var files: [SandboxFile]

    nonisolated enum TemplateType: String, Codable, Sendable, CaseIterable {
        case blank = "Blank"
        case helloWorld = "Hello World"
        case navigation = "Navigation"
        case todoApp = "Todo App"
        case apiExample = "API Example"

        var defaultCode: String {
            switch self {
            case .blank:
                return """
                import React from 'react';
                import { View, Text, StyleSheet } from 'react-native';

                export default function App() {
                  return (
                    <View style={styles.container}>
                      <Text style={styles.text}>Start coding!</Text>
                    </View>
                  );
                }

                const styles = StyleSheet.create({
                  container: { flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: '#1a1a2e' },
                  text: { color: '#00d97e', fontSize: 24, fontWeight: '600' },
                });
                """
            case .helloWorld:
                return """
                import React, { useState } from 'react';
                import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';

                export default function App() {
                  const [count, setCount] = useState(0);

                  return (
                    <View style={styles.container}>
                      <Text style={styles.title}>Hello, Expo!</Text>
                      <Text style={styles.counter}>{count}</Text>
                      <TouchableOpacity style={styles.button} onPress={() => setCount(c => c + 1)}>
                        <Text style={styles.buttonText}>Tap Me</Text>
                      </TouchableOpacity>
                    </View>
                  );
                }

                const styles = StyleSheet.create({
                  container: { flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: '#1a1a2e' },
                  title: { color: '#fff', fontSize: 32, fontWeight: 'bold', marginBottom: 20 },
                  counter: { color: '#00d97e', fontSize: 64, fontWeight: '800', marginBottom: 30 },
                  button: { backgroundColor: '#00d97e', paddingHorizontal: 32, paddingVertical: 14, borderRadius: 12 },
                  buttonText: { color: '#1a1a2e', fontSize: 18, fontWeight: '700' },
                });
                """
            case .navigation:
                return """
                import React from 'react';
                import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
                import { NavigationContainer } from '@react-navigation/native';
                import { createNativeStackNavigator } from '@react-navigation/native-stack';

                const Stack = createNativeStackNavigator();

                function HomeScreen({ navigation }) {
                  return (
                    <View style={styles.container}>
                      <Text style={styles.title}>Home</Text>
                      <TouchableOpacity style={styles.button} onPress={() => navigation.navigate('Details')}>
                        <Text style={styles.buttonText}>Go to Details</Text>
                      </TouchableOpacity>
                    </View>
                  );
                }

                function DetailsScreen() {
                  return (
                    <View style={styles.container}>
                      <Text style={styles.title}>Details</Text>
                      <Text style={styles.subtitle}>You navigated here!</Text>
                    </View>
                  );
                }

                export default function App() {
                  return (
                    <NavigationContainer>
                      <Stack.Navigator screenOptions={{ headerStyle: { backgroundColor: '#1a1a2e' }, headerTintColor: '#00d97e' }}>
                        <Stack.Screen name="Home" component={HomeScreen} />
                        <Stack.Screen name="Details" component={DetailsScreen} />
                      </Stack.Navigator>
                    </NavigationContainer>
                  );
                }

                const styles = StyleSheet.create({
                  container: { flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: '#1a1a2e' },
                  title: { color: '#fff', fontSize: 28, fontWeight: 'bold', marginBottom: 16 },
                  subtitle: { color: '#aaa', fontSize: 16 },
                  button: { backgroundColor: '#00d97e', paddingHorizontal: 24, paddingVertical: 12, borderRadius: 10 },
                  buttonText: { color: '#1a1a2e', fontSize: 16, fontWeight: '600' },
                });
                """
            case .todoApp:
                return """
                import React, { useState } from 'react';
                import { View, Text, TextInput, TouchableOpacity, FlatList, StyleSheet } from 'react-native';

                export default function App() {
                  const [todos, setTodos] = useState([]);
                  const [text, setText] = useState('');

                  const addTodo = () => {
                    if (!text.trim()) return;
                    setTodos(prev => [...prev, { id: Date.now().toString(), text: text.trim(), done: false }]);
                    setText('');
                  };

                  const toggleTodo = (id) => {
                    setTodos(prev => prev.map(t => t.id === id ? { ...t, done: !t.done } : t));
                  };

                  return (
                    <View style={styles.container}>
                      <Text style={styles.title}>Todo App</Text>
                      <View style={styles.inputRow}>
                        <TextInput style={styles.input} value={text} onChangeText={setText} placeholder="Add task..." placeholderTextColor="#666" onSubmitEditing={addTodo} />
                        <TouchableOpacity style={styles.addBtn} onPress={addTodo}>
                          <Text style={styles.addText}>+</Text>
                        </TouchableOpacity>
                      </View>
                      <FlatList data={todos} keyExtractor={i => i.id} renderItem={({ item }) => (
                        <TouchableOpacity style={styles.todo} onPress={() => toggleTodo(item.id)}>
                          <Text style={[styles.todoText, item.done && styles.done]}>{item.text}</Text>
                        </TouchableOpacity>
                      )} />
                    </View>
                  );
                }

                const styles = StyleSheet.create({
                  container: { flex: 1, backgroundColor: '#1a1a2e', paddingTop: 60, paddingHorizontal: 20 },
                  title: { color: '#fff', fontSize: 28, fontWeight: 'bold', marginBottom: 20 },
                  inputRow: { flexDirection: 'row', marginBottom: 20 },
                  input: { flex: 1, backgroundColor: '#2a2a3e', color: '#fff', padding: 14, borderRadius: 10, fontSize: 16 },
                  addBtn: { backgroundColor: '#00d97e', width: 50, marginLeft: 10, borderRadius: 10, justifyContent: 'center', alignItems: 'center' },
                  addText: { color: '#1a1a2e', fontSize: 24, fontWeight: 'bold' },
                  todo: { backgroundColor: '#2a2a3e', padding: 16, borderRadius: 10, marginBottom: 8 },
                  todoText: { color: '#fff', fontSize: 16 },
                  done: { textDecorationLine: 'line-through', color: '#666' },
                });
                """
            case .apiExample:
                return """
                import React, { useState, useEffect } from 'react';
                import { View, Text, FlatList, ActivityIndicator, StyleSheet } from 'react-native';

                export default function App() {
                  const [data, setData] = useState([]);
                  const [loading, setLoading] = useState(true);

                  useEffect(() => {
                    fetch('https://jsonplaceholder.typicode.com/posts?_limit=20')
                      .then(res => res.json())
                      .then(json => { setData(json); setLoading(false); })
                      .catch(() => setLoading(false));
                  }, []);

                  if (loading) return (
                    <View style={styles.center}>
                      <ActivityIndicator size="large" color="#00d97e" />
                    </View>
                  );

                  return (
                    <View style={styles.container}>
                      <Text style={styles.title}>API Posts</Text>
                      <FlatList data={data} keyExtractor={i => i.id.toString()} renderItem={({ item }) => (
                        <View style={styles.card}>
                          <Text style={styles.cardTitle}>{item.title}</Text>
                          <Text style={styles.cardBody} numberOfLines={2}>{item.body}</Text>
                        </View>
                      )} />
                    </View>
                  );
                }

                const styles = StyleSheet.create({
                  container: { flex: 1, backgroundColor: '#1a1a2e', paddingTop: 60 },
                  center: { flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: '#1a1a2e' },
                  title: { color: '#fff', fontSize: 28, fontWeight: 'bold', marginBottom: 16, paddingHorizontal: 20 },
                  card: { backgroundColor: '#2a2a3e', marginHorizontal: 20, marginBottom: 10, padding: 16, borderRadius: 12 },
                  cardTitle: { color: '#00d97e', fontSize: 16, fontWeight: '600', marginBottom: 6 },
                  cardBody: { color: '#aaa', fontSize: 14 },
                });
                """
            }
        }

        var iconName: String {
            switch self {
            case .blank: return "doc"
            case .helloWorld: return "hand.wave"
            case .navigation: return "arrow.triangle.branch"
            case .todoApp: return "checklist"
            case .apiExample: return "network"
            }
        }

        var description: String {
            switch self {
            case .blank: return "Empty project"
            case .helloWorld: return "Counter with state"
            case .navigation: return "Stack navigation"
            case .todoApp: return "CRUD todo list"
            case .apiExample: return "Fetch & display API data"
            }
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        templateType: TemplateType = .blank,
        snackID: String? = nil,
        createdAt: Date = Date(),
        lastOpenedAt: Date = Date(),
        files: [SandboxFile] = []
    ) {
        self.id = id
        self.name = name
        self.templateType = templateType
        self.snackID = snackID
        self.createdAt = createdAt
        self.lastOpenedAt = lastOpenedAt
        self.files = files
    }
}

nonisolated struct SandboxFile: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var name: String
    var content: String
    var language: String

    init(id: UUID = UUID(), name: String, content: String, language: String = "javascript") {
        self.id = id
        self.name = name
        self.content = content
        self.language = language
    }
}
