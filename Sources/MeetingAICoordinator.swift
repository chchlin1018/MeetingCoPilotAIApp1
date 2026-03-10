// ═══════════════════════════════════════════════════════════════════════════
// MeetingAICoordinator.swift
// MeetingCopilot v4.3 — 雙串流 Coordinator + SwiftData Persistence
// ═══════════════════════════════════════════════════════════════════════════
//
//  v4.3 完整功能：
//  - 雙串流說話者分離 (.remote / .local)
//  - SwiftData 會議記錄持久化（startMeeting 建立 / stopMeeting 存入）
//  - Transcript + Card 即時存入 DB
//
//  Platform: macOS 14.0+
// ═══════════════════════════════════════════════════════════════════════════

import Foundation
import SwiftUI
import SwiftData

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
    private(set) var hasDualStream: Bool = false
    private(set) var stats = SessionStats()

    // MARK: 子系統
    private let pipeline: TranscriptPipeline
    private let orchestrator: ResponseOrchestrator
    private let tpTracker = TalkingPointsTracker()
    private var pipelineConsumerTask: Task<Void, Never>?
    private var eventConsumerTask: Task<Void, Never>?
    private var strategyTask: Task<Void, Never>?
    private var tpUpdateTask: Task<Void, Never>?

    // ★ Persistence
    private var currentSessionRecord: MeetingSessionRecord?
    private let modelContext: ModelContext

    init(claudeAPIKey: String, claudeModel: String = "claude-sonnet-4-20250514",
         notebookLMConfig: NotebookLMConfig = .default, meetingContext: MeetingContext) {
        self.pipeline = TranscriptPipeline()
        self.orchestrator = ResponseOrchestrator(claudeAPIKey: claudeAPIKey, claudeModel: claudeModel,
            notebookLMConfig: notebookLMConfig, meetingContext: meetingContext)
        self.modelContext = ModelContext(MeetingDataStore.container)
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
            self.hasDualStream = await pipeline.hasDualStream
        } catch { self.captureState = .error(.engineStartFailed("引擎啟動失敗")); return }

        await orchestrator.checkNotebookLMAvailability()
        self.isNotebookLMAvailable = await orchestrator.isNotebookLMAvailable
        await tpTracker.markMeetingStarted()

        // ★ Persistence: 建立會議記錄
        let record = MeetingSessionRecord(
            startTime: Date(),
            engineType: activeEngineType?.rawValue ?? "unknown",
            hasDualStream: hasDualStream
        )
        modelContext.insert(record)
        currentSessionRecord = record
        try? modelContext.save()

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

        // ★ Persistence: 存入會議統計
        if let record = currentSessionRecord {
            record.updateFromStats(stats, tpStats: tpStats)
            try? modelContext.save()
        }
        currentSessionRecord = nil
    }

    // MARK: 手動操作
    func manualQuery(_ question: String) async {
        let t = await pipeline.fullTranscript
        await orchestrator.manualQuery(question, fullTranscript: t)
        self.cards = await orchestrator.cards; self.stats = await orchestrator.stats
    }
    func markTPCompleted(_ id: UUID) async { await tpTracker.markCompleted(id); await syncTPState() }
    func markTPSkipped(_ id: UUID) async { await tpTracker.markSkipped(id); await syncTPState() }

    // MARK: 雙串流管線消費
    private func startPipelineConsumer() {
        pipelineConsumerTask = Task { [weak self] in
            guard let self else { return }
            let updates = await self.pipeline.updates!
            for await update in updates {
                guard !Task.isCancelled else { break }
                self.fullTranscript = update.fullText
                self.recentTranscript = update.recentText

                // ★ Persistence: 存入逐字稿
                if let record = self.currentSessionRecord, update.segment.text.count > 10 {
                    let tr = TranscriptRecord(timestamp: update.segment.timestamp,
                        text: update.segment.text, speaker: update.speaker.rawValue,
                        isFinal: update.segment.isFinal, confidence: update.segment.confidence)
                    tr.session = record
                    record.transcripts.append(tr)
                }

                switch update.speaker {
                case .remote:
                    let tpStats = await self.tpTracker.getStats()
                    let unfinished = await self.tpTracker.getAllTalkingPoints()
                        .filter { $0.status == .pending && $0.priority == .must }.map { $0.content }
                    await self.orchestrator.processUpdate(update, tpStats: tpStats, unfinishedMust: unfinished)
                case .local:
                    let reminders = await self.tpTracker.analyzeTranscript(update.segment.text)
                    await self.syncTPState()
                    for r in reminders { await self.orchestrator.handleTPReminder(r) }
                }
            }
        }
    }

    private func startEventConsumer() {
        eventConsumerTask = Task { [weak self] in
            guard let self else { return }
            let events = await self.orchestrator.events!
            for await event in events {
                guard !Task.isCancelled else { break }
                switch event.type {
                case .cardInserted(let card):
                    self.cards = await self.orchestrator.cards
                    self.stats = await self.orchestrator.stats
                    // ★ Persistence: 存入卡片
                    if let record = self.currentSessionRecord {
                        let cr = CardRecord(timestamp: card.timestamp, cardType: card.type.rawValue,
                            title: card.title, content: card.content, confidence: card.confidence,
                            latencyMs: card.latencyMs, pipelineLayer: card.type.rawValue)
                        cr.session = record
                        record.cards.append(cr)
                    }
                case .claudeStreamingStarted: self.isClaudeStreaming = true
                case .claudeStreamingEnded: self.isClaudeStreaming = false
                case .notebookLMQueryStarted: self.isNotebookLMQuerying = true
                case .notebookLMQueryEnded: self.isNotebookLMQuerying = false
                case .statsUpdated(let s): self.stats = s
                }
            }
        }
    }

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
