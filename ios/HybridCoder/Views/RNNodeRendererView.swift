import SwiftUI

struct RNNodeRendererView: View {
    let node: RNComponentNode
    let styles: [String: [String: String]]
    let stateManager: RNComponentStateManager
    let screenID: String
    let onNavigate: ((String) -> Void)?

    init(
        node: RNComponentNode,
        styles: [String: [String: String]],
        stateManager: RNComponentStateManager,
        screenID: String = "",
        onNavigate: ((String) -> Void)? = nil
    ) {
        self.node = node
        self.styles = styles
        self.stateManager = stateManager
        self.screenID = screenID
        self.onNavigate = onNavigate
    }

    var body: some View {
        RNNodeCell(node: node, styles: styles, stateManager: stateManager, screenID: screenID, onNavigate: onNavigate)
    }
}

private struct RNNodeCell: View {
    let node: RNComponentNode
    let styles: [String: [String: String]]
    let stateManager: RNComponentStateManager
    let screenID: String
    let onNavigate: ((String) -> Void)?

    var body: some View {
        AnyView(renderNode(node))
    }

    @MainActor
    private func renderNode(_ node: RNComponentNode) -> AnyView {
        switch node.type {
        case .view, .safeAreaView, .keyboardAvoidingView, .fragment, .unknown:
            return AnyView(ContainerCell(node: node, styles: styles, stateManager: stateManager, screenID: screenID, onNavigate: onNavigate))
        case .text:
            return AnyView(TextCell(node: node, stateManager: stateManager, screenID: screenID))
        case .image:
            return AnyView(ImageCell(node: node))
        case .scrollView:
            return AnyView(ScrollCell(node: node, styles: styles, stateManager: stateManager, screenID: screenID, onNavigate: onNavigate))
        case .flatList, .sectionList:
            return AnyView(ListCell(node: node, styles: styles, stateManager: stateManager, screenID: screenID, onNavigate: onNavigate))
        case .touchableOpacity, .pressable:
            return AnyView(TouchableCell(node: node, styles: styles, stateManager: stateManager, screenID: screenID, onNavigate: onNavigate))
        case .textInput:
            return AnyView(InteractiveInputCell(node: node, stateManager: stateManager, screenID: screenID))
        case .button:
            return AnyView(InteractiveButtonCell(node: node, stateManager: stateManager, screenID: screenID, onNavigate: onNavigate))
        case .activityIndicator:
            return AnyView(ActivityCell(node: node))
        case .switchComponent:
            return AnyView(InteractiveSwitchCell(node: node, stateManager: stateManager, screenID: screenID))
        case .statusBar:
            return AnyView(EmptyView())
        case .navigationContainer:
            return AnyView(ChildrenCell(node: node, styles: styles, stateManager: stateManager, screenID: screenID, onNavigate: onNavigate))
        case .stackNavigator, .tabNavigator:
            return AnyView(NavigatorCell(node: node, styles: styles, stateManager: stateManager, screenID: screenID, onNavigate: onNavigate))
        case .stackScreen, .tabScreen:
            return AnyView(ChildrenCell(node: node, styles: styles, stateManager: stateManager, screenID: screenID, onNavigate: onNavigate))
        case .modal:
            return AnyView(ChildrenCell(node: node, styles: styles, stateManager: stateManager, screenID: screenID, onNavigate: onNavigate))
        }
    }
}

private struct ContainerCell: View {
    let node: RNComponentNode
    let styles: [String: [String: String]]
    let stateManager: RNComponentStateManager
    let screenID: String
    let onNavigate: ((String) -> Void)?

    var body: some View {
        let s = node.resolvedStyles
        let isRow = s["flexDirection"] == "row"
        let hasFlex = s["flex"] == "1"
        let justify = s["justifyContent"] ?? ""
        let align = s["alignItems"] ?? ""

        let content = Group {
            if isRow {
                HStack(spacing: gapValue(s)) {
                    ForEach(node.children) { child in
                        RNNodeCell(node: child, styles: styles, stateManager: stateManager, screenID: screenID, onNavigate: onNavigate)
                    }
                }
            } else {
                VStack(alignment: hAlign(align), spacing: gapValue(s)) {
                    if justify == "center" || justify == "space-around" { Spacer(minLength: 0) }
                    ForEach(node.children) { child in
                        RNNodeCell(node: child, styles: styles, stateManager: stateManager, screenID: screenID, onNavigate: onNavigate)
                    }
                    if justify == "center" || justify == "space-between" || justify == "space-around" { Spacer(minLength: 0) }
                }
            }
        }

        applyContainerStyle(content, s: s, hasFlex: hasFlex)
    }

