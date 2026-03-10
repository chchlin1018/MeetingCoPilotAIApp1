// ═══════════════════════════════════════════════════════════════════════════
// ResponseOrchestrator.swift
// MeetingCopilot v4.3 — 回應編排器（Notion + NotebookLM 雙第二層）
// ═══════════════════════════════════════════════════════════════════════════
//
//  第二層優先級：
//  1. Notion API（如果有設定 Notion API Key）
//  2. NotebookLM Bridge（fallback，如果有設定）
//  3. 都沒設定 → 跳過第二層，直接進 Claude
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
    private let notionService: NotionRetrievalService?     // ★ Notion
    private var meetingContext: MeetingContext
    private let notebookLMConfig: NotebookLMConfig

    private var lastClaudeQueryTime: Date = .distantPast
    private let claudeMinInterval: TimeInterval = 5.0

    private var eventContinuation: AsyncStream<OrchestratorEvent>.Continuation?
    private(set) var events: AsyncStream<OrchestratorEvent>!
    private(set) var isNotebookLMAvailable: Bool = false
    private(set) var isNotionAvailable: Bool = false        // ★

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

        // ★ Notion: 從 Keychain 讀取 API Key
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
        // ★ 優先檢查 Notion
        if let notion = notionService {
            isNotionAvailable = await notion.isAvailable
            if isNotionAvailable {
                print("📝 Notion RAG: Available (優先使用)")
            }
        }
        // 仍然檢查 NotebookLM（作為 fallback）
        isNotebookLMAvailable = await notebookLMService.isAvailable
        if isNotebookLMAvailable {
            print("📚 NotebookLM Bridge: Available \(isNotionAvailable ? "(fallback)" : "(主要)")")
        }
        if !isNotionAvailable && !isNotebookLMAvailable {
            print("⚠️ 第二層 RAG: 無可用服務，將直接使用 Claude")
        }
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

        // Layer 2: ★ Notion 優先，NotebookLM fallback
        var ragContext = ""
        var ragSource = ""
        emitEvent(.notebookLMQueryStarted)

        if isNotionAvailable, let notion = notionService {
            let results = await notion.query(question: questionText, maxResults: 3)
            if !results.isEmpty {
                ragContext = NotionRetrievalService.formatAsClaudeContext(results)
                ragSource = results.first?.pageTitle ?? "Notion"
                stats.notebookLMQueries += 1  // 共用統計欄位
            }
        }

        // Notion 沒結果，試 NotebookLM
        if ragContext.isEmpty && isNotebookLMAvailable {
            let nbResults = await notebookLMService.query(.forMeeting(question: questionText, notebookId: notebookLMConfig.notebookId))
            if !nbResults.isEmpty {
                ragContext = NotebookLMService.formatAsClaudeContext(nbResults)
                ragSource = nbResults.first?.sourceTitle ?? "NotebookLM"
                stats.notebookLMQueries += 1
            }
        }

        emitEvent(.notebookLMQueryEnded)

        // Layer 3: Claude + context 2-4s
        emitEvent(.claudeStreamingStarted)
        let startTime = CFAbsoluteTimeGetCurrent(); var text = ""
        let ctx = MeetingContext(goals: meetingContext.goals,
            preAnalysisCache: meetingContext.preAnalysisCache + (ragContext.isEmpty ? "" : "\n\n\(ragContext)"),
            relevantQA: meetingContext.relevantQA, recentTranscript: String(update.fullText.suffix(500)),
            attendeeInfo: meetingContext.attendeeInfo, meetingType: meetingContext.meetingType)
        let stream = await claudeService.streamQuery(question: questionText, context: ctx)
        for await chunk in stream { text += chunk }
        let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        emitEvent(.claudeStreamingEnded)
        guard !text.isEmpty else { return }

        let hasDoc = !ragContext.isEmpty
        let hint = hasDoc ? " 📄 \(ragSource)" : ""
        let card = AICard(type: .aiGenerated, title: "🤖 AI 即時建議\(hint)",
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
        var ragCtx = ""

        // ★ Notion 優先
        emitEvent(.notebookLMQueryStarted)
        if isNotionAvailable, let notion = notionService {
            let r = await notion.query(question: question, maxResults: 3)
            ragCtx = NotionRetrievalService.formatAsClaudeContext(r)
        }
        if ragCtx.isEmpty && isNotebookLMAvailable {
            let r = await notebookLMService.query(.forMeeting(question: question, notebookId: notebookLMConfig.notebookId))
            ragCtx = NotebookLMService.formatAsClaudeContext(r)
        }
        emitEvent(.notebookLMQueryEnded)

        let ctx = MeetingContext(goals: meetingContext.goals,
            preAnalysisCache: meetingContext.preAnalysisCache + (ragCtx.isEmpty ? "" : "\n\n\(ragCtx)"),
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
