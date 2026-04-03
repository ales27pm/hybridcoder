import Foundation

/// Runtime tokenizer for Hugging Face `tokenizer.json` exports backed by ByteLevel-BPE
/// (the exact tokenizer family used by RoBERTa/CodeBERT).
actor HFTokenizer {

    nonisolated enum TokenizerError: Error, LocalizedError, Sendable {
        case fileNotFound(String)
        case invalidFormat(String)
        case incompatibleTokenizer(String)
        case missingComponent(String)
        case notLoaded

        nonisolated var errorDescription: String? {
            switch self {
            case .fileNotFound(let path):
                return "Tokenizer file not found: \(path)"
            case .invalidFormat(let detail):
                return "Invalid tokenizer format: \(detail)"
            case .incompatibleTokenizer(let detail):
                return "Tokenizer is incompatible with HF ByteLevel-BPE runtime: \(detail)"
            case .missingComponent(let detail):
                return "Tokenizer is missing required components: \(detail)"
            case .notLoaded:
                return "Tokenizer encode called before load()."
            }
        }
    }

    nonisolated struct EncodedInput: Sendable {
        let inputIDs: [Int]
        let attentionMask: [Int]
        let tokenTypeIDs: [Int]
        let originalTokenCount: Int
    }

    private struct TokenizerJSON: Decodable {
        struct AddedToken: Decodable {
            let id: Int
            let content: String
            let special: Bool?
        }
        struct PreTokenizer: Decodable {
            let type: String
            let add_prefix_space: Bool?
            let pretokenizers: [PreTokenizer]?
        }
        struct PostProcessor: Decodable {
            let type: String
            let sep: [JSONValue]?
            let cls: [JSONValue]?
            let processors: [PostProcessor]?
        }
        struct Model: Decodable {
            let type: String
            let vocab: [String: Int]
            let merges: [String]?
            let unk_token: String?
        }

        let added_tokens: [AddedToken]?
        let pre_tokenizer: PreTokenizer?
        let post_processor: PostProcessor?
        let model: Model
    }

    private enum JSONValue: Decodable {
        case string(String)
        case int(Int)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let intValue = try? container.decode(Int.self) {
                self = .int(intValue)
                return
            }
            if let stringValue = try? container.decode(String.self) {
                self = .string(stringValue)
                return
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }

        var intValue: Int? {
            if case .int(let v) = self { return v }
            return nil
        }

        var stringValue: String? {
            if case .string(let v) = self { return v }
            return nil
        }
    }

    private static let byteLevelPattern = "'s|'t|'re|'ve|'m|'ll|'d| ?\\p{L}+| ?\\p{N}+| ?[^\\s\\p{L}\\p{N}]+|\\s+(?!\\S)|\\s+"

    private let maxLength = 512

    private var isLoaded = false
    private var addPrefixSpace = false

    private var vocab: [String: Int] = [:]
    private var mergesRank: [String: Int] = [:]
    private var bpeCache: [String: [String]] = [:]

    private var clsTokenID: Int = 0
    private var sepTokenID: Int = 2
    private var padTokenID: Int = 1
    private var unkTokenID: Int = 3
    private var unkToken: String = "<unk>"

    private let byteEncoder: [UInt8: Character] = HFTokenizer.makeByteToUnicodeMap()
    private lazy var tokenRegex = try? NSRegularExpression(pattern: Self.byteLevelPattern, options: [])

    var loaded: Bool { isLoaded }

    func load(from directory: URL) async throws {
        let fm = FileManager.default
        let tokenizerURL = directory.appendingPathComponent("tokenizer.json")

        guard fm.fileExists(atPath: tokenizerURL.path) else {
            throw TokenizerError.fileNotFound(tokenizerURL.path)
        }

        let data = try Data(contentsOf: tokenizerURL)
        let decoded: TokenizerJSON
        do {
            decoded = try JSONDecoder().decode(TokenizerJSON.self, from: data)
        } catch {
            throw TokenizerError.invalidFormat("tokenizer.json decode failed: \(error.localizedDescription)")
        }

        guard decoded.model.type.uppercased() == "BPE" else {
            throw TokenizerError.incompatibleTokenizer("Expected model.type=BPE, got \(decoded.model.type)")
        }

        let preTokenizer = decoded.pre_tokenizer
        let preTokenizerTypes = preTokenizer?.flattenedTypes(path: "pre_tokenizer").joined(separator: ", ") ?? "none"
        let hasByteLevelPreTokenizer = preTokenizer?.contains(type: "bytelevel") ?? false
        guard hasByteLevelPreTokenizer else {
            throw TokenizerError.incompatibleTokenizer("Expected ByteLevel pre-tokenizer, got \(preTokenizerTypes)")
        }
        self.addPrefixSpace = preTokenizer?.addPrefixSpaceValue() ?? false

        if let post = decoded.post_processor,
           post.containsAny(types: ["roberta", "bytelevel", "template"]) == false {
            let postTypes = post.flattenedTypes(path: "post_processor").joined(separator: ", ")
            throw TokenizerError.incompatibleTokenizer("Expected a supported post-processor (Roberta/ByteLevel/Template), got \(postTypes)")
        }

        guard decoded.model.vocab.isEmpty == false else {
            throw TokenizerError.missingComponent("model.vocab is empty")
        }
        self.vocab = decoded.model.vocab

        let merges = decoded.model.merges ?? []
        guard merges.isEmpty == false else {
            throw TokenizerError.missingComponent("model.merges is empty")
        }

        var ranked: [String: Int] = [:]
        ranked.reserveCapacity(merges.count)
        for (idx, line) in merges.enumerated() {
            let parts = line.split(separator: " ")
            guard parts.count == 2 else { continue }
            ranked["\(parts[0]) \(parts[1])"] = idx
        }
        guard ranked.isEmpty == false else {
            throw TokenizerError.invalidFormat("No valid merge pairs parsed from model.merges")
        }
        self.mergesRank = ranked

        self.unkToken = decoded.model.unk_token ?? "<unk>"

        guard let clsID = vocab["<s>"] else { throw TokenizerError.missingComponent("<s> missing in vocab") }
        guard let sepID = vocab["</s>"] else { throw TokenizerError.missingComponent("</s> missing in vocab") }
        guard let padID = vocab["<pad>"] else { throw TokenizerError.missingComponent("<pad> missing in vocab") }

        self.clsTokenID = clsID
        self.sepTokenID = sepID
        self.padTokenID = padID
        self.unkTokenID = vocab[unkToken] ?? vocab["<unk>"] ?? 3

        if let added = decoded.added_tokens {
            for token in added where token.special == true {
                vocab[token.content] = token.id
            }
        }

        guard tokenRegex != nil else {
            throw TokenizerError.invalidFormat("Failed to compile ByteLevel pre-tokenizer regex")
        }

        bpeCache.removeAll(keepingCapacity: true)
        isLoaded = true
    }

    func encode(text: String) throws -> EncodedInput {
        guard isLoaded else { throw TokenizerError.notLoaded }

        let input = addPrefixSpace && text.hasPrefix(" ") == false ? " " + text : text
        let pieces = preTokenize(input)

        var tokens: [String] = ["<s>"]
        for piece in pieces {
            let mapped = mapBytesToUnicode(piece)
            let bpe = applyBPE(mapped)
            tokens.append(contentsOf: bpe)
        }
        tokens.append("</s>")

        if tokens.count > maxLength {
            tokens = Array(tokens.prefix(maxLength - 1)) + ["</s>"]
        }

        var inputIDs = tokens.map { vocab[$0] ?? unkTokenID }
        let realLen = inputIDs.count

        if realLen < maxLength {
            inputIDs += Array(repeating: padTokenID, count: maxLength - realLen)
        }

        let attentionMask = Array(repeating: 1, count: realLen) + Array(repeating: 0, count: max(0, maxLength - realLen))
        let tokenTypeIDs = Array(repeating: 0, count: maxLength)

        return EncodedInput(
            inputIDs: inputIDs,
            attentionMask: attentionMask,
            tokenTypeIDs: tokenTypeIDs,
            originalTokenCount: realLen
        )
    }

    private func preTokenize(_ text: String) -> [String] {
        guard let tokenRegex else { return [] }
        let range = NSRange(location: 0, length: text.utf16.count)
        let matches = tokenRegex.matches(in: text, options: [], range: range)
        return matches.compactMap { match in
            guard let r = Range(match.range, in: text) else { return nil }
            return String(text[r])
        }
    }

    private func mapBytesToUnicode(_ text: String) -> String {
        var chars: [Character] = []
        chars.reserveCapacity(text.utf8.count)
        for b in text.utf8 {
            chars.append(byteEncoder[b] ?? "�")
        }
        return String(chars)
    }

    private func applyBPE(_ token: String) -> [String] {
        if let cached = bpeCache[token] {
            return cached
        }

        var word = token.map { String($0) }
        if word.count <= 1 {
            bpeCache[token] = word
            return word
        }

        while true {
            let pairs = adjacentPairs(word)
            if pairs.isEmpty { break }

            var bestPair: String?
            var bestRank = Int.max

            for pair in pairs {
                if let rank = mergesRank[pair], rank < bestRank {
                    bestRank = rank
                    bestPair = pair
                }
            }

            guard let pair = bestPair else { break }
            let parts = pair.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { break }

            let first = parts[0]
            let second = parts[1]

            var newWord: [String] = []
            newWord.reserveCapacity(word.count)

            var i = 0
            while i < word.count {
                if i < word.count - 1, word[i] == first, word[i + 1] == second {
                    newWord.append(first + second)
                    i += 2
                } else {
                    newWord.append(word[i])
                    i += 1
                }
            }

            word = newWord
            if word.count == 1 { break }
        }

        bpeCache[token] = word
        return word
    }

    private func adjacentPairs(_ word: [String]) -> Set<String> {
        guard word.count > 1 else { return [] }
        var pairs: Set<String> = []
        pairs.reserveCapacity(word.count - 1)
        for i in 0..<(word.count - 1) {
            pairs.insert("\(word[i]) \(word[i + 1])")
        }
        return pairs
    }

    private static func makeByteToUnicodeMap() -> [UInt8: Character] {
        var bs: [Int] = Array(33...126) + Array(161...172) + Array(174...255)
        var cs = bs
        var n = 0

        for b in 0...255 where bs.contains(b) == false {
            bs.append(b)
            cs.append(256 + n)
            n += 1
        }

        var table: [UInt8: Character] = [:]
        table.reserveCapacity(256)
        for (b, c) in zip(bs, cs) {
            if let scalar = UnicodeScalar(c) {
                table[UInt8(b)] = Character(scalar)
            }
        }
        return table
    }
}

