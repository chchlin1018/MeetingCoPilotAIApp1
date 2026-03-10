// ═══════════════════════════════════════════════════════════════════════════
// MeetingAICoordinator.swift
// MeetingCopilot v4.3 — 雙串流 Coordinator（說話者分離）
// ═══════════════════════════════════════════════════════════════════════════
//
//  v4.2 → v4.3 核心變更：
//  - TranscriptUpdate 新增 speaker: SpeakerSource (.remote / .local)
//  - .remote → ResponseOrchestrator（觸發問題偵測 + 三層管線）
//  - .local  → TalkingPointsTracker（偵測「我講了什麼」）
//  - UI 新增 hasDualStream 狀態指示
//
//  Platform: macOS 14.0+
// ═══════════════════════════════════════════════════════════════════════════

import Foundation
import SwiftUI

@Observable
@MainActor
final class MeetingAICoordinator {

    // MARK: UI 狀態
    private(set) var cards: [AICard] = []
    private(set) var fullTranscript: String = ""
    private(set) var recentTranscript: String = ""
    private(set) var captureState: AudioCaptureState = .idle
    private(set) var activeEngineType: AudioCaptureEngineType?
    private(set) var talkingPoints: [TalkingPoint] = []
    private(set) var tpStats: TPStats = TPStats(total: 0, completed: 0, mustTotal: 0, mustCompleted: 0, shouldTotal: 0, shouldCompleted: 0)
    private(set) var isNotebookLMAvailable: Bool = false
    private(set) var isNotebookLMQuerying: Bool = false
    private(set) var isClaudeStreaming: Bool = false
    private(set) var hasDualStream: Bool = false            // ★ v4.3 新增
    private(set) var stats = SessionStats()

    // MARK: 子系統
    private let pipeline: TranscriptPipeline
    private let orchestrator: ResponseOrchestrator
    private let tpTracker = TalkingPointsTracker()
    private var pipelineConsumerTask: Task<Void, Never>?
    private var eventConsumerTask: Task<Void, Never>?
    private var strategyTask: Task<Void, Never>?
    private var tpUpdateTask: Task<Void, Never>?

    init(claudeAPIKey: String, claudeModel: String = "claude-sonnet-4-20250514",
         notebookLMConfig: NotebookLMConfig = .default, meetingContext: MeetingContext) {
        self.pipeline = TranscriptPipeline()
        self.orchestrator = ResponseOrchestrator(claudeAPIKey: claudeAPIKey, claudeModel: claudeModel,
            notebookLMConfig: notebookLMConfig, meetingContext: meetingContext)
    }

    // MARK: 會前設定
    func loadKnowledgeBase(_ items: [QAItem]) async {
        await orchestrator.loadKnowledgeBase(items); stats.qaItemsLoaded = items.count
    }
    func loadTalkingPoints(_ points: [TalkingPoint], meetingDurationMinutes: Int = 60) async {
        await tpTracker.loadTalkingPoints(points, meetingDurationMinutes: meetingDurationMinutes)
        await syncTPState()
    }
    func updateContext(_ context: MeetingContext) async { await orchestrator.updateContext(context) }

    // MARK: 啟動會議
    func startMeeting(config: AudioCaptureConfiguration = .default) async {
        do {
            try await pipeline.start(config: config)
            self.captureState = await pipeline.captureState
            self.activeEngineType = await pipeline.activeEngineType
            self.hasDualStream = await pipeline.hasDualStream  // ★ v4.3
        } catch { self.captureState = .error(.engineStartFailed("引擎啟動失敗")); return }

        await orchestrator.checkNotebookLMAvailability()
        self.isNotebookLMAvailable = await orchestrator.isNotebookLMAvailable
        await tpTracker.markMeetingStarted()

        startPipelineConsumer(); startEventConsumer(); startPeriodicStrategy(); startTPUpdateLoop()
        stats.sessionStartTime = Date()
    }

    // MARK: 停止會議
    func stopMeeting() async {
        pipelineConsumerTask?.cancel(); eventConsumerTask?.cancel()
        strategyTask?.cancel(); tpUpdateTask?.cancel()
        await pipeline.stop(); await orchestrator.markSessionEnd()
        captureState = .idle; activeEngineType = nil
        isClaudeStreaming = false; isNotebookLMQuerying = false; hasDualStream = false
        stats = await orchestrator.stats; stats.sessionEndTime = Date()
        self.tpStats = await tpTracker.getStats()
    }

