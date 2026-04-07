import Foundation
import OSLog

@Observable
@MainActor
final class LanguageModelSessionManager {
    private let logger = Logger(subsystem: "com.hybridcoder.app", category: "SessionManager")

    private(set) var activeSessions: [String: SessionInfo] = [:]
    private(set) var totalEstimatedTokens: Int = 0

    struct SessionInfo: Identifiable, Sendable {
        let id: String
        let purpose: SessionPurpose
        var estimatedTokens: Int
        var turnCount: Int
        var createdAt: Date
        var lastUsedAt: Date
        var isActive: Bool

        var age: TimeInterval { Date().timeIntervalSince(createdAt) }
        var idleTime: TimeInterval { Date().timeIntervalSince(lastUsedAt) }
    }

    nonisolated enum SessionPurpose: String, Sendable {
        case routeClassification
        case explanation
        case codeGeneration
        case patchPlanning
        case conversationSummary
        case contentTagging
    }

    func registerSession(id: String, purpose: SessionPurpose) {
        let info = SessionInfo(
            id: id,
            purpose: purpose,
            estimatedTokens: 0,
            turnCount: 0,
            createdAt: Date(),
            lastUsedAt: Date(),
            isActive: true
        )
        activeSessions[id] = info
        recalculateTokenBudget()
        logger.info("session.registered id=\(id, privacy: .public) purpose=\(purpose.rawValue, privacy: .public)")
    }

    func recordTurn(sessionID: String, estimatedTokens: Int) {
        guard var session = activeSessions[sessionID] else { return }
        session.estimatedTokens += estimatedTokens
        session.turnCount += 1
        session.lastUsedAt = Date()
        activeSessions[sessionID] = session
        recalculateTokenBudget()
    }

    func markSessionInactive(id: String) {
        guard var session = activeSessions[id] else { return }
        session.isActive = false
        activeSessions[id] = session
        logger.info("session.deactivated id=\(id, privacy: .public)")
    }

    func removeSession(id: String) {
        activeSessions.removeValue(forKey: id)
        recalculateTokenBudget()
        logger.info("session.removed id=\(id, privacy: .public)")
    }

    func shouldEvictSession(id: String, maxIdleSeconds: TimeInterval = 300) -> Bool {
        guard let session = activeSessions[id] else { return false }
        return session.idleTime > maxIdleSeconds && !session.isActive
    }

    func evictIdleSessions(maxIdleSeconds: TimeInterval = 300) {
        let toEvict = activeSessions.values.filter {
            $0.idleTime > maxIdleSeconds && !$0.isActive
        }
        for session in toEvict {
            removeSession(id: session.id)
        }
        if !toEvict.isEmpty {
            logger.info("session.evicted count=\(toEvict.count)")
        }
    }

    func sessionNeedsCompaction(id: String, tokenThreshold: Int = 3000) -> Bool {
        guard let session = activeSessions[id] else { return false }
        return session.estimatedTokens > tokenThreshold
    }

    func recordCompaction(sessionID: String, newEstimatedTokens: Int) {
        guard var session = activeSessions[sessionID] else { return }
        let previous = session.estimatedTokens
        session.estimatedTokens = newEstimatedTokens
        activeSessions[sessionID] = session
        recalculateTokenBudget()
        logger.info("session.compacted id=\(sessionID, privacy: .public) tokens=\(previous)->\(newEstimatedTokens)")
    }

    var sessionSummary: String {
        let active = activeSessions.values.filter(\.isActive).count
        let total = activeSessions.count
        return "\(active) active / \(total) total · ~\(totalEstimatedTokens) tokens"
    }

    private func recalculateTokenBudget() {
        totalEstimatedTokens = activeSessions.values.reduce(0) { $0 + $1.estimatedTokens }
    }
}
