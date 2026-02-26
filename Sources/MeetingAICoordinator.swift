// ═══════════════════════════════════════════════════════════════════════════
// MeetingAICoordinator.swift
// MeetingCopilot v4.1 — 三層即時管線總指揮
// ═══════════════════════════════════════════════════════════════════════════
//
//  v4.0 → v4.1 核心變更：雙路徑 → 三層管線 + Talking Points 追蹤
//
//  ┌─────────────────────────────────────────────────────────────┐
//  │  音訊 → 轉錄 → 問題偵測                                      │
//  │              │                                               │
//  │    ┌─────────┴──────────┐                                    │
//  │    │                     │                                    │
//  │    ▼                     ▼                                    │
//  │  ① 本地 Q&A           ② NotebookLM                         │
//  │  匹配 < 200ms         RAG 查詢 1-3s                          │
//  │    │                     │                                    │
//  │    │ 命中               │ 找到相關段落                         │
//  │    ▼                     ▼                                    │
//  │  🔵 藍色卡片          ③ Claude Sonnet                       │
//  │  （預載答案）          + NotebookLM context                   │
//  │                        2-4s streaming                        │
//  │                          │                                    │
//  │                          ▼                                    │
//  │                       🟣 紫色卡片                             │
//  │                       （AI + 文件佐證）                       │
//  │                                                              │
//  │  背景：每 3 分鐘 → 🟠 橘色卡片（策略分析 + TP 狀態）         │
//  │  持續：TP 追蹤   → 🟢 面板指示器 + ⚠️ 黃色提醒卡片           │
//  └─────────────────────────────────────────────────────────────┘
//
//  延遲預算（v4.1）：
//  ┌──────────────────────┬───────────┬──────────────────────────┐
//  │ 階段                 │ 延遲目標  │ 引擎                      │
//  ├──────────────────────┼───────────┼──────────────────────────┤
//  │ 音訊擷取             │ 即時      │ ScreenCaptureKit          │
//  │ 語音轉文字           │ 300-500ms │ Apple Speech (partial)    │
//  │ 問題偵測             │ ~100ms    │ QuestionDetector          │
//  │ ① Q&A 匹配（命中）  │ < 50ms   │ KeywordMatcher            │
//  │ ② NotebookLM 查詢   │ 1-3s     │ notebooklm-kit bridge    │
//  │ ③ Claude + context   │ 2-4s     │ Claude Sonnet Streaming   │
//  │ TP 追蹤              │ < 50ms   │ TalkingPointsTracker      │
//  │ 策略建議（背景）     │ 2-4s     │ Claude Sonnet (定時)      │
//  ├──────────────────────┼───────────┼──────────────────────────┤
//  │ 端到端（① 命中）     │ < 1s ✅  │                           │
//  │ 端到端（② + ③）     │ 3-7s ⚠️  │ Streaming 緩解等待感      │
//  │ 端到端（③ 無 ②）    │ < 5s     │ NotebookLM 不可用時       │
//  └──────────────────────┴───────────┴──────────────────────────┘
//
//  Platform: macOS 14.0+
// ═══════════════════════════════════════════════════════════════════════════

import Foundation
import SwiftUI

// MARK: - Coordinator

@Observable
@MainActor
final class MeetingAICoordinator {

    // ─────────────────────────────────────────────────────────
    // MARK: UI 狀態（SwiftUI 綁定）
    // ─────────────────────────────────────────────────────────

    /// AI 卡片（倒序，最新在前）
    private(set) var cards: [AICard] = []

    /// 即時逐字稿
    private(set) var fullTranscript: String = ""
    private(set) var recentTranscript: String = ""

    /// 引擎狀態
    private(set) var captureState: AudioCaptureState = .idle
    private(set) var activeEngineType: AudioCaptureEngineType?

    /// Talking Points 即時狀態
    private(set) var talkingPoints: [TalkingPoint] = []
    private(set) var tpStats: TPStats = TPStats(
        total: 0, completed: 0,
        mustTotal: 0, mustCompleted: 0,
        shouldTotal: 0, shouldCompleted: 0
    )

    /// NotebookLM 狀態
    private(set) var isNotebookLMAvailable: Bool = false
    private(set) var isNotebookLMQuerying: Bool = false

    /// Claude 狀態
    private(set) var isClaudeStreaming: Bool = false

    /// 統計
    private(set) var stats = SessionStats()

    // ─────────────────────────────────────────────────────────
    // MARK: 內部元件
    // ─────────────────────────────────────────────────────────