    @ViewBuilder
    private func applyContainerStyle<C: View>(_ content: C, s: [String: String], hasFlex: Bool) -> some View {
        let resolved = ContainerStyleValues(s: s, hasFlex: hasFlex)
        let padded = content
            .padding(.horizontal, resolved.padH)
            .padding(.vertical, resolved.padV)
            .padding(.top, resolved.padT)
            .padding(.bottom, resolved.padB)
            .padding(.leading, resolved.padL)
            .padding(.trailing, resolved.padR)
            .padding(resolved.pad)

        let framed = padded
            .frame(width: resolved.w, height: resolved.h)
            .frame(minHeight: resolved.minH)
            .frame(maxWidth: hasFlex ? .infinity : nil, maxHeight: hasFlex ? .infinity : nil)

        let styled = framed
            .background(resolved.bg)
            .clipShape(.rect(cornerRadius: resolved.br))
            .overlay {
                if resolved.bw > 0 {
                    RoundedRectangle(cornerRadius: resolved.br)
                        .strokeBorder(resolved.bc, lineWidth: resolved.bw)
                }
            }
            .opacity(resolved.opacity)

        styled
            .padding(.horizontal, resolved.mH)
            .padding(.vertical, resolved.mV)
            .padding(.top, resolved.mT)
            .padding(.bottom, resolved.mB)
    }

    private func gapValue(_ s: [String: String]) -> CGFloat {
        cgFloat(s["gap"]) ?? 0
    }

    private func hAlign(_ val: String) -> HorizontalAlignment {
        switch val {
        case "center": return .center
        case "flex-end": return .trailing
        default: return .leading
        }
    }
}

private struct ContainerStyleValues {
    let padH: CGFloat
    let padV: CGFloat
    let padT: CGFloat
    let padB: CGFloat
    let padL: CGFloat
    let padR: CGFloat
    let pad: CGFloat
    let mH: CGFloat
    let mV: CGFloat
    let mT: CGFloat
    let mB: CGFloat
    let br: CGFloat
    let bg: Color
    let bw: CGFloat
    let bc: Color
    let w: CGFloat?
    let h: CGFloat?
    let minH: CGFloat?
    let opacity: Double

    init(s: [String: String], hasFlex: Bool) {
        padH = cgFloat(s["paddingHorizontal"]) ?? 0
        padV = cgFloat(s["paddingVertical"]) ?? 0
        padT = cgFloat(s["paddingTop"]) ?? 0
        padB = cgFloat(s["paddingBottom"]) ?? 0
        padL = cgFloat(s["paddingLeft"]) ?? 0
        padR = cgFloat(s["paddingRight"]) ?? 0
        pad = cgFloat(s["padding"]) ?? 0
        mH = cgFloat(s["marginHorizontal"]) ?? 0
        mV = cgFloat(s["marginVertical"]) ?? 0
        mT = cgFloat(s["marginTop"]) ?? 0
        mB = cgFloat(s["marginBottom"]) ?? 0
        br = cgFloat(s["borderRadius"]) ?? 0
        bg = s["backgroundColor"].map { RNStyleResolver.resolveColor($0) } ?? .clear
        bw = cgFloat(s["borderWidth"]) ?? 0
        bc = s["borderColor"].map { RNStyleResolver.resolveColor($0) } ?? Theme.border
        w = cgFloat(s["width"])
        h = cgFloat(s["height"])
        minH = cgFloat(s["minHeight"])
        opacity = s["opacity"].flatMap { Double($0) } ?? 1.0
    }
}

private struct TextCell: View {
    let node: RNComponentNode
    let stateManager: RNComponentStateManager
    let screenID: String

