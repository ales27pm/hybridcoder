import Foundation
import OSLog

actor DocumentationFetchService {

    nonisolated enum FetchError: Error, LocalizedError, Sendable {
        case invalidURL(String)
        case networkError(String)
        case parsingFailed(String)

        nonisolated var errorDescription: String? {
            switch self {
            case .invalidURL(let url): return "Invalid URL: \(url)"
            case .networkError(let detail): return "Network error: \(detail)"
            case .parsingFailed(let detail): return "Parsing failed: \(detail)"
            }
        }
    }

    private let session: URLSession
    private let logger = Logger(subsystem: "com.hybridcoder.app", category: "DocumentationFetch")

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    func fetchDocumentationPage(url: String) async throws -> String {
        guard let pageURL = URL(string: url) else {
            throw FetchError.invalidURL(url)
        }

        var request = URLRequest(url: pageURL)
        request.setValue("text/plain, text/markdown, text/html", forHTTPHeaderField: "Accept")
        request.setValue("HybridCoder/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw FetchError.networkError("HTTP \(statusCode) for \(url)")
        }

        guard let content = String(data: data, encoding: .utf8), !content.isEmpty else {
            throw FetchError.parsingFailed("Empty response from \(url)")
        }

        let cleaned = Self.extractMainContent(from: content)
        logger.info("doc.fetch.success url=\(url, privacy: .public) size=\(cleaned.count)")
        return cleaned
    }

    func fetchAndUpdateSource(_ source: DocumentationSource, pageURLs: [String: String]) async -> DocumentationSource {
        var updatedPages: [DocumentationSource.DocPage] = []

        for page in source.pages {
            let url = pageURLs[page.path] ?? "\(source.baseURL)/\(page.path)"

            if !page.content.isEmpty {
                updatedPages.append(page)
                continue
            }

            do {
                let content = try await fetchDocumentationPage(url: url)
                updatedPages.append(DocumentationSource.DocPage(
                    path: page.path,
                    title: page.title,
                    content: content
                ))
            } catch {
                logger.warning("doc.fetch.page.failed url=\(url, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                updatedPages.append(page)
            }
        }

        return DocumentationSource(
            id: source.id,
            name: source.name,
            category: source.category,
            baseURL: source.baseURL,
            pages: updatedPages,
            priority: source.priority,
            isEnabled: source.isEnabled
        )
    }

    nonisolated static func extractMainContent(from html: String) -> String {
        if !html.contains("<") {
            return html
        }

        var text = html
        text = text.replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<nav[^>]*>[\\s\\S]*?</nav>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<footer[^>]*>[\\s\\S]*?</footer>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<header[^>]*>[\\s\\S]*?</header>", with: "", options: .regularExpression)

        text = text.replacingOccurrences(of: "<br[^>]*>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</p>", with: "\n\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</div>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</li>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</h[1-6]>", with: "\n\n", options: .regularExpression)

        text = text.replacingOccurrences(of: "<h1[^>]*>", with: "# ", options: .regularExpression)
        text = text.replacingOccurrences(of: "<h2[^>]*>", with: "## ", options: .regularExpression)
        text = text.replacingOccurrences(of: "<h3[^>]*>", with: "### ", options: .regularExpression)
        text = text.replacingOccurrences(of: "<li[^>]*>", with: "- ", options: .regularExpression)

        text = text.replacingOccurrences(of: "<code[^>]*>", with: "`", options: .regularExpression)
        text = text.replacingOccurrences(of: "</code>", with: "`")
        text = text.replacingOccurrences(of: "<pre[^>]*>", with: "```\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</pre>", with: "\n```")

        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")

        let lines = text.components(separatedBy: "\n")
        var cleaned: [String] = []
        var blankCount = 0
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                blankCount += 1
                if blankCount <= 2 { cleaned.append("") }
            } else {
                blankCount = 0
                cleaned.append(trimmed)
            }
        }

        return cleaned.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
