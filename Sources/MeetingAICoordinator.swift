// ═══════════════════════════════════════════════════════════════════════════
// MeetingAICoordinator.swift
// MeetingCopilot v4.3.1 — + App Selection + Audio Health
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
    private(set) var transcriptEntries: [TranscriptEntry] = []
    private(set) var captureState: AudioCaptureState = .idle
    private(set) var activeEngineType: AudioCaptureEngineType?
    private(set) var talkingPoints: [TalkingPoint] = []
    private(set) var tpStats: TPStats = TPStats(total: 0, completed: 0, mustTotal: 0, mustCompleted: 0, shouldTotal: 0, shouldCompleted: 0)
    private(set) var isNotebookLMAvailable: Bool = false
    private(set) var isNotebookLMQuerying: Bool = false
    private(set) var isClaudeStreaming: Bool = false
    private(set) var hasDualStream: Bool = false
    private(set) var stats = SessionStats()

    // ★ Audio Health
    private(set) var audioHealth = AudioHealthStatus(
        remoteActive: false, localActive: false,
        remoteLastReceived: nil, localLastReceived: nil,
        remoteSegmentCount: 0, localSegmentCount: 0,
        startupMessage: nil, detectedAppName: nil
    )

    // ★ App Selection
    var detectedApps: [DetectedAppInfo] = []
    var showAppPicker: Bool = false
    var isScanning: Bool = false
    private(set) var detectedAppName: String = ""

    // MARK: 子系統
    private let pipeline: TranscriptPipeline
    private let orchestrator: ResponseOrchestrator
    private let tpTracker = TalkingPointsTracker()
    private var pipelineConsumerTask: Task<Void, Never>?
    private var eventConsumerTask: Task<Void, Never>?
    private var strategyTask: Task<Void, Never>?
    private var tpUpdateTask: Task<Void, Never>?
    private var audioHealthTask: Task<Void, Never>?

    private var currentSessionRecord: MeetingSessionRecord?
    private let modelContext: ModelContext
    private var pendingConfig: AudioCaptureConfiguration?

    init(claudeAPIKey: String, claudeModel: String = "claude-sonnet-4-20250514",
         notebookLMConfig: NotebookLMConfig = .default, meetingContext: MeetingContext) {
        self.pipeline = TranscriptPipeline()
        self.orchestrator = ResponseOrchestrator(claudeAPIKey: claudeAPIKey, claudeModel: claudeModel,
            notebookLMConfig: notebookLMConfig, meetingContext: meetingContext)
        self.modelContext = ModelContext(MeetingDataStore.container)
    }

    func loadKnowledgeBase(_ items: [QAItem]) async {
        await orchestrator.loadKnowledgeBase(items); stats.qaItemsLoaded = items.count
    }
    func loadTalkingPoints(_ points: [TalkingPoint], meetingDurationMinutes: Int = 60) async {
        await tpTracker.loadTalkingPoints(points, meetingDurationMinutes: meetingDurationMinutes)
        await syncTPState()
    }
    func updateContext(_ context: MeetingContext) async { await orchestrator.updateContext(context) }

    // MARK: - ★ Step 1: 掃描 App（用戶按下開始會議後的第一步）
    
    /// 掃描支援的 App，決定是否顯示選擇器
    /// - 0 個 App → 顯示錯誤
    /// - 1 個 App → 自動啟動
    /// - 2+ 個 App → 顯示 App Picker
    func scanAndPrepare(config: AudioCaptureConfiguration = .default) async {
        isScanning = true
        pendingConfig = config
        
        let apps = await AppScanner.scanActiveApps()
        isScanning = false
        
        if apps.isEmpty {
            captureState = .error(.noAudioSourceFound)
        } else if apps.count == 1 {
            // 單一 App → 直接啟動
            await startMeeting(config: config.withTarget(apps[0].app))
        } else {
            // 多個 App → 顯示選擇器
            detectedApps = apps
            showAppPicker = true
        }
    }
    
    // MARK: - ★ Step 2: 用戶選擇 App 後啟動
    
    func startMeetingWithApp(_ app: MeetingApp) async {
        showAppPicker = false
        let config = pendingConfig ?? .default
        await startMeeting(config: config.withTarget(app))
    }

    // MARK: - Start Meeting
    
    func startMeeting(config: AudioCaptureConfiguration = .default) async {
        do {
            try await pipeline.start(config: config)
            self.captureState = await pipeline.captureState
            self.activeEngineType = await pipeline.activeEngineType
            self.hasDualStream = await pipeline.hasDualStream
        } catch { self.captureState = .error(.engineStartFailed("引擎啟動失敗")); return }

        // ★ 立即同步音訊健康狀態（含啟動訊息 + App 名稱）
        self.audioHealth = await pipeline.audioHealth
        self.detectedAppName = audioHealth.detectedAppName ?? ""

        await orchestrator.checkNotebookLMAvailability()
        self.isNotebookLMAvailable = await orchestrator.isNotebookLMAvailable
        await tpTracker.markMeetingStarted()

        let record = MeetingSessionRecord(
            startTime: Date(), engineType: activeEngineType?.rawValue ?? "unknown",
            hasDualStream: hasDualStream
        )
        modelContext.insert(record)
        currentSessionRecord = record
        try? modelContext.save()

        startPipelineConsumer(); startEventConsumer(); startPeriodicStrategy()
        startTPUpdateLoop(); startAudioHealthLoop()
        stats.sessionStartTime = Date()
    }

    func stopMeeting() async {
        pipelineConsumerTask?.cancel(); eventConsumerTask?.cancel()
        strategyTask?.cancel(); tpUpdateTask?.cancel(); audioHealthTask?.cancel()
        await pipeline.stop(); await orchestrator.markSessionEnd()
        captureState = .idle; activeEngineType = nil
        isClaudeStreaming = false; isNotebookLMQuerying = false; hasDualStream = false
        detectedAppName = ""
        stats = await orchestrator.stats; stats.sessionEndTime = Date()
        self.tpStats = await tpTracker.getStats()
        self.audioHealth = AudioHealthStatus(
            remoteActive: false, localActive: false,
            remoteLastReceived: nil, localLastReceived: nil,
            remoteSegmentCount: 0, localSegmentCount: 0,
            startupMessage: nil, detectedAppName: nil
        )

        if let record = currentSessionRecord {
            record.updateFromStats(stats, tpStats: tpStats)
            try? modelContext.save()
        }
        currentSessionRecord = nil
    }

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
                self.transcriptEntries = await self.pipeline.transcriptEntries

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
                    if let record = self.currentSessionRecord {
                        let cr = CardRecord(timestamp: card.timestamp, cardType: card.type.rawValue,
                            title: card.title, content: card.content,
                            confidence: Double(card.confidence),
                            latencyMs: card.latencyMs, pipelineLayer: card.type.rawValue)
                        cr.session = record; record.cards.append(cr)
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

    // ★ Audio Health 輪詢（每 3 秒）
    private func startAudioHealthLoop() {
        audioHealthTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let self else { break }
                self.audioHealth = await self.pipeline.audioHealth
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
        return "\(d) | Cards: \(totalCards) (🟢\(localMatches) 📚\(notebookLMQueries) 🟣\(claudeQueries) 🟠\(strategyAnalyses)) | Lat: \(String(format: "%.0f", averageClaudeLatencyMs))ms | $\(String(format: "%.2f", estimatedClaudeCost))"
    }
}
