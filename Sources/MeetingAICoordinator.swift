// MeetingAICoordinator.swift
// MeetingCopilot v4.0 — Dual-Engine Real-time Pipeline Orchestrator
//
// Central coordinator that:
// 1. Selects audio engine (SystemAudio primary -> Microphone fallback)
// 2. Consumes transcriptStream, dual-path routing:
//    Path 1: Local Q&A match -> Blue card (< 200ms)
//    Path 2: Unmatched + question detected -> Claude Streaming -> Purple card (1.5-3s)
// 3. Periodic background strategy analysis -> Orange card (every 3 min)
// 4. Pushes all cards and state to SwiftUI via @Observable

import Foundation
import SwiftUI

@Observable
@MainActor
final class MeetingAICoordinator {

    // MARK: - UI State (SwiftUI bindings)

    private(set) var cards: [AICard] = []
    private(set) var fullTranscript: String = ""
    private(set) var recentTranscript: String = ""
    private(set) var captureState: AudioCaptureState = .idle
    private(set) var activeEngineType: AudioCaptureEngineType?
    private(set) var detectedMeetingApp: String?
    private(set) var stats = SessionStats()
    private(set) var isClaudeStreaming: Bool = false

    // MARK: - Internal Components

    private var audioEngine: (any AudioCaptureEngine)?
    private let keywordMatcher = KeywordMatcher()
    private let claudeService: ClaudeService
    private var meetingContext: MeetingContext
    private var transcriptConsumerTask: Task<Void, Never>?
    private var strategyAnalysisTask: Task<Void, Never>?
    private let questionDetector = QuestionDetector()
    private var lastClaudeQueryTime: Date = .distantPast
    private let claudeMinInterval: TimeInterval = 5.0
    private let strategyInterval: TimeInterval = 180.0

    // MARK: - Init

    init(claudeAPIKey: String, claudeModel: String = "claude-sonnet-4-20250514", meetingContext: MeetingContext) {
        self.claudeService = ClaudeService(apiKey: claudeAPIKey, model: claudeModel)
        self.meetingContext = meetingContext
    }

    // MARK: - Load Knowledge Base

    func loadKnowledgeBase(_ items: [QAItem]) async {
        await keywordMatcher.loadKnowledgeBase(items)
        stats.qaItemsLoaded = items.count
    }

    func updateContext(_ context: MeetingContext) {
        self.meetingContext = context
    }

    // MARK: - Start Meeting

    func startMeeting(config: AudioCaptureConfiguration = .default) async {
        // Try primary engine (ScreenCaptureKit)
        let systemEngine = SystemAudioCaptureEngine(configuration: config)
        do {
            try await systemEngine.start()
            self.audioEngine = systemEngine
            self.activeEngineType = .systemAudio
            self.captureState = .capturing
        } catch {
            // Fallback to microphone
            let micEngine = MicrophoneCaptureEngine(configuration: config)
            do {
                try await micEngine.start()
                self.audioEngine = micEngine
                self.activeEngineType = .microphone
                self.captureState = .capturing
            } catch {
                self.captureState = .error(.engineStartFailed("All engines failed"))
                return
            }
        }

        startTranscriptConsumer()
        startPeriodicStrategyAnalysis()
        stats.sessionStartTime = Date()
    }

    // MARK: - Stop Meeting

    func stopMeeting() async {
        transcriptConsumerTask?.cancel()
        strategyAnalysisTask?.cancel()
        transcriptConsumerTask = nil
        strategyAnalysisTask = nil
        await audioEngine?.stop()
        audioEngine = nil
        captureState = .idle
        activeEngineType = nil
        isClaudeStreaming = false
        stats.sessionEndTime = Date()
        print("Meeting ended. \(stats.summary)")
    }

    // MARK: - Transcript Consumer (Core Pipeline)

    private func startTranscriptConsumer() {
        guard let engine = audioEngine else { return }
        transcriptConsumerTask = Task { [weak self] in
            for await segment in engine.transcriptStream {
                guard let self = self, !Task.isCancelled else { break }
                self.fullTranscript = segment.text
                self.recentTranscript = segment.recentText
                guard segment.text.count > 5 else { continue }
                await self.processTranscriptSegment(segment)
            }
        }
    }

    // MARK: - Dual-Path Routing (Core Logic)

    private func processTranscriptSegment(_ segment: TranscriptSegment) async {

        // Path 1: Local Q&A match (< 200ms)
        if let matchResult = await keywordMatcher.match(transcript: segment.text) {
            let card = AICard(
                type: .qaMatch,
                title: "Q&A: \(matchResult.item.question)",
                content: matchResult.item.shortAnswer,
                confidence: matchResult.confidence,
                latencyMs: matchResult.latencyMs,
                timestamp: Date()
            )
            insertCard(card)
            stats.localMatches += 1
            stats.totalCards += 1
            return
        }

        // Path 2: Question detected but no local match -> Claude API
        let recentText = String(segment.text.suffix(60))
        guard questionDetector.isQuestion(recentText) else { return }

        let now = Date()
        guard now.timeIntervalSince(lastClaudeQueryTime) >= claudeMinInterval else { return }
        lastClaudeQueryTime = now

        isClaudeStreaming = true
        let startTime = CFAbsoluteTimeGetCurrent()
        var accumulatedText = ""

        let currentContext = MeetingContext(
            goals: meetingContext.goals,
            preAnalysisCache: meetingContext.preAnalysisCache,
            relevantQA: meetingContext.relevantQA,
            recentTranscript: String(fullTranscript.suffix(500)),
            attendeeInfo: meetingContext.attendeeInfo,
            meetingType: meetingContext.meetingType
        )

        let stream = await claudeService.streamQuery(question: recentText, context: currentContext)
        for await chunk in stream {
            accumulatedText += chunk
        }

        let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        isClaudeStreaming = false
        guard !accumulatedText.isEmpty else { return }

        let card = AICard(
            type: .aiGenerated,
            title: "AI Suggestion",
            content: accumulatedText,
            confidence: 0.85,
            latencyMs: latency,
            timestamp: Date()
        )
        insertCard(card)
        stats.claudeQueries += 1
        stats.totalCards += 1
        stats.totalClaudeLatencyMs += latency
    }

