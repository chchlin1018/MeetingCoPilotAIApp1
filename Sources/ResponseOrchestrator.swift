// ═══════════════════════════════════════════════════════════════════════════
// ResponseOrchestrator.swift
// MeetingCopilot v4.3 — 回應編排器（Notion + NotebookLM 雙來源並行查詢）
// ═══════════════════════════════════════════════════════════════════════════
//
//  第二層 RAG：雙來源並行，不是二選一
//
//  NotebookLM（文件萃取）         Notion（個人規劃）
//  → PDF/PPTX/XLSX/影片          → Goals、策略筆記
//  → Google 語意搜尋              → Q&A 建議、客戶背景
//  → 精確數據、原文段落            → 談判要點、歷史紀錄
//       │                              │
//       └──────── 並行查詢 ─────────────┘
//                    │
//                合併 context
//                    │
//              餵給 Claude
//                    │
//          同時有數據佐證 + 策略建議
//
//  Platform: macOS 14.0+
// ═══════════════════════════════════════════════════════════════════════════

import Foundation

// MARK: - Orchestrator Events

struct OrchestratorEvent: Sendable {
    enum EventType: Sendable {
        case cardInserted(AICard)
        case claudeStreamingStarted
        case claudeStreamingEnded
        case notebookLMQueryStarted
        case notebookLMQueryEnded
        case statsUpdated(SessionStats)
    }
    let type: EventType
    let timestamp: Date
}

// MARK: - Response Orchestrator

