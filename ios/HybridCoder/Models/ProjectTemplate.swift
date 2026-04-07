import Foundation
import SwiftUI

nonisolated struct ProjectTemplate: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let category: Category
    let iconName: String
    let accentColor: Color
    let files: [TemplateFile]

    nonisolated enum Category: String, CaseIterable, Sendable, Hashable {
        case starter = "Starter"
        case ui = "UI Patterns"
        case data = "Data & API"
        case fullApp = "Full Apps"

        var iconName: String {
            switch self {
            case .starter: return "sparkles"
            case .ui: return "paintbrush"
            case .data: return "externaldrive.connected.to.line.below"
            case .fullApp: return "app.badge.checkmark"
            }
        }
    }

    nonisolated struct TemplateFile: Sendable, Hashable {
        let name: String
        let content: String
        let language: String

        init(name: String, content: String, language: String = "javascript") {
            self.name = name
            self.content = content
            self.language = language
        }
    }

    var templateType: SandboxProject.TemplateType {
        switch id {
        case "blank": return .blank
        case "hello_world": return .helloWorld
        case "navigation": return .navigation
        case "todo_app": return .todoApp
        case "api_example": return .apiExample
        default: return .blank
        }
    }
}

extension ProjectTemplate {
    static let all: [ProjectTemplate] = starters + uiPatterns + dataTemplates + fullApps

    static func grouped() -> [(Category, [ProjectTemplate])] {
        Category.allCases.compactMap { category in
            let templates = all.filter { $0.category == category }
            return templates.isEmpty ? nil : (category, templates)
        }
    }

    static let starters: [ProjectTemplate] = [
        ProjectTemplate(
            id: "blank",
            name: "Blank",
            subtitle: "Empty canvas to start from scratch",
            category: .starter,
            iconName: "doc",
            accentColor: .gray,
            files: [
                TemplateFile(name: "App.js", content: SandboxProject.TemplateType.blank.defaultCode)
            ]
        ),
        ProjectTemplate(
            id: "hello_world",
            name: "Hello World",
            subtitle: "Interactive counter with state hooks",
            category: .starter,
            iconName: "hand.wave",
            accentColor: .green,
            files: [
                TemplateFile(name: "App.js", content: SandboxProject.TemplateType.helloWorld.defaultCode)
            ]
        ),
    ]

    static let uiPatterns: [ProjectTemplate] = [
        ProjectTemplate(
            id: "navigation",
            name: "Stack Navigation",
            subtitle: "Multi-screen flow with React Navigation",
            category: .ui,
            iconName: "arrow.triangle.branch",
            accentColor: .blue,
            files: [
                TemplateFile(name: "App.js", content: SandboxProject.TemplateType.navigation.defaultCode)
            ]
        ),
        ProjectTemplate(
            id: "tab_layout",
            name: "Tab Layout",
            subtitle: "Bottom tab bar with multiple screens",
            category: .ui,
            iconName: "rectangle.split.3x1",
            accentColor: .purple,
            files: [
                TemplateFile(name: "App.js", content: tabLayoutCode)
            ]
        ),
        ProjectTemplate(
            id: "form_input",
            name: "Form & Input",
            subtitle: "Text inputs, validation, keyboard handling",
            category: .ui,
            iconName: "rectangle.and.pencil.and.ellipsis",
            accentColor: .orange,
            files: [
                TemplateFile(name: "App.js", content: formInputCode)
            ]
        ),
    ]

    static let dataTemplates: [ProjectTemplate] = [
        ProjectTemplate(
            id: "api_example",
            name: "REST API",
            subtitle: "Fetch, display, and paginate remote data",
            category: .data,
            iconName: "network",
            accentColor: .cyan,
            files: [
                TemplateFile(name: "App.js", content: SandboxProject.TemplateType.apiExample.defaultCode)
            ]
        ),
        ProjectTemplate(
            id: "async_storage",
            name: "Local Storage",
            subtitle: "Persist data with AsyncStorage",
            category: .data,
            iconName: "internaldrive",
            accentColor: .mint,
            files: [
                TemplateFile(name: "App.js", content: asyncStorageCode)
            ]
        ),
    ]

