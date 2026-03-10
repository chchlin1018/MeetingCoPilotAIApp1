// MeetingSessionStore.swift
// MeetingCopilot v4.3 — SwiftData Persistence (P0)

import Foundation
import SwiftData

@Model
final class MeetingSessionRecord {
    var sessionId: UUID
    var startTime: Date
    var endTime: Date?
    var engineType: String
    var hasDualStream: Bool
    var meetingType: String
    var localMatches: Int
    var notebookLMQueries: Int
    var claudeQueries: Int
    var strategyAnalyses: Int
    var totalCards: Int
    var averageLatencyMs: Double
    var estimatedCost: Double
    var tpTotal: Int
    var tpCompleted: Int
    var tpMustTotal: Int
    var tpMustCompleted: Int
    @Relationship(deleteRule: .cascade) var transcripts: [TranscriptRecord]
    @Relationship(deleteRule: .cascade) var cards: [CardRecord]

    init(sessionId: UUID = UUID(), startTime: Date = Date(), engineType: String = "SystemAudio",
         hasDualStream: Bool = false, meetingType: String = "") {
        self.sessionId = sessionId; self.startTime = startTime
        self.engineType = engineType; self.hasDualStream = hasDualStream
        self.meetingType = meetingType
        self.localMatches = 0; self.notebookLMQueries = 0; self.claudeQueries = 0
        self.strategyAnalyses = 0; self.totalCards = 0; self.averageLatencyMs = 0
        self.estimatedCost = 0; self.tpTotal = 0; self.tpCompleted = 0
        self.tpMustTotal = 0; self.tpMustCompleted = 0
        self.transcripts = []; self.cards = []
    }

    func updateFromStats(_ stats: SessionStats, tpStats: TPStats) {
        self.endTime = stats.sessionEndTime ?? Date()
        self.localMatches = stats.localMatches
        self.notebookLMQueries = stats.notebookLMQueries
        self.claudeQueries = stats.claudeQueries
        self.strategyAnalyses = stats.strategyAnalyses
        self.totalCards = stats.totalCards
        self.averageLatencyMs = stats.averageClaudeLatencyMs
        self.estimatedCost = stats.estimatedClaudeCost
        self.tpTotal = tpStats.total; self.tpCompleted = tpStats.completed
        self.tpMustTotal = tpStats.mustTotal; self.tpMustCompleted = tpStats.mustCompleted
    }

    var durationMinutes: Int? {
        guard let end = endTime else { return nil }
        return Int(end.timeIntervalSince(startTime) / 60)
    }
}

@Model
final class TranscriptRecord {
    var timestamp: Date
    var text: String
    var speaker: String
    var isFinal: Bool
    var confidence: Float
    var session: MeetingSessionRecord?

    init(timestamp: Date = Date(), text: String, speaker: String, isFinal: Bool = false, confidence: Float = 0) {
        self.timestamp = timestamp; self.text = text; self.speaker = speaker
        self.isFinal = isFinal; self.confidence = confidence
    }
}

@Model
final class CardRecord {
    var timestamp: Date
    var cardType: String
    var title: String
    var content: String
    var confidence: Double
    var latencyMs: Double
    var pipelineLayer: String
    var session: MeetingSessionRecord?

    init(timestamp: Date = Date(), cardType: String, title: String, content: String,
         confidence: Double, latencyMs: Double, pipelineLayer: String) {
        self.timestamp = timestamp; self.cardType = cardType; self.title = title
        self.content = content; self.confidence = confidence
        self.latencyMs = latencyMs; self.pipelineLayer = pipelineLayer
    }
}

enum MeetingDataStore {
    static let schema = Schema([MeetingSessionRecord.self, TranscriptRecord.self, CardRecord.self])
    static var container: ModelContainer = {
        do { return try ModelContainer(for: schema) }
        catch { fatalError("SwiftData container failed: \(error)") }
    }()
}
