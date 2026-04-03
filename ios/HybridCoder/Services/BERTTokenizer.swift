import Foundation

actor BERTTokenizer {

    nonisolated enum TokenizerError: Error, LocalizedError, Sendable {
        case fileNotFound(String)
        case invalidFormat(String)
        case vocabEmpty

        nonisolated var errorDescription: String? {
            switch self {
            case .fileNotFound(let path):
                return "Tokenizer file not found: \(path)"
            case .invalidFormat(let detail):
                return "Invalid tokenizer format: \(detail)"
            case .vocabEmpty:
                return "Vocabulary is empty after loading."
            }
        }
    }

    nonisolated struct TokenizerConfig: Sendable {
        let clsTokenID: Int
        let sepTokenID: Int
        let padTokenID: Int
        let unkTokenID: Int
        let maxLength: Int
    }

    nonisolated struct EncodedInput: Sendable {
        let inputIDs: [Int]
        let attentionMask: [Int]
        let tokenTypeIDs: [Int]
        let originalTokenCount: Int
    }

    private var vocab: [String: Int] = [:]
    private var config: TokenizerConfig?
    private var isLoaded: Bool = false

    private static let defaultClsToken = "[CLS]"
    private static let defaultSepToken = "[SEP]"
    private static let defaultPadToken = "[PAD]"
    private static let defaultUnkToken = "[UNK]"

    var loaded: Bool { isLoaded }

    func load(from directory: URL) async throws {
        let fm = FileManager.default

        let tokenizerJsonURL = directory.appendingPathComponent("tokenizer.json")
        let vocabURL = directory.appendingPathComponent("vocab.txt")
        let vocabJsonURL = directory.appendingPathComponent("vocab.json")

        if fm.fileExists(atPath: tokenizerJsonURL.path) {
            try loadFromTokenizerJSON(tokenizerJsonURL)
        } else if fm.fileExists(atPath: vocabURL.path) {
            try loadFromVocabTxt(vocabURL)
        } else if fm.fileExists(atPath: vocabJsonURL.path) {
            try loadFromVocabJSON(vocabJsonURL)
        } else {
            throw TokenizerError.fileNotFound("No tokenizer.json, vocab.txt, or vocab.json found in \(directory.lastPathComponent)")
        }

        guard !vocab.isEmpty else { throw TokenizerError.vocabEmpty }

        let clsID = vocab[Self.defaultClsToken] ?? 101
        let sepID = vocab[Self.defaultSepToken] ?? 102
        let padID = vocab[Self.defaultPadToken] ?? 0
        let unkID = vocab[Self.defaultUnkToken] ?? 100

        config = TokenizerConfig(
            clsTokenID: clsID,
            sepTokenID: sepID,
            padTokenID: padID,
            unkTokenID: unkID,
            maxLength: 512
        )

        isLoaded = true
    }

    func encode(text: String) -> EncodedInput {
        guard let config, isLoaded else {
            return EncodedInput(inputIDs: [], attentionMask: [], tokenTypeIDs: [], originalTokenCount: 0)
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let ids = [config.clsTokenID, config.sepTokenID]
            let padCount = config.maxLength - ids.count
            return EncodedInput(
                inputIDs: ids + Array(repeating: config.padTokenID, count: padCount),
                attentionMask: [1, 1] + Array(repeating: 0, count: padCount),
                tokenTypeIDs: Array(repeating: 0, count: config.maxLength),
                originalTokenCount: 2
            )
        }

        let tokens = tokenize(trimmed)
        let maxContentLen = config.maxLength - 2
        let truncated = Array(tokens.prefix(maxContentLen))

        var inputIDs = [config.clsTokenID]
        for token in truncated {
            inputIDs.append(vocab[token] ?? config.unkTokenID)
        }
        inputIDs.append(config.sepTokenID)

        let realLen = inputIDs.count
        let padCount = config.maxLength - realLen

        if padCount > 0 {
            inputIDs.append(contentsOf: Array(repeating: config.padTokenID, count: padCount))
        }

        var attentionMask = Array(repeating: 1, count: realLen)
        if padCount > 0 {
            attentionMask.append(contentsOf: Array(repeating: 0, count: padCount))
        }

        let tokenTypeIDs = Array(repeating: 0, count: config.maxLength)

        return EncodedInput(
            inputIDs: inputIDs,
            attentionMask: attentionMask,
            tokenTypeIDs: tokenTypeIDs,
            originalTokenCount: realLen
        )
    }

    // MARK: - WordPiece Tokenization

    private func tokenize(_ text: String) -> [String] {
        let basicTokens = basicTokenize(text)
        var wordPieceTokens: [String] = []
        for token in basicTokens {
            let subTokens = wordPieceTokenize(token)
            wordPieceTokens.append(contentsOf: subTokens)
        }
        return wordPieceTokens
    }

    private func basicTokenize(_ text: String) -> [String] {
        let cleaned = text.lowercased().map { ch -> String in
            if ch.isWhitespace { return " " }
            if isPunctuation(ch) { return " \(ch) " }
            if shouldStripChar(ch) { return "" }
            return String(ch)
        }.joined()

        return cleaned.split(separator: " ").map(String.init).filter { !$0.isEmpty }
    }

    private func wordPieceTokenize(_ token: String) -> [String] {
        let unkToken = Self.defaultUnkToken
        guard !token.isEmpty else { return [] }

        let chars = Array(token)
        if chars.count > 200 {
            return [unkToken]
        }

        var tokens: [String] = []
        var start = 0

        while start < chars.count {
            var end = chars.count
            var found: String?

            while start < end {
                let substr: String
                if start > 0 {
                    substr = "##" + String(chars[start..<end])
                } else {
                    substr = String(chars[start..<end])
                }

                if vocab[substr] != nil {
                    found = substr
                    break
                }
                end -= 1
            }

            if let found {
                tokens.append(found)
                start = end
            } else {
                tokens.append(unkToken)
                start += 1
            }
        }

        return tokens
    }

    private func isPunctuation(_ ch: Character) -> Bool {
        guard let scalar = ch.unicodeScalars.first else { return false }
        let v = scalar.value
        if (v >= 33 && v <= 47) || (v >= 58 && v <= 64) ||
            (v >= 91 && v <= 96) || (v >= 123 && v <= 126) {
            return true
        }
        return ch.isPunctuation
    }

    private func shouldStripChar(_ ch: Character) -> Bool {
        guard let scalar = ch.unicodeScalars.first else { return false }
        let v = scalar.value
        return v == 0 || v == 0xFFFD || (v >= 1 && v <= 31 && v != 9 && v != 10 && v != 13)
    }

    // MARK: - Vocab Loading

    private func loadFromTokenizerJSON(_ url: URL) throws {
        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TokenizerError.invalidFormat("tokenizer.json is not a valid JSON object")
        }

        if let model = json["model"] as? [String: Any],
           let vocabDict = model["vocab"] as? [String: Int] {
            self.vocab = vocabDict
            mergeAddedTokens(from: json)
            return
        }

        if let model = json["model"] as? [String: Any],
           let vocabDict = model["vocab"] as? [String: NSNumber] {
            var converted: [String: Int] = [:]
            for (key, val) in vocabDict {
                converted[key] = val.intValue
            }
            self.vocab = converted
            mergeAddedTokens(from: json)
            return
        }

        if let vocabDict = json["vocab"] as? [String: Int] {
            self.vocab = vocabDict
            mergeAddedTokens(from: json)
            return
        }

        var builtVocab: [String: Int] = [:]
        if let addedTokens = json["added_tokens"] as? [[String: Any]] {
            for entry in addedTokens {
                if let content = entry["content"] as? String,
                   let id = entry["id"] as? Int {
                    builtVocab[content] = id
                }
            }
        }

        if !builtVocab.isEmpty {
            self.vocab = builtVocab
            return
        }

        throw TokenizerError.invalidFormat("Could not extract vocabulary from tokenizer.json")
    }

    private func mergeAddedTokens(from json: [String: Any]) {
        guard let addedTokens = json["added_tokens"] as? [[String: Any]] else { return }
        for entry in addedTokens {
            if let content = entry["content"] as? String,
               let id = entry["id"] as? Int {
                vocab[content] = id
            }
        }
    }

    private func loadFromVocabTxt(_ url: URL) throws {
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        var loadedVocab: [String: Int] = [:]
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                loadedVocab[trimmed] = index
            }
        }
        self.vocab = loadedVocab
    }

    private func loadFromVocabJSON(_ url: URL) throws {
        let data = try Data(contentsOf: url)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Int] else {
            throw TokenizerError.invalidFormat("vocab.json is not a valid {token: id} dictionary")
        }
        self.vocab = dict
    }
}