    static let fullApps: [ProjectTemplate] = [
        ProjectTemplate(
            id: "todo_app",
            name: "Todo App",
            subtitle: "Full CRUD with add, toggle, delete",
            category: .fullApp,
            iconName: "checklist",
            accentColor: .green,
            files: [
                TemplateFile(name: "App.js", content: SandboxProject.TemplateType.todoApp.defaultCode)
            ]
        ),
        ProjectTemplate(
            id: "notes_app",
            name: "Notes App",
            subtitle: "Create, edit, and search notes",
            category: .fullApp,
            iconName: "note.text",
            accentColor: .yellow,
            files: [
                TemplateFile(name: "App.js", content: notesAppCode)
            ]
        ),
    ]
}

private let tabLayoutCode = """
import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { NavigationContainer } from '@react-navigation/native';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';

const Tab = createBottomTabNavigator();

function HomeScreen() {
  return (
    <View style={styles.container}>
      <Text style={styles.emoji}>🏠</Text>
      <Text style={styles.title}>Home</Text>
      <Text style={styles.subtitle}>Welcome back!</Text>
    </View>
  );
}

function SearchScreen() {
  return (
    <View style={styles.container}>
      <Text style={styles.emoji}>🔍</Text>
      <Text style={styles.title}>Search</Text>
      <Text style={styles.subtitle}>Find anything</Text>
    </View>
  );
}

function ProfileScreen() {
  return (
    <View style={styles.container}>
      <Text style={styles.emoji}>👤</Text>
      <Text style={styles.title}>Profile</Text>
      <Text style={styles.subtitle}>Your settings</Text>
    </View>
  );
}

export default function App() {
  return (
    <NavigationContainer>
      <Tab.Navigator
        screenOptions={{
          headerStyle: { backgroundColor: '#1a1a2e' },
          headerTintColor: '#fff',
          tabBarStyle: { backgroundColor: '#1a1a2e', borderTopColor: '#2a2a3e' },
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

const styles = StyleSheet.create({
  container: { flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: '#1a1a2e' },
  emoji: { fontSize: 48, marginBottom: 16 },
  title: { color: '#fff', fontSize: 28, fontWeight: 'bold', marginBottom: 8 },
  subtitle: { color: '#aaa', fontSize: 16 },
});
"""

private let formInputCode = """
import React, { useState } from 'react';
import { View, Text, TextInput, TouchableOpacity, ScrollView, KeyboardAvoidingView, Platform, StyleSheet } from 'react-native';

export default function App() {
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [message, setMessage] = useState('');
  const [submitted, setSubmitted] = useState(false);
  const [errors, setErrors] = useState({});

  const validate = () => {
    const errs = {};
    if (!name.trim()) errs.name = 'Name is required';
    if (!email.includes('@')) errs.email = 'Valid email required';
    if (!message.trim()) errs.message = 'Message is required';
    setErrors(errs);
    return Object.keys(errs).length === 0;
  };

  const handleSubmit = () => {
    if (validate()) {
      setSubmitted(true);
      setTimeout(() => setSubmitted(false), 3000);
      setName(''); setEmail(''); setMessage('');
    }
  };

  return (
    <KeyboardAvoidingView style={styles.flex} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <ScrollView style={styles.container} contentContainerStyle={styles.content}>
        <Text style={styles.title}>Contact Form</Text>

        <Text style={styles.label}>Name</Text>
        <TextInput style={[styles.input, errors.name && styles.inputError]} value={name} onChangeText={setName} placeholder="Your name" placeholderTextColor="#555" />
        {errors.name && <Text style={styles.error}>{errors.name}</Text>}

        <Text style={styles.label}>Email</Text>
        <TextInput style={[styles.input, errors.email && styles.inputError]} value={email} onChangeText={setEmail} placeholder="you@example.com" placeholderTextColor="#555" keyboardType="email-address" autoCapitalize="none" />
        {errors.email && <Text style={styles.error}>{errors.email}</Text>}

        <Text style={styles.label}>Message</Text>
        <TextInput style={[styles.input, styles.textArea, errors.message && styles.inputError]} value={message} onChangeText={setMessage} placeholder="Write something..." placeholderTextColor="#555" multiline numberOfLines={4} />
        {errors.message && <Text style={styles.error}>{errors.message}</Text>}

        <TouchableOpacity style={styles.button} onPress={handleSubmit}>
          <Text style={styles.buttonText}>Submit</Text>
        </TouchableOpacity>

        {submitted && <Text style={styles.success}>Sent successfully!</Text>}
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  flex: { flex: 1 },
  container: { flex: 1, backgroundColor: '#1a1a2e' },
  content: { padding: 24, paddingTop: 60 },
  title: { color: '#fff', fontSize: 28, fontWeight: 'bold', marginBottom: 24 },
  label: { color: '#aaa', fontSize: 14, fontWeight: '600', marginBottom: 6, marginTop: 16 },
  input: { backgroundColor: '#2a2a3e', color: '#fff', padding: 14, borderRadius: 10, fontSize: 16, borderWidth: 1, borderColor: 'transparent' },
  inputError: { borderColor: '#ff4444' },
  textArea: { minHeight: 100, textAlignVertical: 'top' },
  error: { color: '#ff4444', fontSize: 12, marginTop: 4 },
  button: { backgroundColor: '#00d97e', padding: 16, borderRadius: 12, alignItems: 'center', marginTop: 24 },
  buttonText: { color: '#1a1a2e', fontSize: 18, fontWeight: '700' },
  success: { color: '#00d97e', fontSize: 16, textAlign: 'center', marginTop: 16, fontWeight: '600' },
});
"""