    // MARK: - Periodic Strategy Analysis (every 3 min)

    private func startPeriodicStrategyAnalysis() {
        strategyAnalysisTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(120 * 1_000_000_000))
            while !Task.isCancelled {
                guard let self = self else { break }
                await self.runStrategyAnalysis()
                try? await Task.sleep(nanoseconds: UInt64(self.strategyInterval * 1_000_000_000))
            }
        }
    }

    private func runStrategyAnalysis() async {
        let recentChunk = String(fullTranscript.suffix(1000))
        guard recentChunk.count > 100 else { return }

        let prompt = """
        Analyze the last 3 minutes of meeting transcript:
        1. Is the meeting drifting from our goals?
        2. Any hidden agenda or avoided topics from the other side?
        3. What should I proactively raise in the next 5 minutes?
        Keep under 80 chars. Give direct strategy advice.
        Transcript: \(recentChunk)
        """

        let startTime = CFAbsoluteTimeGetCurrent()
        var strategyText = ""
        let stream = await claudeService.streamQuery(question: prompt, context: meetingContext)
        for await chunk in stream { strategyText += chunk }
        let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        guard !strategyText.isEmpty else { return }

        insertCard(AICard(
            type: .strategy,
            title: "Strategy Analysis",
            content: strategyText,
            confidence: 0.80,
            latencyMs: latency,
            timestamp: Date()
        ))
        stats.strategyAnalyses += 1
        stats.totalCards += 1
    }

    // MARK: - Card Management

    private func insertCard(_ card: AICard) {
        cards.insert(card, at: 0)
        if cards.count > 50 { cards = Array(cards.prefix(50)) }
    }

    func manualQuery(_ question: String) async {
        isClaudeStreaming = true
        let startTime = CFAbsoluteTimeGetCurrent()
        var text = ""
        let stream = await claudeService.streamQuery(question: question, context: meetingContext)
        for await chunk in stream { text += chunk }
        let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        isClaudeStreaming = false
        guard !text.isEmpty else { return }
        insertCard(AICard(
            type: .aiGenerated,
            title: "AI: \(String(question.prefix(20)))...",
            content: text,
            confidence: 0.9,
            latencyMs: latency,
            timestamp: Date()
        ))
        stats.claudeQueries += 1
        stats.totalCards += 1
    }
}

// MARK: - Question Detector

struct QuestionDetector: Sendable {
    private let questionPatterns: [String] = [
        "嗎", "什麼", "怎麼", "為什麼", "如何", "哪裡", "哪些", "哪個",
        "幾", "多少", "能不能", "可不可以", "是否", "有沒有", "呢", "吧",
        "請問", "想問", "請教", "好奇", "比較", "差異", "不同", "優勢", "劣勢",
        "what", "how", "why", "when", "where", "which", "who",
        "can you", "could you", "would you",
        "tell me", "explain", "describe",
        "difference", "compare", "advantage", "？", "?"
    ]

    func isQuestion(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return questionPatterns.filter { lowered.contains($0) }.count >= 1
    }
}

// MARK: - Session Stats

struct SessionStats {
    var sessionStartTime: Date?
    var sessionEndTime: Date?
    var qaItemsLoaded: Int = 0
    var localMatches: Int = 0
    var claudeQueries: Int = 0
    var strategyAnalyses: Int = 0
    var totalCards: Int = 0
    var totalClaudeLatencyMs: Double = 0

    var sessionDuration: TimeInterval? {
        guard let start = sessionStartTime else { return nil }
        return (sessionEndTime ?? Date()).timeIntervalSince(start)
    }

    var averageClaudeLatencyMs: Double {
        claudeQueries > 0 ? totalClaudeLatencyMs / Double(claudeQueries) : 0
    }

    var estimatedClaudeCost: Double {
        Double(claudeQueries + strategyAnalyses) * 0.022
    }

    var summary: String {
        let duration = sessionDuration.map { "\(Int($0 / 60)) min" } ?? "N/A"
        return "Duration: \(duration) | Cards: \(totalCards) (Local:\(localMatches) Claude:\(claudeQueries) Strategy:\(strategyAnalyses)) | Avg latency: \(String(format: "%.0f", averageClaudeLatencyMs))ms | AI cost: $\(String(format: "%.2f", estimatedClaudeCost))"
    }
}
