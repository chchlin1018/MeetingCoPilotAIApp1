// ═══════════════════════════════════════════════════════════════════════════
// ResponseOrchestrator.swift
// MeetingCopilot v4.2 — 回應編排器（從 Coordinator 拆出）
// ═══════════════════════════════════════════════════════════════════════════
//
//  單一職責：
//  1. 三層管線路由（本地匹配 → NotebookLM → Claude）
//  2. 背景策略分析（每 3 分鐘）
//  3. 手動提問處理
//  4. 卡片生成與管理
//
//  不負責：音訊擷取、轉錄、UI 狀態綁定、TP 追蹤
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
    private var meetingContext: MeetingContext
    private let notebookLMConfig: NotebookLMConfig

    private var lastClaudeQueryTime: Date = .distantPast
    private let claudeMinInterval: TimeInterval = 5.0

    private var eventContinuation: AsyncStream<OrchestratorEvent>.Continuation?
    private(set) var events: AsyncStream<OrchestratorEvent>!
    private(set) var isNotebookLMAvailable: Bool = false

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
        var cont: AsyncStream<OrchestratorEvent>.Continuation!
        self.events = AsyncStream { cont = $0 }
        self.eventContinuation = cont
    }

    func loadKnowledgeBase(_ items: [QAItem]) async {
        await keywordMatcher.loadKnowledgeBase(items)
        stats.qaItemsLoaded = items.count
    }

    func updateContext(_ context: MeetingContext) { self.meetingContext = context }
    func checkNotebookLMAvailability() async { isNotebookLMAvailable = await notebookLMService.isAvailable }

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

        // Layer 2: NotebookLM RAG 1-3s
        var nbContext = ""; var nbResults: [NotebookLMResult] = []
        if isNotebookLMAvailable {
            emitEvent(.notebookLMQueryStarted)
            nbResults = await notebookLMService.query(.forMeeting(question: questionText, notebookId: notebookLMConfig.notebookId))
            nbContext = NotebookLMService.formatAsClaudeContext(nbResults)
            emitEvent(.notebookLMQueryEnded); stats.notebookLMQueries += 1
        }

        // Layer 3: Claude + context 2-4s
        emitEvent(.claudeStreamingStarted)
        let startTime = CFAbsoluteTimeGetCurrent(); var text = ""
        let ctx = MeetingContext(goals: meetingContext.goals,
            preAnalysisCache: meetingContext.preAnalysisCache + (nbContext.isEmpty ? "" : "\n\n\(nbContext)"),
            relevantQA: meetingContext.relevantQA, recentTranscript: String(update.fullText.suffix(500)),
            attendeeInfo: meetingContext.attendeeInfo, meetingType: meetingContext.meetingType)
        let stream = await claudeService.streamQuery(question: questionText, context: ctx)
        for await chunk in stream { text += chunk }
        let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        emitEvent(.claudeStreamingEnded)
        guard !text.isEmpty else { return }

        let hasDoc = !nbResults.isEmpty
        let hint = hasDoc ? " 📄 \(nbResults.first?.sourceTitle ?? "")" : ""
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
        var nbCtx = ""
        if isNotebookLMAvailable {
            emitEvent(.notebookLMQueryStarted)
            let r = await notebookLMService.query(.forMeeting(question: question, notebookId: notebookLMConfig.notebookId))
            nbCtx = NotebookLMService.formatAsClaudeContext(r)
            emitEvent(.notebookLMQueryEnded)
        }
        let ctx = MeetingContext(goals: meetingContext.goals,
            preAnalysisCache: meetingContext.preAnalysisCache + (nbCtx.isEmpty ? "" : "\n\n\(nbCtx)"),
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