private let asyncStorageCode = """
import React, { useState, useEffect } from 'react';
import { View, Text, TextInput, TouchableOpacity, FlatList, StyleSheet } from 'react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';

export default function App() {
  const [items, setItems] = useState([]);
  const [text, setText] = useState('');

  useEffect(() => { loadItems(); }, []);

  const loadItems = async () => {
    try {
      const stored = await AsyncStorage.getItem('saved_items');
      if (stored) setItems(JSON.parse(stored));
    } catch (e) { console.log('Load error', e); }
  };

  const saveItems = async (newItems) => {
    try {
      await AsyncStorage.setItem('saved_items', JSON.stringify(newItems));
      setItems(newItems);
    } catch (e) { console.log('Save error', e); }
  };

  const addItem = () => {
    if (!text.trim()) return;
    const newItems = [{ id: Date.now().toString(), text: text.trim() }, ...items];
    saveItems(newItems);
    setText('');
  };

  const removeItem = (id) => {
    saveItems(items.filter(i => i.id !== id));
  };

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Saved Items</Text>
      <Text style={styles.subtitle}>{items.length} items persisted locally</Text>

      <View style={styles.inputRow}>
        <TextInput style={styles.input} value={text} onChangeText={setText} placeholder="Add item..." placeholderTextColor="#555" onSubmitEditing={addItem} />
        <TouchableOpacity style={styles.addBtn} onPress={addItem}>
          <Text style={styles.addText}>+</Text>
        </TouchableOpacity>
      </View>

      <FlatList data={items} keyExtractor={i => i.id} renderItem={({ item }) => (
        <TouchableOpacity style={styles.item} onLongPress={() => removeItem(item.id)}>
          <Text style={styles.itemText}>{item.text}</Text>
          <Text style={styles.hint}>Hold to remove</Text>
        </TouchableOpacity>
      )} ListEmptyComponent={<Text style={styles.empty}>No saved items yet</Text>} />
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#1a1a2e', paddingTop: 60, paddingHorizontal: 20 },
  title: { color: '#fff', fontSize: 28, fontWeight: 'bold' },
  subtitle: { color: '#aaa', fontSize: 14, marginBottom: 20, marginTop: 4 },
  inputRow: { flexDirection: 'row', marginBottom: 20 },
  input: { flex: 1, backgroundColor: '#2a2a3e', color: '#fff', padding: 14, borderRadius: 10, fontSize: 16 },
  addBtn: { backgroundColor: '#00d97e', width: 50, marginLeft: 10, borderRadius: 10, justifyContent: 'center', alignItems: 'center' },
  addText: { color: '#1a1a2e', fontSize: 24, fontWeight: 'bold' },
  item: { backgroundColor: '#2a2a3e', padding: 16, borderRadius: 10, marginBottom: 8, flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  itemText: { color: '#fff', fontSize: 16, flex: 1 },
  hint: { color: '#555', fontSize: 11 },
  empty: { color: '#555', fontSize: 16, textAlign: 'center', marginTop: 40 },
});
"""