private extension HFTokenizer.TokenizerJSON.PreTokenizer {
    func contains(type target: String) -> Bool {
        let normalizedTarget = target.lowercased()
        if type.lowercased() == normalizedTarget { return true }
        return pretokenizers?.contains(where: { $0.contains(type: normalizedTarget) }) ?? false
    }

    func addPrefixSpaceValue() -> Bool {
        if let add_prefix_space { return add_prefix_space }
        return pretokenizers?.first(where: { $0.contains(type: "bytelevel") })?.addPrefixSpaceValue() ?? false
    }

    func flattenedTypes(path: String) -> [String] {
        var values = ["\(path)=\(type)"]
        for (index, tokenizer) in (pretokenizers ?? []).enumerated() {
            values.append(contentsOf: tokenizer.flattenedTypes(path: "\(path).pretokenizers[\(index)]"))
        }
        return values
    }
}

private extension HFTokenizer.TokenizerJSON.PostProcessor {
    func containsAny(types targets: [String]) -> Bool {
        let normalized = type.lowercased()
        if targets.contains(where: { normalized.contains($0.lowercased()) }) {
            return true
        }
        return processors?.contains(where: { $0.containsAny(types: targets) }) ?? false
    }

    func flattenedTypes(path: String) -> [String] {
        var values = ["\(path)=\(type)"]
        for (index, processor) in (processors ?? []).enumerated() {
            values.append(contentsOf: processor.flattenedTypes(path: "\(path).processors[\(index)]"))
        }
        return values
    }
}

@available(*, deprecated, renamed: "HFTokenizer", message: "BERTTokenizer is deprecated. Use HFTokenizer for tokenizer.json-compatible runtimes.")
typealias BERTTokenizer = HFTokenizer