    private var audioEngine: (any AudioCaptureEngine)?
    private let keywordMatcher = KeywordMatcher()
    private let claudeService: ClaudeService
    private let notebookLMService: NotebookLMService
    private let tpTracker = TalkingPointsTracker()
    private var meetingContext: MeetingContext

    // Tasks
    private var transcriptConsumerTask: Task<Void, Never>?
    private var strategyAnalysisTask: Task<Void, Never>?
    private var tpUpdateTask: Task<Void, Never>?

    // 問題偵測
    private let questionDetector = QuestionDetector()

    // Claude 節流：5 秒最小間隔
    private var lastClaudeQueryTime: Date = .distantPast
    private let claudeMinInterval: TimeInterval = 5.0

    // 策略分析間隔：3 分鐘
    private let strategyInterval: TimeInterval = 180.0

    // NotebookLM 設定
    private let notebookLMConfig: NotebookLMConfig

    // ─────────────────────────────────────────────────────────
    // MARK: 初始化
    // ─────────────────────────────────────────────────────────

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
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: 會前設定
    // ═══════════════════════════════════════════════════════════

    /// 載入 Q&A 知識庫（第一層用）
    func loadKnowledgeBase(_ items: [QAItem]) async {
        await keywordMatcher.loadKnowledgeBase(items)
        stats.qaItemsLoaded = items.count
    }

    /// 載入 Talking Points
    func loadTalkingPoints(
        _ points: [TalkingPoint],
        meetingDurationMinutes: Int = 60
    ) async {
        await tpTracker.loadTalkingPoints(
            points, meetingDurationMinutes: meetingDurationMinutes)
        self.talkingPoints = await tpTracker.getAllTalkingPoints()
        self.tpStats = await tpTracker.getStats()
    }

    /// 更新會議脈絡
    func updateContext(_ context: MeetingContext) {
        self.meetingContext = context
    }