private let notesAppCode = """
import React, { useState } from 'react';
import { View, Text, TextInput, TouchableOpacity, FlatList, StyleSheet } from 'react-native';

export default function App() {
  const [notes, setNotes] = useState([]);
  const [search, setSearch] = useState('');
  const [editingId, setEditingId] = useState(null);
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');

  const filtered = notes.filter(n =>
    n.title.toLowerCase().includes(search.toLowerCase()) ||
    n.body.toLowerCase().includes(search.toLowerCase())
  );

  const saveNote = () => {
    if (!title.trim()) return;
    if (editingId) {
      setNotes(notes.map(n => n.id === editingId ? { ...n, title, body, updatedAt: new Date().toLocaleString() } : n));
    } else {
      setNotes([{ id: Date.now().toString(), title, body, updatedAt: new Date().toLocaleString() }, ...notes]);
    }
    setTitle(''); setBody(''); setEditingId(null);
  };

  const editNote = (note) => {
    setEditingId(note.id); setTitle(note.title); setBody(note.body);
  };

  const deleteNote = (id) => {
    setNotes(notes.filter(n => n.id !== id));
    if (editingId === id) { setEditingId(null); setTitle(''); setBody(''); }
  };

  return (
    <View style={styles.container}>
      <Text style={styles.header}>Notes</Text>

      <TextInput style={styles.search} value={search} onChangeText={setSearch} placeholder="Search notes..." placeholderTextColor="#555" />

      <View style={styles.editor}>
        <TextInput style={styles.titleInput} value={title} onChangeText={setTitle} placeholder="Note title" placeholderTextColor="#555" />
        <TextInput style={styles.bodyInput} value={body} onChangeText={setBody} placeholder="Write something..." placeholderTextColor="#555" multiline />
        <TouchableOpacity style={styles.saveBtn} onPress={saveNote}>
          <Text style={styles.saveBtnText}>{editingId ? 'Update' : 'Save'}</Text>
        </TouchableOpacity>
      </View>

      <FlatList data={filtered} keyExtractor={i => i.id} renderItem={({ item }) => (
        <TouchableOpacity style={styles.card} onPress={() => editNote(item)} onLongPress={() => deleteNote(item.id)}>
          <Text style={styles.cardTitle}>{item.title}</Text>
          <Text style={styles.cardBody} numberOfLines={2}>{item.body}</Text>
          <Text style={styles.cardDate}>{item.updatedAt}</Text>
        </TouchableOpacity>
      )} />
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#1a1a2e', paddingTop: 60, paddingHorizontal: 20 },
  header: { color: '#fff', fontSize: 32, fontWeight: 'bold', marginBottom: 16 },
  search: { backgroundColor: '#2a2a3e', color: '#fff', padding: 12, borderRadius: 10, fontSize: 15, marginBottom: 16 },
  editor: { backgroundColor: '#2a2a3e', borderRadius: 12, padding: 14, marginBottom: 20 },
  titleInput: { color: '#fff', fontSize: 18, fontWeight: '600', marginBottom: 8 },
  bodyInput: { color: '#ccc', fontSize: 15, minHeight: 60, textAlignVertical: 'top' },
  saveBtn: { backgroundColor: '#00d97e', padding: 12, borderRadius: 10, alignItems: 'center', marginTop: 10 },
  saveBtnText: { color: '#1a1a2e', fontSize: 16, fontWeight: '700' },
  card: { backgroundColor: '#2a2a3e', padding: 14, borderRadius: 10, marginBottom: 8 },
  cardTitle: { color: '#fff', fontSize: 16, fontWeight: '600', marginBottom: 4 },
  cardBody: { color: '#aaa', fontSize: 14, marginBottom: 6 },
  cardDate: { color: '#555', fontSize: 11 },
});
"""