    var body: some View {
        let s = node.resolvedStyles
        let text = resolveText(node)
        let color = s["color"].map { RNStyleResolver.resolveColor($0) } ?? .white
        let size = cgFloat(s["fontSize"]) ?? 16
        let weight = s["fontWeight"].map { RNStyleResolver.resolveFontWeight($0) } ?? .regular
        let mB = cgFloat(s["marginBottom"])
        let mT = cgFloat(s["marginTop"])
        let strike = s["textDecorationLine"] == "line-through"
        let underline = s["textDecorationLine"] == "underline"
        let textAlign = s["textAlign"].map { RNStyleResolver.resolveTextAlignment($0) } ?? .leading
        let lineHeight = cgFloat(s["lineHeight"])
        let letterSpacing = cgFloat(s["letterSpacing"])
        let opacity = s["opacity"].flatMap { Double($0) }
        let numberOfLines = s["numberOfLines"].flatMap { Int($0) }

        Text(text)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(color)
            .strikethrough(strike)
            .underline(underline)
            .multilineTextAlignment(textAlign)
            .lineSpacing(lineHeight.map { $0 - size } ?? 0)
            .tracking(letterSpacing ?? 0)
            .lineLimit(numberOfLines)
            .opacity(opacity ?? 1.0)
            .padding(.bottom, mB ?? 0)
            .padding(.top, mT ?? 0)
    }

    private func resolveText(_ node: RNComponentNode) -> String {
        if let t = node.textContent {
            if t.contains("${") || t.contains("{") {
                let stateKey = extractStateReference(t)
                if let stateKey {
                    let stored = stateManager.getTextInput(componentID: screenID, inputKey: stateKey)
                    if !stored.isEmpty { return stored }
                    let counter = stateManager.getCounter(componentID: screenID, counterKey: stateKey)
                    if counter != 0 { return "\(counter)" }
                }
            }
            return cleanExpressionText(t)
        }
        return node.children.compactMap { child -> String? in
            if let t = child.textContent { return cleanExpressionText(t) }
            return nil
        }.joined()
    }

    private func extractStateReference(_ text: String) -> String? {
        let patterns = [
            #"\$\{(\w+)\}"#,
            #"\{(\w+)\}"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: range),
               let nameRange = Range(match.range(at: 1), in: text) {
                return String(text[nameRange])
            }
        }
        return nil
    }

    private func cleanExpressionText(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "`", with: "")
        let templatePattern = #"\$\{[^}]+\}"#
        if let regex = try? NSRegularExpression(pattern: templatePattern) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "…")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ImageCell: View {
    let node: RNComponentNode

    var body: some View {
        let s = node.resolvedStyles
        let w = cgFloat(s["width"])
        let h = cgFloat(s["height"])
        let br = cgFloat(s["borderRadius"]) ?? 0
        let tint = s["tintColor"].map { RNStyleResolver.resolveColor($0) }
        let resizeMode = node.props["resizeMode"]?.stringValue ?? "cover"

        let sourceURI = extractImageURI(node)

        Group {
            if let sourceURI, sourceURI.hasPrefix("http") {
                Color(Theme.cardBg)
                    .frame(width: w, height: h ?? 120)
                    .overlay {
                        AsyncImage(url: URL(string: sourceURI)) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: resizeMode == "contain" ? .fit : .fill)
                                    .allowsHitTesting(false)
                            case .failure:
                                Image(systemName: "photo.badge.exclamationmark")
                                    .font(.title2)
                                    .foregroundStyle(Theme.dimText)
                            default:
                                ProgressView().tint(Theme.accent)
                            }
                        }
                    }
                    .clipShape(.rect(cornerRadius: br))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 24))
                    .foregroundStyle(tint ?? Theme.dimText)
                    .frame(width: w, height: h)
                    .background(Theme.cardBg)
                    .clipShape(.rect(cornerRadius: br))
            }
        }
    }

    private func extractImageURI(_ node: RNComponentNode) -> String? {
        if let source = node.props["source"]?.stringValue {
            let uriPattern = #"uri\s*:\s*['"]([^'"]+)['"]"#
            if let regex = try? NSRegularExpression(pattern: uriPattern),
               let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
               let range = Range(match.range(at: 1), in: source) {
                return String(source[range])
            }
            if source.hasPrefix("http") { return source }
        }
        return nil
    }
}

