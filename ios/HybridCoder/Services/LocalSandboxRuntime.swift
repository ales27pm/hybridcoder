import Foundation
import JavaScriptCore
import OSLog

actor LocalSandboxRuntime {
    private let logger = Logger(subsystem: "com.hybridcoder.app", category: "LocalSandboxRuntime")
    private var context: JSContext?
    private var consoleOutput: [ConsoleEntry] = []
    private let maxConsoleEntries = 200

    nonisolated struct ConsoleEntry: Identifiable, Sendable {
        let id: UUID
        let level: Level
        let message: String
        let timestamp: Date

        nonisolated enum Level: String, Sendable {
            case log
            case warn
            case error
            case info
        }

        init(level: Level, message: String) {
            self.id = UUID()
            self.level = level
            self.message = message
            self.timestamp = Date()
        }
    }

    nonisolated struct ExecutionResult: Sendable {
        let output: String?
        let error: String?
        let consoleEntries: [ConsoleEntry]
        let durationMs: Double
    }

    func initialize() {
        guard context == nil else { return }
        let ctx = JSContext()!

        ctx.exceptionHandler = { [weak self] _, exception in
            guard let self, let exception else { return }
            let msg = exception.toString() ?? "Unknown JS error"
            Task { await self.appendConsole(.init(level: .error, message: msg)) }
        }

        injectConsoleAPI(into: ctx)
        injectTimerStubs(into: ctx)
        injectModuleStubs(into: ctx)

        context = ctx
        logger.info("LocalSandboxRuntime initialized")
    }

    func execute(code: String) async -> ExecutionResult {
        if context == nil { initialize() }
        guard let ctx = context else {
            return ExecutionResult(output: nil, error: "Runtime not initialized", consoleEntries: [], durationMs: 0)
        }

        consoleOutput.removeAll()
        let start = CFAbsoluteTimeGetCurrent()

        let wrappedCode = """
        (function() {
            try {
                \(code)
            } catch(e) {
                console.error(e.toString());
            }
        })();
        """

        let result = ctx.evaluateScript(wrappedCode)
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        let output = result?.isUndefined == false ? result?.toString() : nil
        let error = ctx.exception?.toString()
        ctx.exception = nil

        return ExecutionResult(
            output: output,
            error: error,
            consoleEntries: consoleOutput,
            durationMs: elapsed
        )
    }

    func executeFiles(_ files: [(name: String, content: String)]) async -> ExecutionResult {
        let combined = files.map { "// --- \($0.name) ---\n\($0.content)" }.joined(separator: "\n\n")
        return await execute(code: combined)
    }

    func reset() {
        context = nil
        consoleOutput.removeAll()
        logger.info("LocalSandboxRuntime reset")
    }

    private func appendConsole(_ entry: ConsoleEntry) {
        consoleOutput.append(entry)
        if consoleOutput.count > maxConsoleEntries {
            consoleOutput.removeFirst(consoleOutput.count - maxConsoleEntries)
        }
    }

    private func injectConsoleAPI(into ctx: JSContext) {
        let logBlock: @convention(block) (JSValue) -> Void = { [weak self] value in
            let msg = value.toString() ?? ""
            Task { await self?.appendConsole(.init(level: .log, message: msg)) }
        }
        let warnBlock: @convention(block) (JSValue) -> Void = { [weak self] value in
            let msg = value.toString() ?? ""
            Task { await self?.appendConsole(.init(level: .warn, message: msg)) }
        }
        let errorBlock: @convention(block) (JSValue) -> Void = { [weak self] value in
            let msg = value.toString() ?? ""
            Task { await self?.appendConsole(.init(level: .error, message: msg)) }
        }
        let infoBlock: @convention(block) (JSValue) -> Void = { [weak self] value in
            let msg = value.toString() ?? ""
            Task { await self?.appendConsole(.init(level: .info, message: msg)) }
        }

        let console = JSValue(newObjectIn: ctx)!
        console.setObject(logBlock, forKeyedSubscript: "log" as NSString)
        console.setObject(warnBlock, forKeyedSubscript: "warn" as NSString)
        console.setObject(errorBlock, forKeyedSubscript: "error" as NSString)
        console.setObject(infoBlock, forKeyedSubscript: "info" as NSString)
        ctx.setObject(console, forKeyedSubscript: "console" as NSString)
    }

    private func injectTimerStubs(into ctx: JSContext) {
        let noopWithReturn: @convention(block) (JSValue, JSValue) -> Int = { _, _ in return 0 }
        let noopClear: @convention(block) (Int) -> Void = { _ in }

        ctx.setObject(noopWithReturn, forKeyedSubscript: "setTimeout" as NSString)
        ctx.setObject(noopWithReturn, forKeyedSubscript: "setInterval" as NSString)
        ctx.setObject(noopClear, forKeyedSubscript: "clearTimeout" as NSString)
        ctx.setObject(noopClear, forKeyedSubscript: "clearInterval" as NSString)
    }

    private func injectModuleStubs(into ctx: JSContext) {
        let requireBlock: @convention(block) (String) -> JSValue = { moduleName in
            let obj = JSValue(newObjectIn: JSContext.current())!
            obj.setObject("stub:\(moduleName)", forKeyedSubscript: "__module" as NSString)
            return obj
        }
        ctx.setObject(requireBlock, forKeyedSubscript: "require" as NSString)

        ctx.evaluateScript("""
        var exports = {};
        var module = { exports: exports };
        """)
    }
}
