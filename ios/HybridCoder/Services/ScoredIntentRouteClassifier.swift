import Foundation

/// Default `RouteClassifier` implementation.
///
/// Replaces the legacy keyword if/else chain with a transparent, testable
/// scored-intent system. For each candidate route we compute a weighted score
/// from independent signal classes:
///
/// - verb/intent signals (write/edit/apply vs. read/explain vs. locate)
/// - object signals (file paths, symbol-like tokens, `.swift`/`.ts` extensions)
/// - structural signals (query length, imperative mood, presence of code fences)
/// - workspace signals (file hints that match repo paths)
/// - negative signals (questions starting with "why/how/what" penalize write routes)
///
/// The winning route must beat the runner-up by `winningMargin`, otherwise we
/// fall back to `.explanation`. `confidence` is reported on a 1..5 scale,
/// derived from the normalized margin.
nonisolated struct ScoredIntentRouteClassifier: RouteClassifier {
    struct Tuning: Sendable {
        var winningMargin: Double = 0.15
        var maxRelevantFiles: Int = 8
        var maxSearchTerms: Int = 8
    }

    let tuning: Tuning

    init(tuning: Tuning = Tuning()) {
        self.tuning = tuning
    }

    func classify(query: String, fileList: [String]) async throws -> RouteDecision {
        let normalized = query.lowercased()
        let tokens = Self.tokenize(normalized)
        let tokenSet = Set(tokens)

        var scores: [Route: Double] = [
            .explanation: 0,
            .codeGeneration: 0,
            .patchPlanning: 0,
            .search: 0
        ]
        var reasons: [String] = []

        // Verb/intent signals
        let patchVerbs: Set<String> = [
            "patch", "apply", "modify", "edit", "refactor", "update",
            "fix", "change", "tweak", "rename", "move", "delete", "remove"
        ]
        let writeVerbs: Set<String> = [
            "create", "implement", "write", "generate", "add", "build",
            "scaffold", "bootstrap", "introduce", "make"
        ]
        let locateVerbs: Set<String> = [
            "find", "locate", "where", "search", "grep", "lookup", "show"
        ]
        let explainVerbs: Set<String> = [
            "explain", "describe", "summarize", "walk", "why", "how", "what"
        ]

        if !tokenSet.isDisjoint(with: patchVerbs) {
            scores[.patchPlanning, default: 0] += 2.0
            reasons.append("patch-verb")
        }
        if !tokenSet.isDisjoint(with: writeVerbs) {
            scores[.codeGeneration, default: 0] += 1.6
            scores[.patchPlanning, default: 0] += 0.6
            reasons.append("write-verb")
        }
        if !tokenSet.isDisjoint(with: locateVerbs) {
            scores[.search, default: 0] += 1.8
            reasons.append("locate-verb")
        }
        if !tokenSet.isDisjoint(with: explainVerbs) {
            scores[.explanation, default: 0] += 1.4
            reasons.append("explain-verb")
        }

        // Object signals — code extensions & symbol-like tokens
        let codeExts: Set<String> = [
            ".swift", ".ts", ".tsx", ".js", ".jsx", ".py", ".go",
            ".rs", ".kt", ".java", ".md", ".json", ".gguf"
        ]
        let hasCodeExt = codeExts.contains { normalized.contains($0) }
        if hasCodeExt {
            scores[.explanation, default: 0] += 0.6
            scores[.patchPlanning, default: 0] += 0.4
            scores[.search, default: 0] += 0.4
            reasons.append("code-extension")
        }

        let symbolish = tokens.contains { token in
            token.contains(".") || (token.rangeOfCharacter(from: .uppercaseLetters) != nil && token.count >= 3)
        }
        if symbolish {
            scores[.explanation, default: 0] += 0.3
            scores[.search, default: 0] += 0.3
        }

        // Structural signals
        if query.contains("```") {
            scores[.codeGeneration, default: 0] += 0.6
            scores[.patchPlanning, default: 0] += 0.4
            reasons.append("code-fence")
        }
        if query.count > 320 {
            scores[.explanation, default: 0] += 0.4
        }
        if Self.looksImperative(normalized) {
            scores[.codeGeneration, default: 0] += 0.4
            scores[.patchPlanning, default: 0] += 0.3
        }

        // Workspace signals — hint files matching repo paths
        let hintedFiles: [String] = Self.matchFiles(in: fileList, againstTokens: tokens, limit: tuning.maxRelevantFiles)
        if !hintedFiles.isEmpty {
            scores[.explanation, default: 0] += 0.3
            scores[.patchPlanning, default: 0] += 0.5
            scores[.search, default: 0] += 0.3
            reasons.append("workspace-file-hint")
        }

        // Negative signals
        let startsWithQuestionWord = ["why ", "how ", "what ", "when ", "who ", "which "].contains {
            normalized.hasPrefix($0)
        }
        if startsWithQuestionWord {
            scores[.patchPlanning, default: 0] -= 0.8
            scores[.codeGeneration, default: 0] -= 0.6
            scores[.explanation, default: 0] += 0.6
            reasons.append("question-prefix")
        }

        // Pick winner with margin fallback
        let ranked = scores.sorted { $0.value > $1.value }
        let top = ranked.first ?? (.explanation, 0)
        let runnerUp = ranked.dropFirst().first?.value ?? 0
        let margin = top.value - runnerUp

        let chosenRoute: Route
        if margin < tuning.winningMargin {
            chosenRoute = .explanation
            reasons.append("fallback-margin=\(String(format: "%.2f", margin))")
        } else {
            chosenRoute = top.key
        }

        let confidence = Self.confidenceBucket(margin: margin, topScore: top.value)
        let searchTerms = Self.selectSearchTerms(tokens: tokens, limit: tuning.maxSearchTerms)
        let reasoning = "scored-intent: route=\(chosenRoute.rawValue) margin=\(String(format: "%.2f", margin)) signals=[\(reasons.joined(separator: ","))]"

        return RouteDecision(
            route: chosenRoute.rawValue,
            reasoning: reasoning,
            searchTerms: searchTerms,
            relevantFiles: hintedFiles,
            confidence: confidence
        )
    }

    // MARK: - Helpers

    private static func tokenize(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet.alphanumerics.inverted.subtracting(CharacterSet(charactersIn: ".")))
            .filter { !$0.isEmpty }
    }

    private static func looksImperative(_ normalized: String) -> Bool {
        let imperativeStarts = [
            "make ", "create ", "add ", "remove ", "rename ", "fix ",
            "refactor ", "implement ", "write ", "generate ", "build ", "update "
        ]
        return imperativeStarts.contains { normalized.hasPrefix($0) }
    }

    private static func matchFiles(in files: [String], againstTokens tokens: [String], limit: Int) -> [String] {
        guard limit > 0 else { return [] }
        let bigTokens = tokens.filter { $0.count >= 4 }
        guard !bigTokens.isEmpty else { return [] }
        var out: [String] = []
        for path in files {
            let lower = path.lowercased()
            if bigTokens.contains(where: { lower.contains($0) }) {
                out.append(path)
                if out.count >= limit { break }
            }
        }
        return out
    }

    private static func selectSearchTerms(tokens: [String], limit: Int) -> [String] {
        let stopwords: Set<String> = [
            "the", "and", "for", "with", "from", "this", "that", "have",
            "does", "what", "when", "where", "how", "why", "into", "your"
        ]
        var seen: Set<String> = []
        var out: [String] = []
        for token in tokens where token.count >= 4 && !stopwords.contains(token) {
            if seen.insert(token).inserted {
                out.append(token)
                if out.count >= limit { break }
            }
        }
        return out
    }

    private static func confidenceBucket(margin: Double, topScore: Double) -> Int {
        switch (margin, topScore) {
        case (_, ..<0.5): return 1
        case (..<0.3, _): return 2
        case (..<0.8, _): return 3
        case (..<1.5, _): return 4
        default: return 5
        }
    }
}