private struct ScrollCell: View {
    let node: RNComponentNode
    let styles: [String: [String: String]]
    let stateManager: RNComponentStateManager
    let screenID: String
    let onNavigate: ((String) -> Void)?

    var body: some View {
        let s = node.resolvedStyles
        let bg = s["backgroundColor"].map { RNStyleResolver.resolveColor($0) }
        let padH = cgFloat(s["paddingHorizontal"]) ?? 0
        let padV = cgFloat(s["paddingVertical"]) ?? 0
        let isHorizontal = node.props["horizontal"]?.boolValue == true

        if isHorizontal {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(node.children) { child in
                        RNNodeCell(node: child, styles: styles, stateManager: stateManager, screenID: screenID, onNavigate: onNavigate)
                    }
                }
                .padding(.horizontal, padH)
                .padding(.vertical, padV)
            }
            .background(bg ?? .clear)
        } else {
            ScrollView(showsIndicators: true) {
                VStack(spacing: 0) {
                    ForEach(node.children) { child in
                        RNNodeCell(node: child, styles: styles, stateManager: stateManager, screenID: screenID, onNavigate: onNavigate)
                    }
                }
                .padding(.horizontal, padH)
                .padding(.vertical, padV)
            }
            .background(bg ?? .clear)
        }
    }
}

private struct ListCell: View {
    let node: RNComponentNode
    let styles: [String: [String: String]]
    let stateManager: RNComponentStateManager
    let screenID: String
    let onNavigate: ((String) -> Void)?