    // MARK: 手動操作
    func manualQuery(_ question: String) async {
        let t = await pipeline.fullTranscript
        await orchestrator.manualQuery(question, fullTranscript: t)
        self.cards = await orchestrator.cards; self.stats = await orchestrator.stats
    }
    func markTPCompleted(_ id: UUID) async { await tpTracker.markCompleted(id); await syncTPState() }
    func markTPSkipped(_ id: UUID) async { await tpTracker.markSkipped(id); await syncTPState() }

    // MARK: ★ 雙串流管線消費（v4.3 核心變更）
    private func startPipelineConsumer() {
        pipelineConsumerTask = Task { [weak self] in
            guard let self else { return }
            let updates = await self.pipeline.updates!
            for await update in updates {
                guard !Task.isCancelled else { break }

                // 更新 UI 逐字稿（雙方合併）
                self.fullTranscript = update.fullText
                self.recentTranscript = update.recentText

                switch update.speaker {
                case .remote:
                    // ★ 對方的聲音 → 進入三層管線（問題偵測 + AI 回應）
                    let tpStats = await self.tpTracker.getStats()
                    let unfinished = await self.tpTracker.getAllTalkingPoints()
                        .filter { $0.status == .pending && $0.priority == .must }.map { $0.content }
                    await self.orchestrator.processUpdate(update, tpStats: tpStats, unfinishedMust: unfinished)

                case .local:
                    // ★ 我的聲音 → 僅用於 TP 追蹤（偵測「我講了什麼」）
                    let reminders = await self.tpTracker.analyzeTranscript(update.segment.text)
                    await self.syncTPState()
                    for r in reminders { await self.orchestrator.handleTPReminder(r) }
                }
            }
        }
    }

    // ─── 事件消費（同步 Orchestrator → UI）───
    private func startEventConsumer() {
        eventConsumerTask = Task { [weak self] in
            guard let self else { return }
            let events = await self.orchestrator.events!
            for await event in events {
                guard !Task.isCancelled else { break }
                switch event.type {
                case .cardInserted: self.cards = await self.orchestrator.cards; self.stats = await self.orchestrator.stats
                case .claudeStreamingStarted: self.isClaudeStreaming = true
                case .claudeStreamingEnded: self.isClaudeStreaming = false
                case .notebookLMQueryStarted: self.isNotebookLMQuerying = true
                case .notebookLMQueryEnded: self.isNotebookLMQuerying = false
                case .statsUpdated(let s): self.stats = s
                }
            }
        }
    }

    // ─── 背景策略分析 ───
    private func startPeriodicStrategy() {
        strategyTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000_000)
            while !Task.isCancelled {
                guard let self else { break }
                let t = await self.pipeline.fullTranscript
                let tp = await self.tpTracker.getStats()
                let um = await self.tpTracker.getAllTalkingPoints()
                    .filter { $0.status == .pending && $0.priority == .must }.map { $0.content }
                await self.orchestrator.runStrategyAnalysis(recentTranscript: t, tpStats: tp, unfinishedMust: um)
                try? await Task.sleep(nanoseconds: 180_000_000_000)
            }
        }
    }

    private func startTPUpdateLoop() {
        tpUpdateTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self else { break }; await self.syncTPState()
            }
        }
    }

    private func syncTPState() async {
        self.talkingPoints = await tpTracker.getAllTalkingPoints()
        self.tpStats = await tpTracker.getStats()
    }
}

// MARK: - Session Stats

struct SessionStats {
    var sessionStartTime: Date?; var sessionEndTime: Date?
    var qaItemsLoaded: Int = 0; var localMatches: Int = 0; var notebookLMQueries: Int = 0
    var claudeQueries: Int = 0; var strategyAnalyses: Int = 0; var totalCards: Int = 0
    var totalClaudeLatencyMs: Double = 0
    var sessionDuration: TimeInterval? {
        guard let s = sessionStartTime else { return nil }; return (sessionEndTime ?? Date()).timeIntervalSince(s)
    }
    var averageClaudeLatencyMs: Double { claudeQueries > 0 ? totalClaudeLatencyMs / Double(claudeQueries) : 0 }
    var estimatedClaudeCost: Double { Double(claudeQueries + strategyAnalyses) * 0.022 }
    var summary: String {
        let d = sessionDuration.map { "\(Int($0 / 60))m" } ?? "N/A"
        return "\(d) | Cards: \(totalCards) (🔵\(localMatches) 📚\(notebookLMQueries) 🟣\(claudeQueries) 🟠\(strategyAnalyses)) | Lat: \(String(format: "%.0f", averageClaudeLatencyMs))ms | $\(String(format: "%.2f", estimatedClaudeCost))"
    }
}