    /// 檢查 NotebookLM 是否可用
    func checkNotebookLMAvailability() async {
        isNotebookLMAvailable = await notebookLMService.isAvailable
        print(isNotebookLMAvailable
            ? "✅ NotebookLM connected (Notebook: \(notebookLMConfig.notebookId))"
            : "⚠️ NotebookLM not available — Layer 2 will be skipped")
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: 啟動會議
    // ═══════════════════════════════════════════════════════════

    func startMeeting(config: AudioCaptureConfiguration = .default) async {

        // Step 1: 音訊引擎（主引擎 → 降級）
        let systemEngine = SystemAudioCaptureEngine(configuration: config)
        do {
            try await systemEngine.start()
            self.audioEngine = systemEngine
            self.activeEngineType = .systemAudio
            self.captureState = .capturing
        } catch {
            let micEngine = MicrophoneCaptureEngine(configuration: config)
            do {
                try await micEngine.start()
                self.audioEngine = micEngine
                self.activeEngineType = .microphone
                self.captureState = .capturing
            } catch {
                self.captureState = .error(
                    .engineStartFailed("所有引擎都無法啟動"))
                return
            }
        }

        // Step 2: 檢查 NotebookLM
        await checkNotebookLMAvailability()

        // Step 3: TP 追蹤開始
        await tpTracker.markMeetingStarted()

        // Step 4: 啟動所有消費管線
        startTranscriptConsumer()
        startPeriodicStrategyAnalysis()
        startTPUpdateLoop()

        stats.sessionStartTime = Date()
        print("🎬 Meeting started | Engine: \(activeEngineType?.rawValue ?? "?") "
            + "| NotebookLM: \(isNotebookLMAvailable) "
            + "| TPs: \(talkingPoints.count)")
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: 停止會議
    // ═══════════════════════════════════════════════════════════

    func stopMeeting() async {
        transcriptConsumerTask?.cancel()
        strategyAnalysisTask?.cancel()
        tpUpdateTask?.cancel()
        transcriptConsumerTask = nil
        strategyAnalysisTask = nil
        tpUpdateTask = nil

        await audioEngine?.stop()
        audioEngine = nil

        captureState = .idle
        activeEngineType = nil
        isClaudeStreaming = false
        isNotebookLMQuerying = false

        stats.sessionEndTime = Date()
        self.tpStats = await tpTracker.getStats()

        print("🛑 Meeting ended | \(stats.summary) | \(tpStats.summary)")
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: Transcript Consumer（管線入口）
    // ═══════════════════════════════════════════════════════════

    private func startTranscriptConsumer() {
        guard let engine = audioEngine else { return }

        transcriptConsumerTask = Task { [weak self] in
            for await segment in engine.transcriptStream {
                guard let self = self, !Task.isCancelled else { break }

                // 更新逐字稿
                self.fullTranscript = segment.text
                self.recentTranscript = segment.recentText

                guard segment.text.count > 5 else { continue }

                // TP 追蹤（每次 transcript 都要跑）
                let reminders = await self.tpTracker.analyzeTranscript(
                    segment.text)
                self.talkingPoints = await self.tpTracker.getAllTalkingPoints()
                self.tpStats = await self.tpTracker.getStats()

                for reminder in reminders {
                    self.handleTPReminder(reminder)
                }

                // ★ 三層管線
                await self.processThreeLayerPipeline(segment)
            }
        }
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: ★★★ 三層即時管線（核心邏輯）★★★
    // ═══════════════════════════════════════════════════════════

    private func processThreeLayerPipeline(
        _ segment: TranscriptSegment
    ) async {

        // ─────────────────────────────────────────────────────
        // 第一層：本地 Q&A 匹配（< 200ms）
        // 預載的精確答案，命中即返回，不走後續層
        // ─────────────────────────────────────────────────────

        if let matchResult = await keywordMatcher.match(
            transcript: segment.text
        ) {
            let card = AICard(
                type: .qaMatch,
                title: "💡 \(matchResult.item.question)",
                content: matchResult.item.shortAnswer,
                confidence: matchResult.confidence,
                latencyMs: matchResult.latencyMs,
                timestamp: Date()
            )
            insertCard(card)
            stats.localMatches += 1
            stats.totalCards += 1
            print("🔵 Layer 1 HIT | \(String(format: "%.0f", matchResult.latencyMs))ms "
                + "[\(matchResult.matchedKeywords.joined(separator: ", "))]")
            return  // ← 命中即返回
        }

        // ─────────────────────────────────────────────────────
        // 問題偵測閘門：只有偵測到疑問句才進入第二、三層
        // ─────────────────────────────────────────────────────

        let recentText = String(segment.text.suffix(60))
        guard questionDetector.isQuestion(recentText) else { return }

        // Claude 節流
        let now = Date()
        guard now.timeIntervalSince(lastClaudeQueryTime) >= claudeMinInterval else {
            return
        }
        lastClaudeQueryTime = now

        // ─────────────────────────────────────────────────────
        // 第二層：NotebookLM RAG 查詢（1-3s）
        // 從用戶準備的大量文件中找最相關段落
        // ─────────────────────────────────────────────────────

        var notebookLMContext = ""
        var notebookLMResults: [NotebookLMResult] = []

        if isNotebookLMAvailable {
            isNotebookLMQuerying = true

            let query = NotebookLMQuery.forMeeting(
                question: recentText,
                notebookId: notebookLMConfig.notebookId
            )
            notebookLMResults = await notebookLMService.query(query)
            notebookLMContext = NotebookLMService.formatAsClaudeContext(
                notebookLMResults)

            isNotebookLMQuerying = false
            stats.notebookLMQueries += 1

            if !notebookLMResults.isEmpty {
                print("📚 Layer 2 | \(notebookLMResults.count) passages "
                    + "[\(notebookLMResults.map { $0.sourceTitle }.joined(separator: ", "))]")
            }
        }

        // ─────────────────────────────────────────────────────
        // 第三層：Claude + NotebookLM context（2-4s streaming）
        // 用第二層找到的段落當 context，產生有文件佐證的回答
        // ─────────────────────────────────────────────────────

        isClaudeStreaming = true
        let startTime = CFAbsoluteTimeGetCurrent()
        var accumulatedText = ""

        // 構建增強版 context（含 NotebookLM 結果）
        let enhancedContext = MeetingContext(
            goals: meetingContext.goals,
            preAnalysisCache: meetingContext.preAnalysisCache
                + (notebookLMContext.isEmpty ? "" : "\n\n\(notebookLMContext)"),
            relevantQA: meetingContext.relevantQA,
            recentTranscript: String(fullTranscript.suffix(500)),
            attendeeInfo: meetingContext.attendeeInfo,
            meetingType: meetingContext.meetingType
        )

        let stream = await claudeService.streamQuery(
            question: recentText,
            context: enhancedContext
        )

        for await chunk in stream {
            accumulatedText += chunk
        }

        let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        isClaudeStreaming = false

        guard !accumulatedText.isEmpty else { return }

        // 卡片標題標示是否有文件佐證
        let hasDocEvidence = !notebookLMResults.isEmpty
        let sourceHint = hasDocEvidence
            ? " 📄 \(notebookLMResults.first?.sourceTitle ?? "")"
            : ""

        let card = AICard(
            type: .aiGenerated,
            title: "🤖 AI 即時建議\(sourceHint)",
            content: accumulatedText,
            confidence: hasDocEvidence ? 0.92 : 0.82,
            latencyMs: latency,
            timestamp: Date()
        )

        insertCard(card)
        stats.claudeQueries += 1
        stats.totalCards += 1
        stats.totalClaudeLatencyMs += latency

        print("🟣 Layer 3 | Claude\(hasDocEvidence ? " + NotebookLM" : "") "
            + "| \(String(format: "%.0f", latency))ms | \(accumulatedText.count) chars")
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: TP 提醒處理
    // ═══════════════════════════════════════════════════════════

    private func handleTPReminder(_ reminder: TPReminder) {
        let cardType: AICard.AICardType
        switch reminder.urgency {
        case .critical, .high: cardType = .warning
        case .medium, .low:    cardType = .strategy
        }

        let card = AICard(
            type: cardType,
            title: "📋 TP 提醒",
            content: reminder.message,
            confidence: 1.0,
            latencyMs: 0,
            timestamp: reminder.timestamp
        )
        insertCard(card)
        stats.totalCards += 1
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: TP 狀態定期更新（5 秒）
    // ═══════════════════════════════════════════════════════════

    private func startTPUpdateLoop() {
        tpUpdateTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self = self else { break }
                self.talkingPoints = await self.tpTracker.getAllTalkingPoints()
                self.tpStats = await self.tpTracker.getStats()
            }
        }
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: 背景策略分析（每 3 分鐘）
    // ═══════════════════════════════════════════════════════════

    private func startPeriodicStrategyAnalysis() {
        strategyAnalysisTask = Task { [weak self] in
            // 首次等 2 分鐘
            try? await Task.sleep(nanoseconds: 120_000_000_000)

            while !Task.isCancelled {
                guard let self = self else { break }
                await self.runStrategyAnalysis()
                try? await Task.sleep(
                    nanoseconds: UInt64(self.strategyInterval * 1_000_000_000))
            }
        }
    }

    private func runStrategyAnalysis() async {
        let recentChunk = String(fullTranscript.suffix(1000))
        guard recentChunk.count > 100 else { return }

        // 把 TP 狀態納入策略分析
        let tpStatus = await tpTracker.getStats()
        let unfinishedMust = await tpTracker.getAllTalkingPoints()
            .filter { $0.status == .pending && $0.priority == .must }
            .map { $0.content }

        let strategyPrompt = """
        分析最近 3 分鐘的會議逐字稿：
        1. 會議走向是否偏離目標？
        2. 對方是否有隱藏意圖或迴避話題？
        3. 接下來 5 分鐘應主動提出什麼？

        TP 狀態：\(tpStatus.completed)/\(tpStatus.total) 完成
        未完成 MUST：\(unfinishedMust.isEmpty
            ? "（全部完成）"
            : unfinishedMust.joined(separator: "、"))

        回答限 80 字以內。

        逐字稿：\(recentChunk)
        """

        let startTime = CFAbsoluteTimeGetCurrent()
        var text = ""

        let stream = await claudeService.streamQuery(
            question: strategyPrompt, context: meetingContext)
        for await chunk in stream { text += chunk }
        let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        guard !text.isEmpty else { return }

        insertCard(AICard(
            type: .strategy,
            title: "📊 策略分析",
            content: text,
            confidence: 0.80,
            latencyMs: latency,
            timestamp: Date()
        ))
        stats.strategyAnalyses += 1
        stats.totalCards += 1
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: 手動操作
    // ═══════════════════════════════════════════════════════════

    /// 手動提問（也走 NotebookLM → Claude 管線）
    func manualQuery(_ question: String) async {
        isClaudeStreaming = true
        let startTime = CFAbsoluteTimeGetCurrent()
        var text = ""

        // 手動提問也走第二層
        var notebookContext = ""
        if isNotebookLMAvailable {
            isNotebookLMQuerying = true
            let results = await notebookLMService.query(
                .forMeeting(question: question,
                            notebookId: notebookLMConfig.notebookId))
            notebookContext = NotebookLMService.formatAsClaudeContext(results)
            isNotebookLMQuerying = false
        }

        let enhancedContext = MeetingContext(
            goals: meetingContext.goals,
            preAnalysisCache: meetingContext.preAnalysisCache
                + (notebookContext.isEmpty ? "" : "\n\n\(notebookContext)"),
            relevantQA: meetingContext.relevantQA,
            recentTranscript: String(fullTranscript.suffix(500)),
            attendeeInfo: meetingContext.attendeeInfo,
            meetingType: meetingContext.meetingType
        )

        let stream = await claudeService.streamQuery(
            question: question, context: enhancedContext)
        for await chunk in stream { text += chunk }

        let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        isClaudeStreaming = false
        guard !text.isEmpty else { return }

        insertCard(AICard(
            type: .aiGenerated,
            title: "🤖 \(String(question.prefix(20)))...",
            content: text,
            confidence: 0.9,
            latencyMs: latency,
            timestamp: Date()
        ))
        stats.claudeQueries += 1
        stats.totalCards += 1
    }

    /// 手動標記 TP
    func markTPCompleted(_ id: UUID) async {
        await tpTracker.markCompleted(id)
        self.talkingPoints = await tpTracker.getAllTalkingPoints()
        self.tpStats = await tpTracker.getStats()
    }

    func markTPSkipped(_ id: UUID) async {
        await tpTracker.markSkipped(id)
        self.talkingPoints = await tpTracker.getAllTalkingPoints()
        self.tpStats = await tpTracker.getStats()
    }

    // ─────────────────────────────────────────────────────────
    // MARK: 卡片管理
    // ─────────────────────────────────────────────────────────

    private func insertCard(_ card: AICard) {
        cards.insert(card, at: 0)
        if cards.count > 50 { cards = Array(cards.prefix(50)) }
    }
}


// ═══════════════════════════════════════════════════════════════════════════
// MARK: - 問題偵測器
// ═══════════════════════════════════════════════════════════════════════════

struct QuestionDetector: Sendable {

    private let questionPatterns: [String] = [
        // 中文疑問詞
        "嗎", "什麼", "怎麼", "為什麼", "如何", "哪裡", "哪些", "哪個",
        "幾", "多少", "能不能", "可不可以", "是否", "有沒有",
        "呢", "吧", "請問", "想問", "請教", "好奇",
        "比較", "差異", "不同", "優勢", "劣勢",
        // 英文疑問詞
        "what", "how", "why", "when", "where", "which", "who",
        "can you", "could you", "would you",
        "tell me", "explain", "describe",
        "difference", "compare", "advantage",
        "？", "?"
    ]

    func isQuestion(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return questionPatterns.contains { lowered.contains($0) }
    }
}


// ═══════════════════════════════════════════════════════════════════════════
// MARK: - 會議統計（v4.1 擴充）
// ═══════════════════════════════════════════════════════════════════════════

struct SessionStats {
    var sessionStartTime: Date?
    var sessionEndTime: Date?
    var qaItemsLoaded: Int = 0
    var localMatches: Int = 0          // 🔵 第一層
    var notebookLMQueries: Int = 0     // 📚 第二層（v4.1 新增）
    var claudeQueries: Int = 0         // 🟣 第三層
    var strategyAnalyses: Int = 0      // 🟠 策略分析
    var totalCards: Int = 0
    var totalClaudeLatencyMs: Double = 0

    var sessionDuration: TimeInterval? {
        guard let start = sessionStartTime else { return nil }
        return (sessionEndTime ?? Date()).timeIntervalSince(start)
    }

    var averageClaudeLatencyMs: Double {
        claudeQueries > 0 ? totalClaudeLatencyMs / Double(claudeQueries) : 0
    }

    /// 每次 Claude 查詢約 $0.022（Sonnet input + output）
    var estimatedClaudeCost: Double {
        Double(claudeQueries + strategyAnalyses) * 0.022
    }

    var summary: String {
        let dur = sessionDuration.map { "\(Int($0 / 60))m" } ?? "N/A"
        return "\(dur) | Cards: \(totalCards) "
            + "(🔵\(localMatches) 📚\(notebookLMQueries) "
            + "🟣\(claudeQueries) 🟠\(strategyAnalyses)) | "
            + "Latency: \(String(format: "%.0f", averageClaudeLatencyMs))ms | "
            + "Cost: $\(String(format: "%.2f", estimatedClaudeCost))"
    }
}