    var body: some View {
        let s = node.resolvedStyles
        let bg = s["backgroundColor"].map { RNStyleResolver.resolveColor($0) }
        let listType = node.type == .sectionList ? "SectionList" : "FlatList"
        let itemCount = node.children.count
        let selectedIdx = stateManager.getSelectedIndex(componentID: screenID, listKey: node.id.uuidString)

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.accent.opacity(0.6))
                Text("\(listType) (\(itemCount) items)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.dimText)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.accent.opacity(0.06), in: .rect(cornerRadius: 6))

            ForEach(Array(node.children.enumerated()), id: \.element.id) { index, child in
                Button {
                    stateManager.setSelectedIndex(componentID: screenID, listKey: node.id.uuidString, index: index)
                } label: {
                    RNNodeCell(node: child, styles: styles, stateManager: stateManager, screenID: screenID, onNavigate: onNavigate)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(selectedIdx == index ? Theme.accent.opacity(0.08) : .clear)
                        .clipShape(.rect(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .background(bg ?? .clear)
    }
}

private struct TouchableCell: View {
    let node: RNComponentNode
    let styles: [String: [String: String]]
    let stateManager: RNComponentStateManager
    let screenID: String
    let onNavigate: ((String) -> Void)?
    @State private var isPressed: Bool = false

    var body: some View {
        let s = node.resolvedStyles
        let bg = s["backgroundColor"].map { RNStyleResolver.resolveColor($0) }
        let br = cgFloat(s["borderRadius"]) ?? 0
        let padH = cgFloat(s["paddingHorizontal"]) ?? 0
        let padV = cgFloat(s["paddingVertical"]) ?? 0
        let pad = cgFloat(s["padding"]) ?? 0
        let mL = cgFloat(s["marginLeft"]) ?? 0
        let mR = cgFloat(s["marginRight"]) ?? 0
        let mB = cgFloat(s["marginBottom"]) ?? 0
        let mT = cgFloat(s["marginTop"]) ?? 0
        let mH = cgFloat(s["marginHorizontal"]) ?? 0
        let w = cgFloat(s["width"])
        let h = cgFloat(s["height"])
        let alignCenter = s["alignItems"] == "center"
        let justCenter = s["justifyContent"] == "center"
        let isRow = s["flexDirection"] == "row"
        let hasFlex = s["flex"] == "1"
        let bw = cgFloat(s["borderWidth"])
        let bc = s["borderColor"].map { RNStyleResolver.resolveColor($0) }
        let activeOpacity = node.props["activeOpacity"]?.numberValue ?? (node.type == .touchableOpacity ? 0.7 : 1.0)

        Button {
            handlePress()
        } label: {
            Group {
                if isRow {
                    HStack(spacing: cgFloat(s["gap"]) ?? 0) {
                        ForEach(node.children) { child in
                            RNNodeCell(node: child, styles: styles, stateManager: stateManager, screenID: screenID, onNavigate: onNavigate)
                        }
                    }
                } else {
                    VStack(spacing: cgFloat(s["gap"]) ?? 0) {
                        if justCenter { Spacer(minLength: 0) }
                        ForEach(node.children) { child in
                            RNNodeCell(node: child, styles: styles, stateManager: stateManager, screenID: screenID, onNavigate: onNavigate)
                        }
                        if justCenter { Spacer(minLength: 0) }
                    }
                }
            }
            .frame(maxWidth: alignCenter || hasFlex ? .infinity : nil)
            .padding(.horizontal, padH)
            .padding(.vertical, padV)
            .padding(pad)
            .frame(width: w, height: h)
            .background(bg ?? .clear)
            .clipShape(.rect(cornerRadius: br))
            .overlay {
                if let bw, bw > 0 {
                    RoundedRectangle(cornerRadius: br)
                        .strokeBorder(bc ?? Theme.border, lineWidth: bw)
                }
            }
        }
        .buttonStyle(TouchableButtonStyle(activeOpacity: activeOpacity))
        .padding(.leading, mL)
        .padding(.trailing, mR)
        .padding(.bottom, mB)
        .padding(.top, mT)
        .padding(.horizontal, mH)
        .sensoryFeedback(.selection, trigger: isPressed)
    }

    private func handlePress() {
        isPressed.toggle()
        if let target = extractNavTarget(node) {
            onNavigate?(target)
            return
        }
        if let onPressExpr = node.props["onPress"]?.stringValue {
            handleAsyncStorageAction(onPressExpr)
        }
    }

    private func handleAsyncStorageAction(_ expr: String) {
        let setPattern = #"AsyncStorage\.setItem\(\s*['"]([^'"]+)['"]\s*,\s*['"]?([^'")\s]+)['"]?\s*\)"#
        if let regex = try? NSRegularExpression(pattern: setPattern),
           let match = regex.firstMatch(in: expr, range: NSRange(expr.startIndex..., in: expr)),
           let keyRange = Range(match.range(at: 1), in: expr),
           let valRange = Range(match.range(at: 2), in: expr) {
            let key = String(expr[keyRange])
            let val = String(expr[valRange])
            Task {
                await stateManager.setAsyncStorageValue(key: key, value: val)
            }
            return
        }

        let removePattern = #"AsyncStorage\.removeItem\(\s*['"]([^'"]+)['"]\s*\)"#
        if let regex = try? NSRegularExpression(pattern: removePattern),
           let match = regex.firstMatch(in: expr, range: NSRange(expr.startIndex..., in: expr)),
           let keyRange = Range(match.range(at: 1), in: expr) {
            let key = String(expr[keyRange])
            Task {
                await stateManager.setAsyncStorageValue(key: key, value: "")
            }
            return
        }

        let incrementPattern = #"set(\w+)\s*\(\s*(\w+)\s*\+\s*1\s*\)"#
        if let regex = try? NSRegularExpression(pattern: incrementPattern),
           let match = regex.firstMatch(in: expr, range: NSRange(expr.startIndex..., in: expr)),
           let nameRange = Range(match.range(at: 1), in: expr) {
            let name = String(expr[nameRange]).lowercasedFirst
            stateManager.incrementCounter(componentID: screenID, counterKey: name)
            return
        }

        let decrementPattern = #"set(\w+)\s*\(\s*(\w+)\s*-\s*1\s*\)"#
        if let regex = try? NSRegularExpression(pattern: decrementPattern),
           let match = regex.firstMatch(in: expr, range: NSRange(expr.startIndex..., in: expr)),
           let nameRange = Range(match.range(at: 1), in: expr) {
            let name = String(expr[nameRange]).lowercasedFirst
            stateManager.decrementCounter(componentID: screenID, counterKey: name)
            return
        }

        let setStatePattern = #"set(\w+)\s*\(\s*(!?\w+|['"][^'"]*['"])\s*\)"#
        if let regex = try? NSRegularExpression(pattern: setStatePattern),
           let match = regex.firstMatch(in: expr, range: NSRange(expr.startIndex..., in: expr)),
           let nameRange = Range(match.range(at: 1), in: expr),
           let valRange = Range(match.range(at: 2), in: expr) {
            let name = String(expr[nameRange]).lowercasedFirst
            let val = String(expr[valRange])
            if val.hasPrefix("!") {
                let current = stateManager.getToggle(componentID: screenID, toggleKey: name)
                stateManager.setToggle(componentID: screenID, toggleKey: name, value: !current)
            } else {
                stateManager.setTextInput(componentID: screenID, inputKey: name, value: val.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\"", with: ""))
            }
        }
    }

    private func extractNavTarget(_ node: RNComponentNode) -> String? {
        guard let expr = node.props["onPress"]?.stringValue else { return nil }
        let patterns = [
            #"navigate\(\s*['"](\w+)['"]\s*\)"#,
            #"push\(\s*['"](\w+)['"]\s*\)"#,
            #"router\.push\(\s*['"]([^'"]+)['"]\s*\)"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: expr, range: NSRange(expr.startIndex..., in: expr)),
                  let range = Range(match.range(at: 1), in: expr) else { continue }
            return String(expr[range])
        }
        return nil
    }
}

private struct TouchableButtonStyle: ButtonStyle {
    let activeOpacity: Double

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? activeOpacity : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

private struct InteractiveInputCell: View {
    let node: RNComponentNode
    let stateManager: RNComponentStateManager
    let screenID: String
    @State private var inputText: String = ""
    @State private var didLoadInitial: Bool = false

    var body: some View {
        let s = node.resolvedStyles
        let bg = s["backgroundColor"].map { RNStyleResolver.resolveColor($0) } ?? Theme.inputBg
        let size = cgFloat(s["fontSize"]) ?? 16
        let br = cgFloat(s["borderRadius"]) ?? 8
        let padH = cgFloat(s["paddingHorizontal"]) ?? cgFloat(s["padding"]) ?? 12
        let padV = cgFloat(s["paddingVertical"]) ?? cgFloat(s["padding"]) ?? 12
        let placeholder = node.props["placeholder"]?.stringValue ?? "Enter text…"
        let textColor = s["color"].map { RNStyleResolver.resolveColor($0) } ?? .white
        let bw = cgFloat(s["borderWidth"])
        let bc = s["borderColor"].map { RNStyleResolver.resolveColor($0) }
        let isSecure = node.props["secureTextEntry"]?.boolValue == true
        let isMultiline = node.props["multiline"]?.boolValue == true
        let maxLength = node.props["maxLength"]?.numberValue.map { Int($0) }
        let inputKey = node.props["testID"]?.stringValue ?? node.props["nativeID"]?.stringValue ?? node.id.uuidString

        VStack(spacing: 0) {
            if isMultiline {
                TextField(placeholder, text: $inputText, axis: .vertical)
                    .font(.system(size: size))
                    .foregroundStyle(textColor)
                    .lineLimit(3...6)
                    .padding(.horizontal, padH)
                    .padding(.vertical, padV)
            } else if isSecure {
                SecureField(placeholder, text: $inputText)
                    .font(.system(size: size))
                    .foregroundStyle(textColor)
                    .padding(.horizontal, padH)
                    .padding(.vertical, padV)
            } else {
                TextField(placeholder, text: $inputText)
                    .font(.system(size: size))
                    .foregroundStyle(textColor)
                    .padding(.horizontal, padH)
                    .padding(.vertical, padV)
            }
        }
        .background(bg, in: .rect(cornerRadius: br))
        .overlay {
            if let bw, bw > 0 {
                RoundedRectangle(cornerRadius: br)
                    .strokeBorder(bc ?? Theme.border, lineWidth: bw)
            }
        }
        .onAppear {
            if !didLoadInitial {
                inputText = stateManager.getTextInput(componentID: screenID, inputKey: inputKey)
                didLoadInitial = true
            }
        }
        .onChange(of: inputText) { _, newValue in
            var value = newValue
            if let maxLength, value.count > maxLength {
                value = String(value.prefix(maxLength))
                inputText = value
            }
            stateManager.setTextInput(componentID: screenID, inputKey: inputKey, value: value)

            if let storageKey = extractAsyncStorageKey(node) {
                Task {
                    await stateManager.setAsyncStorageValue(key: storageKey, value: value)
                }
            }
        }
    }

    private func extractAsyncStorageKey(_ node: RNComponentNode) -> String? {
        if let onChangeExpr = node.props["onChangeText"]?.stringValue {
            let pattern = #"AsyncStorage\.setItem\(\s*['"]([^'"]+)['"]\s*,"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: onChangeExpr, range: NSRange(onChangeExpr.startIndex..., in: onChangeExpr)),
               let range = Range(match.range(at: 1), in: onChangeExpr) {
                return String(onChangeExpr[range])
            }
        }
        return nil
    }
}

private struct InteractiveButtonCell: View {
    let node: RNComponentNode
    let stateManager: RNComponentStateManager
    let screenID: String
    let onNavigate: ((String) -> Void)?

    var body: some View {
        let title = node.props["title"]?.stringValue ?? "Button"
        let color = node.props["color"]?.stringValue.map { RNStyleResolver.resolveColor($0) } ?? Theme.accent
        let disabled = node.props["disabled"]?.boolValue ?? false

        Button(title) {
            if let onPressExpr = node.props["onPress"]?.stringValue {
                let navPatterns = [#"navigate\(\s*['"](\w+)['"]\s*\)"#, #"push\(\s*['"](\w+)['"]\s*\)"#]
                for pattern in navPatterns {
                    if let regex = try? NSRegularExpression(pattern: pattern),
                       let match = regex.firstMatch(in: onPressExpr, range: NSRange(onPressExpr.startIndex..., in: onPressExpr)),
                       let range = Range(match.range(at: 1), in: onPressExpr) {
                        onNavigate?(String(onPressExpr[range]))
                        return
                    }
                }
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(color)
        .disabled(disabled)
    }
}

private struct InteractiveSwitchCell: View {
    let node: RNComponentNode
    let stateManager: RNComponentStateManager
    let screenID: String
    @State private var isOn: Bool = false
    @State private var didLoadInitial: Bool = false

    var body: some View {
        let trackColor = node.props["trackColor"]?.stringValue.map { RNStyleResolver.resolveColor($0) }
        let toggleKey = node.props["testID"]?.stringValue ?? node.props["nativeID"]?.stringValue ?? node.id.uuidString

        Toggle("", isOn: $isOn)
            .labelsHidden()
            .tint(trackColor ?? Theme.accent)
            .onAppear {
                if !didLoadInitial {
                    isOn = stateManager.getToggle(componentID: screenID, toggleKey: toggleKey)
                    if let defaultVal = node.props["value"]?.boolValue {
                        if !didLoadInitial { isOn = defaultVal }
                    }
                    didLoadInitial = true
                }
            }
            .onChange(of: isOn) { _, newValue in
                stateManager.setToggle(componentID: screenID, toggleKey: toggleKey, value: newValue)
                if let storageKey = extractAsyncStorageToggleKey(node) {
                    Task {
                        await stateManager.setAsyncStorageValue(key: storageKey, value: newValue ? "true" : "false")
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: isOn)
    }

    private func extractAsyncStorageToggleKey(_ node: RNComponentNode) -> String? {
        if let onChangeExpr = node.props["onValueChange"]?.stringValue {
            let pattern = #"AsyncStorage\.setItem\(\s*['"]([^'"]+)['"]\s*,"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: onChangeExpr, range: NSRange(onChangeExpr.startIndex..., in: onChangeExpr)),
               let range = Range(match.range(at: 1), in: onChangeExpr) {
                return String(onChangeExpr[range])
            }
        }
        return nil
    }
}

private struct ActivityCell: View {
    let node: RNComponentNode

    var body: some View {
        let color = node.props["color"]?.stringValue.map { RNStyleResolver.resolveColor($0) } ?? Theme.accent
        let large = node.props["size"]?.stringValue == "large"
        ProgressView().controlSize(large ? .large : .regular).tint(color)
    }
}

private struct NavigatorCell: View {
    let node: RNComponentNode
    let styles: [String: [String: String]]
    let stateManager: RNComponentStateManager
    let screenID: String
    let onNavigate: ((String) -> Void)?
    @State private var activeTabIndex: Int = 0

    var body: some View {
        let screenNodes = node.children.filter { $0.type == .stackScreen || $0.type == .tabScreen }

        VStack(spacing: 0) {
            if node.type == .tabNavigator {
                tabContent(screenNodes)
            } else {
                stackContent(screenNodes)
            }
        }
    }

    @ViewBuilder
    private func tabContent(_ screenNodes: [RNComponentNode]) -> some View {
        if activeTabIndex < screenNodes.count {
            ChildrenCell(node: screenNodes[activeTabIndex], styles: styles, stateManager: stateManager, screenID: screenID, onNavigate: onNavigate)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        Divider().overlay(Theme.border)

        HStack(spacing: 0) {
            ForEach(Array(screenNodes.enumerated()), id: \.element.id) { index, screen in
                let name = screen.props["name"]?.stringValue ?? "Tab"
                let icon = resolveTabIcon(screen)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { activeTabIndex = index }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: icon)
                            .font(.system(size: 16))
                        Text(name)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(index == activeTabIndex ? Theme.accent : Theme.dimText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .sensoryFeedback(.selection, trigger: activeTabIndex)
            }
        }
        .background(Theme.cardBg)
    }

    @ViewBuilder
    private func stackContent(_ screenNodes: [RNComponentNode]) -> some View {
        if let first = screenNodes.first {
            let name = first.props["name"]?.stringValue ?? ""
            HStack {
                Text(name).font(.headline.weight(.semibold)).foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Theme.cardBg)

            Divider().overlay(Theme.border)
            ChildrenCell(node: first, styles: styles, stateManager: stateManager, screenID: screenID, onNavigate: onNavigate)
        }
    }

    private func resolveTabIcon(_ screen: RNComponentNode) -> String {
        if let iconExpr = screen.props["tabBarIcon"]?.stringValue {
            if iconExpr.contains("home") { return "house.fill" }
            if iconExpr.contains("search") { return "magnifyingglass" }
            if iconExpr.contains("settings") || iconExpr.contains("gear") { return "gearshape.fill" }
            if iconExpr.contains("profile") || iconExpr.contains("user") || iconExpr.contains("person") { return "person.fill" }
            if iconExpr.contains("chat") || iconExpr.contains("message") { return "message.fill" }
            if iconExpr.contains("heart") || iconExpr.contains("favorite") { return "heart.fill" }
            if iconExpr.contains("cart") || iconExpr.contains("shopping") { return "cart.fill" }
            if iconExpr.contains("bell") || iconExpr.contains("notification") { return "bell.fill" }
            if iconExpr.contains("camera") { return "camera.fill" }
            if iconExpr.contains("map") || iconExpr.contains("location") { return "map.fill" }
        }
        let name = screen.props["name"]?.stringValue?.lowercased() ?? ""
        if name.contains("home") { return "house.fill" }
        if name.contains("search") || name.contains("explore") { return "magnifyingglass" }
        if name.contains("setting") { return "gearshape.fill" }
        if name.contains("profile") || name.contains("account") { return "person.fill" }
        return "rectangle.portrait"
    }
}

private struct ChildrenCell: View {
    let node: RNComponentNode
    let styles: [String: [String: String]]
    let stateManager: RNComponentStateManager
    let screenID: String
    let onNavigate: ((String) -> Void)?

    var body: some View {
        ForEach(node.children) { child in
            RNNodeCell(node: child, styles: styles, stateManager: stateManager, screenID: screenID, onNavigate: onNavigate)
        }
    }
}

private func cgFloat(_ value: String?) -> CGFloat? {
    guard let v = value, let d = Double(v) else { return nil }
    return CGFloat(d)
}

extension String {
    fileprivate var lowercasedFirst: String {
        guard let first = self.first else { return self }
        return first.lowercased() + dropFirst()
    }
}