actor ResponseOrchestrator {

    private(set) var stats = SessionStats()
    private(set) var cards: [AICard] = []

    private let keywordMatcher = KeywordMatcher()
    private let claudeService: ClaudeService
    private let notebookLMService: NotebookLMService
    private let notionService: NotionRetrievalService?
    private var meetingContext: MeetingContext
    private let notebookLMConfig: NotebookLMConfig

    private var lastClaudeQueryTime: Date = .distantPast
    private let claudeMinInterval: TimeInterval = 5.0

    private var eventContinuation: AsyncStream<OrchestratorEvent>.Continuation?
    private(set) var events: AsyncStream<OrchestratorEvent>!
    private(set) var isNotebookLMAvailable: Bool = false
    private(set) var isNotionAvailable: Bool = false

    init(
        claudeAPIKey: String,
        claudeModel: String = "claude-sonnet-4-20250514",
        notebookLMConfig: NotebookLMConfig = .default,
        meetingContext: MeetingContext
    ) {
        self.claudeService = ClaudeService(apiKey: claudeAPIKey, model: claudeModel)
        self.notebookLMConfig = notebookLMConfig
        self.notebookLMService = NotebookLMService(config: notebookLMConfig)
        self.meetingContext = meetingContext

        if let notionKey = KeychainManager.notionAPIKey {
            self.notionService = NotionRetrievalService(apiKey: notionKey)
        } else {
            self.notionService = nil
        }

        var cont: AsyncStream<OrchestratorEvent>.Continuation!
        self.events = AsyncStream { cont = $0 }
        self.eventContinuation = cont
    }

    func loadKnowledgeBase(_ items: [QAItem]) async {
        await keywordMatcher.loadKnowledgeBase(items)
        stats.qaItemsLoaded = items.count
    }

    func updateContext(_ context: MeetingContext) { self.meetingContext = context }

    func checkNotebookLMAvailability() async {
        if let notion = notionService {
            isNotionAvailable = await notion.isAvailable
            if isNotionAvailable { print("📝 Notion RAG: Available (個人筆記/策略)") }
        }
        isNotebookLMAvailable = await notebookLMService.isAvailable
        if isNotebookLMAvailable { print("📚 NotebookLM RAG: Available (文件數據)") }

        if isNotionAvailable && isNotebookLMAvailable {
            print("✅ 第二層 RAG: 雙來源並行模式 (Notion + NotebookLM)")
        } else if isNotionAvailable {
            print("⚠️ 第二層 RAG: 僅 Notion（無文件數據）")
        } else if isNotebookLMAvailable {
            print("⚠️ 第二層 RAG: 僅 NotebookLM（無個人筆記）")
        } else {
            print("⚠️ 第二層 RAG: 無可用服務，將直接使用 Claude")
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: ★ 雙來源並行查詢（核心變更）
    // ═══════════════════════════════════════════════════════

    /// 並行查詢 Notion + NotebookLM，合併結果
    private func parallelRAGQuery(question: String) async -> (context: String, sources: [String]) {
        var notionCtx = ""
        var nlmCtx = ""
        var sources: [String] = []

        // ★ 使用 async let 並行查詢兩個來源
        if isNotionAvailable && isNotebookLMAvailable {
            // 兩者都可用 → 並行
            async let notionTask: [NotionRetrievalResult] = {
                guard let notion = notionService else { return [] }
                return await notion.query(question: question, maxResults: 3)
            }()
            async let nlmTask: [NotebookLMResult] = notebookLMService.query(
                .forMeeting(question: question, notebookId: notebookLMConfig.notebookId)
            )

            let notionResults = await notionTask
            let nlmResults = await nlmTask

            if !notionResults.isEmpty {
                notionCtx = NotionRetrievalService.formatAsClaudeContext(notionResults)
                sources.append(contentsOf: notionResults.prefix(2).map { "📝 \($0.pageTitle)" })
                stats.notebookLMQueries += 1
            }
            if !nlmResults.isEmpty {
                nlmCtx = NotebookLMService.formatAsClaudeContext(nlmResults)
                sources.append(contentsOf: nlmResults.prefix(2).map { "📄 \($0.sourceTitle)" })
                stats.notebookLMQueries += 1
            }

        } else if isNotionAvailable, let notion = notionService {
            // 僅 Notion
            let results = await notion.query(question: question, maxResults: 3)
            if !results.isEmpty {
                notionCtx = NotionRetrievalService.formatAsClaudeContext(results)
                sources.append(contentsOf: results.prefix(2).map { "📝 \($0.pageTitle)" })
                stats.notebookLMQueries += 1
            }

        } else if isNotebookLMAvailable {
            // 僅 NotebookLM
            let results = await notebookLMService.query(
                .forMeeting(question: question, notebookId: notebookLMConfig.notebookId)
            )
            if !results.isEmpty {
                nlmCtx = NotebookLMService.formatAsClaudeContext(results)
                sources.append(contentsOf: results.prefix(2).map { "📄 \($0.sourceTitle)" })
                stats.notebookLMQueries += 1
            }
        }

        // ★ 合併兩個來源的 context
        let merged = mergeRAGContext(notionContext: notionCtx, notebookLMContext: nlmCtx)
        return (context: merged, sources: sources)
    }

    /// 合併 Notion（個人筆記）+ NotebookLM（文件數據）
    private func mergeRAGContext(notionContext: String, notebookLMContext: String) -> String {
        if notionContext.isEmpty && notebookLMContext.isEmpty { return "" }
        if notionContext.isEmpty { return notebookLMContext }
        if notebookLMContext.isEmpty { return notionContext }

        // 兩者都有結果 → 標註來源類型合併
        return """
        \(notebookLMContext)

        \(notionContext)

        【以上包含兩類來源：📄 文件原文數據 + 📝 個人策略筆記。請綜合兩者回答。】
        """
    }

    // ═ 三層即時管線 ═

    func processUpdate(_ update: TranscriptUpdate, tpStats: TPStats, unfinishedMust: [String]) async {
        // Layer 1: Local Q&A < 200ms
        if let match = await keywordMatcher.match(transcript: update.fullText) {
            let card = AICard(type: .qaMatch, title: "💡 \(match.item.question)",
                content: match.item.shortAnswer, confidence: match.confidence,
                latencyMs: match.latencyMs, timestamp: Date())
            insertCard(card); stats.localMatches += 1; stats.totalCards += 1
            emitEvent(.cardInserted(card)); return
        }

        guard let questionText = update.detectedQuestion else { return }
        let now = Date()
        guard now.timeIntervalSince(lastClaudeQueryTime) >= claudeMinInterval else { return }
        lastClaudeQueryTime = now

        // Layer 2: ★ 雙來源並行查詢
        emitEvent(.notebookLMQueryStarted)
        let ragResult = await parallelRAGQuery(question: questionText)
        emitEvent(.notebookLMQueryEnded)

        // Layer 3: Claude + merged context 2-4s
        emitEvent(.claudeStreamingStarted)
        let startTime = CFAbsoluteTimeGetCurrent(); var text = ""
        let ctx = MeetingContext(goals: meetingContext.goals,
            preAnalysisCache: meetingContext.preAnalysisCache + (ragResult.context.isEmpty ? "" : "\n\n\(ragResult.context)"),
            relevantQA: meetingContext.relevantQA, recentTranscript: String(update.fullText.suffix(500)),
            attendeeInfo: meetingContext.attendeeInfo, meetingType: meetingContext.meetingType)
        let stream = await claudeService.streamQuery(question: questionText, context: ctx)
        for await chunk in stream { text += chunk }
        let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        emitEvent(.claudeStreamingEnded)
        guard !text.isEmpty else { return }

        let hasDoc = !ragResult.context.isEmpty
        let sourceHint = ragResult.sources.isEmpty ? "" : " " + ragResult.sources.prefix(2).joined(separator: " + ")
        let card = AICard(type: .aiGenerated, title: "🤖 AI 即時建議\(sourceHint)",
            content: text, confidence: hasDoc ? 0.92 : 0.82, latencyMs: latency, timestamp: Date())
        insertCard(card); stats.claudeQueries += 1; stats.totalCards += 1; stats.totalClaudeLatencyMs += latency
        emitEvent(.cardInserted(card))
    }

    // ═ 策略分析 ═

    func runStrategyAnalysis(recentTranscript: String, tpStats: TPStats, unfinishedMust: [String]) async {
        let chunk = String(recentTranscript.suffix(1000))
        guard chunk.count > 100 else { return }
        let prompt = """
        分析最近 3 分鐘的會議逐字稿：
        1. 會議走向是否偏離目標？ 2. 對方是否有隱藏意圖？ 3. 接下來 5 分鐘應主動提什麼？
        TP: \(tpStats.completed)/\(tpStats.total) | MUST: \(unfinishedMust.isEmpty ? "全部完成" : unfinishedMust.joined(separator: "、"))
        回答限 80 字。逐字稿：\(chunk)
        """
        emitEvent(.claudeStreamingStarted)
        let t0 = CFAbsoluteTimeGetCurrent(); var text = ""
        let stream = await claudeService.streamQuery(question: prompt, context: meetingContext)
        for await c in stream { text += c }
        let lat = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        emitEvent(.claudeStreamingEnded)
        guard !text.isEmpty else { return }
        let card = AICard(type: .strategy, title: "📊 策略分析", content: text, confidence: 0.80, latencyMs: lat, timestamp: Date())
        insertCard(card); stats.strategyAnalyses += 1; stats.totalCards += 1; emitEvent(.cardInserted(card))
    }

    // ═ 手動提問 ═

    func manualQuery(_ question: String, fullTranscript: String) async {
        emitEvent(.claudeStreamingStarted)
        let t0 = CFAbsoluteTimeGetCurrent(); var text = ""

        // ★ 雙來源並行查詢
        emitEvent(.notebookLMQueryStarted)
        let ragResult = await parallelRAGQuery(question: question)
        emitEvent(.notebookLMQueryEnded)

        let ctx = MeetingContext(goals: meetingContext.goals,
            preAnalysisCache: meetingContext.preAnalysisCache + (ragResult.context.isEmpty ? "" : "\n\n\(ragResult.context)"),
            relevantQA: meetingContext.relevantQA, recentTranscript: String(fullTranscript.suffix(500)),
            attendeeInfo: meetingContext.attendeeInfo, meetingType: meetingContext.meetingType)
        let stream = await claudeService.streamQuery(question: question, context: ctx)
        for await c in stream { text += c }
        let lat = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        emitEvent(.claudeStreamingEnded)
        guard !text.isEmpty else { return }
        let card = AICard(type: .aiGenerated, title: "🤖 \(String(question.prefix(20)))...",
            content: text, confidence: 0.9, latencyMs: lat, timestamp: Date())
        insertCard(card); stats.claudeQueries += 1; stats.totalCards += 1; emitEvent(.cardInserted(card))
    }

    func handleTPReminder(_ reminder: TPReminder) {
        let t: AICard.AICardType = (reminder.urgency == .critical || reminder.urgency == .high) ? .warning : .strategy
        let card = AICard(type: t, title: "📋 TP 提醒", content: reminder.message, confidence: 1.0, latencyMs: 0, timestamp: reminder.timestamp)
        insertCard(card); stats.totalCards += 1; emitEvent(.cardInserted(card))
    }

    private func insertCard(_ card: AICard) {
        cards.insert(card, at: 0)
        if cards.count > 50 { cards = Array(cards.prefix(50)) }
    }
    private func emitEvent(_ type: OrchestratorEvent.EventType) {
        eventContinuation?.yield(OrchestratorEvent(type: type, timestamp: Date()))
    }
    func markSessionEnd() { stats.sessionEndTime = Date(); eventContinuation?.finish() }
}
