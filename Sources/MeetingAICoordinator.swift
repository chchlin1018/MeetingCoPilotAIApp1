// ═══════════════════════════════════════════════════════════════════════════
// MeetingAICoordinator.swift
// MeetingCopilot v4.3.1 — Fixed: start_time bug + speaking time fallback
// ═══════════════════════════════════════════════════════════════════════════

import Foundation
import SwiftUI
import SwiftData

@Observable
@MainActor
final class MeetingAICoordinator {

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
    private(set) var audioHealth = AudioHealthStatus(
        remoteActive: false, localActive: false, remoteLastReceived: nil, localLastReceived: nil,
        remoteSegmentCount: 0, localSegmentCount: 0, startupMessage: nil, detectedAppName: nil
    )
    var detectedApps: [DetectedAppInfo] = []
    var showAppPicker: Bool = false
    var isScanning: Bool = false
    private(set) var detectedAppName: String = ""
    private var meetingTitle: String = "Meeting"
    private var meetingLanguage: String = "zh-TW"
    private var claudeAPIConnected: Bool = false
    // ★ Bug fix: 保存 sessionStartTime 避免被覆寫
    private var _sessionStartTime: Date?

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
        self.claudeAPIConnected = (claudeAPIKey != "NOT_CONFIGURED" && !claudeAPIKey.isEmpty)
    }

    func loadKnowledgeBase(_ items: [QAItem]) async { await orchestrator.loadKnowledgeBase(items); stats.qaItemsLoaded = items.count }
    func loadTalkingPoints(_ points: [TalkingPoint], meetingDurationMinutes: Int = 60) async {
        await tpTracker.loadTalkingPoints(points, meetingDurationMinutes: meetingDurationMinutes); await syncTPState()
    }
    func updateContext(_ context: MeetingContext) async { await orchestrator.updateContext(context) }
    func setMeetingInfo(title: String, language: String) { meetingTitle = title; meetingLanguage = language }

    func scanAndPrepare(config: AudioCaptureConfiguration = .default) async {
        isScanning = true; pendingConfig = config
        let apps = await AppScanner.scanActiveApps()
        isScanning = false
        if apps.isEmpty { captureState = .error(.noAudioSourceFound) }
        else if apps.count == 1 { await startMeeting(config: config.withTarget(apps[0].app)) }
        else { detectedApps = apps; showAppPicker = true }
    }
    func startMeetingWithApp(_ app: MeetingApp) async {
        showAppPicker = false; let config = pendingConfig ?? .default
        await startMeeting(config: config.withTarget(app))
    }

    func startMeeting(config: AudioCaptureConfiguration = .default) async {
        do {
            try await pipeline.start(config: config)
            self.captureState = await pipeline.captureState
            self.activeEngineType = await pipeline.activeEngineType
            self.hasDualStream = await pipeline.hasDualStream
        } catch { self.captureState = .error(.engineStartFailed("引擎啟動失敗")); return }
        self.audioHealth = await pipeline.audioHealth
        self.detectedAppName = audioHealth.detectedAppName ?? ""
        await orchestrator.checkNotebookLMAvailability()
        self.isNotebookLMAvailable = await orchestrator.isNotebookLMAvailable
        if stats.claudeQueries > 0 || stats.strategyAnalyses > 0 { claudeAPIConnected = true }
        await tpTracker.markMeetingStarted()
        let record = MeetingSessionRecord(startTime: Date(), engineType: activeEngineType?.rawValue ?? "unknown", hasDualStream: hasDualStream)
        modelContext.insert(record); currentSessionRecord = record; try? modelContext.save()
        startPipelineConsumer(); startEventConsumer(); startPeriodicStrategy()
        startTPUpdateLoop(); startAudioHealthLoop()
        // ★ Bug fix: 同時保存到專屬變數，避免被 orchestrator.stats 覆寫
        let now = Date()
        stats.sessionStartTime = now
        _sessionStartTime = now
    }

    func stopMeeting() async {
        pipelineConsumerTask?.cancel(); eventConsumerTask?.cancel()
        strategyTask?.cancel(); tpUpdateTask?.cancel(); audioHealthTask?.cancel()

        // ★ 收集診斷資訊（在 stop 之前）
        let diag = await pipeline.getEngineDiagnostics()
        let finalAudioHealth = await pipeline.audioHealth
        let finalEntries = await pipeline.transcriptEntries

        await pipeline.stop(); await orchestrator.markSessionEnd()
        captureState = .idle; activeEngineType = nil
        isClaudeStreaming = false; isNotebookLMQuerying = false; hasDualStream = false
        
        // ★ Bug fix: 先從 orchestrator 取 stats，然後還原 sessionStartTime
        stats = await orchestrator.stats
        stats.sessionStartTime = _sessionStartTime  // ★ 還原被覆寫的 startTime
        stats.sessionEndTime = Date()
        
        self.tpStats = await tpTracker.getStats()
        if stats.claudeQueries > 0 || stats.strategyAnalyses > 0 { claudeAPIConnected = true }

        self.audioHealth = AudioHealthStatus(
            remoteActive: false, localActive: false, remoteLastReceived: nil, localLastReceived: nil,
            remoteSegmentCount: 0, localSegmentCount: 0, startupMessage: nil, detectedAppName: nil
        )
        if let record = currentSessionRecord { record.updateFromStats(stats, tpStats: tpStats); try? modelContext.save() }
        currentSessionRecord = nil

        // ★ 計算發言時間（優先用 entries，fallback 用 engine segments）
        let speakingTime = computeSpeakingTime(entries: finalEntries, remoteDiag: diag.remote, localDiag: diag.local)
        
        let connections = ConnectionStatus(
            claudeAPI: claudeAPIConnected ? (stats.claudeQueries > 0 ? .connected : .notUsed) :
                       (KeychainManager.hasClaudeAPIKey ? .failed : .notConfigured),
            notionAPI: KeychainManager.hasNotionAPIKey ? .connected : .notConfigured,
            notebookLM: isNotebookLMAvailable ? .connected :
                        (stats.notebookLMQueries > 0 ? .connected : .notUsed)
        )

        // ★ 儲存會議後診斷 Log
        let log = MeetingSessionLog(
            meetingTitle: meetingTitle,
            startTime: _sessionStartTime,  // ★ 用保存的時間
            endTime: Date(),
            language: meetingLanguage,
            hasDualStream: finalAudioHealth.remoteActive && finalAudioHealth.localActive,
            remoteDiag: diag.remote,
            localDiag: diag.local,
            stats: stats,
            tpStats: tpStats,
            screenRecordingPermission: diag.screenRecordingOK,
            micDevice: diag.micDevice,
            bluetoothDetected: diag.bluetoothDetected,
            errorLog: diag.errors,
            audioSourceApp: detectedAppName,
            connections: connections,
            speakingTime: speakingTime,
            totalTranscriptEntries: finalEntries.count
        )
        PostMeetingLogger.saveLog(log)
        detectedAppName = ""
        _sessionStartTime = nil
    }
    
    // ★ 計算發言時間（用字數估算 + fallback 用 engine segment 數量）
    private func computeSpeakingTime(entries: [TranscriptEntry], remoteDiag: EngineDiagnosticInfo, localDiag: EngineDiagnosticInfo) -> SpeakingTimeInfo {
        let remoteEntries = entries.filter { $0.speaker == .remote && $0.isFinal }
        let localEntries = entries.filter { $0.speaker == .local && $0.isFinal }
        var remoteChars = remoteEntries.reduce(0) { $0 + $1.text.count }
        var localChars = localEntries.reduce(0) { $0 + $1.text.count }
        var remoteFinal = remoteEntries.count
        var localFinal = localEntries.count
        
        // ★ Fallback: 如果 entries 沒有 isFinal 但 engine 有 segments，用 engine 的 segment 數來估算
        // 平均每個 segment 約 20 字（中文）或 30 字（英文）
        if remoteFinal == 0 && remoteDiag.segmentCount > 0 {
            let avgCharsPerSegment = meetingLanguage.hasPrefix("zh") ? 20 : 30
            remoteChars = remoteDiag.segmentCount * avgCharsPerSegment
            remoteFinal = remoteDiag.segmentCount
        }
        if localFinal == 0 && localDiag.segmentCount > 0 {
            let avgCharsPerSegment = meetingLanguage.hasPrefix("zh") ? 20 : 30
            localChars = localDiag.segmentCount * avgCharsPerSegment
            localFinal = localDiag.segmentCount
        }
        
        let charsPerSecond: Double = meetingLanguage.hasPrefix("zh") ? 3.0 : 2.5
        let remoteMinutes = Double(remoteChars) / charsPerSecond / 60.0
        let localMinutes = Double(localChars) / charsPerSecond / 60.0
        return SpeakingTimeInfo(
            remoteFinalSegments: remoteFinal,
            localFinalSegments: localFinal,
            remoteCharCount: remoteChars,
            localCharCount: localChars,
            remoteEstimatedMinutes: remoteMinutes,
            localEstimatedMinutes: localMinutes
        )
    }

    func manualQuery(_ question: String) async {
        let t = await pipeline.fullTranscript
        await orchestrator.manualQuery(question, fullTranscript: t)
        self.cards = await orchestrator.cards; self.stats = await orchestrator.stats
    }
    func markTPCompleted(_ id: UUID) async { await tpTracker.markCompleted(id); await syncTPState() }
    func markTPSkipped(_ id: UUID) async { await tpTracker.markSkipped(id); await syncTPState() }

    private func startPipelineConsumer() {
        pipelineConsumerTask = Task { [weak self] in
            guard let self else { return }
            let updates = await self.pipeline.updates!
            for await update in updates {
                guard !Task.isCancelled else { break }
                self.fullTranscript = update.fullText; self.recentTranscript = update.recentText
                self.transcriptEntries = await self.pipeline.transcriptEntries
                if let record = self.currentSessionRecord, update.segment.text.count > 10 {
                    let tr = TranscriptRecord(timestamp: update.segment.timestamp, text: update.segment.text, speaker: update.speaker.rawValue, isFinal: update.segment.isFinal, confidence: update.segment.confidence)
                    tr.session = record; record.transcripts.append(tr)
                }
                switch update.speaker {
                case .remote:
                    let tp = await self.tpTracker.getStats()
                    let um = await self.tpTracker.getAllTalkingPoints().filter { $0.status == .pending && $0.priority == .must }.map { $0.content }
                    await self.orchestrator.processUpdate(update, tpStats: tp, unfinishedMust: um)
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
                    self.cards = await self.orchestrator.cards; self.stats = await self.orchestrator.stats
                    self.claudeAPIConnected = true
                    if let record = self.currentSessionRecord {
                        let cr = CardRecord(timestamp: card.timestamp, cardType: card.type.rawValue, title: card.title, content: card.content, confidence: Double(card.confidence), latencyMs: card.latencyMs, pipelineLayer: card.type.rawValue)
                        cr.session = record; record.cards.append(cr)
                    }
                case .claudeStreamingStarted: self.isClaudeStreaming = true; self.claudeAPIConnected = true
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
                let t = await self.pipeline.fullTranscript; let tp = await self.tpTracker.getStats()
                let um = await self.tpTracker.getAllTalkingPoints().filter { $0.status == .pending && $0.priority == .must }.map { $0.content }
                await self.orchestrator.runStrategyAnalysis(recentTranscript: t, tpStats: tp, unfinishedMust: um)
                try? await Task.sleep(nanoseconds: 180_000_000_000)
            }
        }
    }
    private func startTPUpdateLoop() {
        tpUpdateTask = Task { [weak self] in
            while !Task.isCancelled { try? await Task.sleep(nanoseconds: 5_000_000_000); guard let self else { break }; await self.syncTPState() }
        }
    }
    private func startAudioHealthLoop() {
        audioHealthTask = Task { [weak self] in
            while !Task.isCancelled { try? await Task.sleep(nanoseconds: 3_000_000_000); guard let self else { break }; self.audioHealth = await self.pipeline.audioHealth }
        }
    }
    private func syncTPState() async { self.talkingPoints = await tpTracker.getAllTalkingPoints(); self.tpStats = await tpTracker.getStats() }
}

struct SessionStats {
    var sessionStartTime: Date?; var sessionEndTime: Date?
    var qaItemsLoaded: Int = 0; var localMatches: Int = 0; var notebookLMQueries: Int = 0
    var claudeQueries: Int = 0; var strategyAnalyses: Int = 0; var totalCards: Int = 0
    var totalClaudeLatencyMs: Double = 0
    var sessionDuration: TimeInterval? { guard let s = sessionStartTime else { return nil }; return (sessionEndTime ?? Date()).timeIntervalSince(s) }
    var averageClaudeLatencyMs: Double { claudeQueries > 0 ? totalClaudeLatencyMs / Double(claudeQueries) : 0 }
    var estimatedClaudeCost: Double { Double(claudeQueries + strategyAnalyses) * 0.022 }
    var summary: String {
        let d = sessionDuration.map { "\(Int($0 / 60))m" } ?? "N/A"
        return "\(d) | Cards: \(totalCards) (🟢\(localMatches) 📚\(notebookLMQueries) 🟣\(claudeQueries) 🟠\(strategyAnalyses)) | Lat: \(String(format: "%.0f", averageClaudeLatencyMs))ms | $\(String(format: "%.2f", estimatedClaudeCost))"
    }
}
