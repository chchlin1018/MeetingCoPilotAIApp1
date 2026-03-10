// ResponseOrchestratorTests.swift
// MeetingCopilot v4.3 XCTest

import XCTest
@testable import MeetingCopilot

final class ResponseOrchestratorTests: XCTestCase {
    func testSpeakerSourceValues() {
        XCTAssertEqual(SpeakerSource.remote.rawValue, "remote")
        XCTAssertEqual(SpeakerSource.local.rawValue, "local")
    }

    func testRemoteUpdateHasQuestion() {
        let seg = TranscriptSegment(text: "ROI怎麼算？", timestamp: Date(), isFinal: false,
            confidence: 0.9, locale: Locale(identifier: "zh-TW"), source: .systemAudio)
        let u = TranscriptUpdate(fullText: seg.text, recentText: seg.text,
            segment: seg, speaker: .remote, detectedQuestion: "ROI怎麼算？")
        XCTAssertEqual(u.speaker, .remote); XCTAssertNotNil(u.detectedQuestion)
    }

    func testLocalUpdateNoQuestion() {
        let seg = TranscriptSegment(text: "我們的ROI是380%", timestamp: Date(), isFinal: false,
            confidence: 0.9, locale: Locale(identifier: "zh-TW"), source: .microphone)
        let u = TranscriptUpdate(fullText: seg.text, recentText: seg.text,
            segment: seg, speaker: .local, detectedQuestion: nil)
        XCTAssertEqual(u.speaker, .local); XCTAssertNil(u.detectedQuestion)
    }

    func testSessionStatsSummary() {
        var s = SessionStats()
        s.sessionStartTime = Date().addingTimeInterval(-3600); s.sessionEndTime = Date()
        s.localMatches = 3; s.claudeQueries = 5; s.totalCards = 10; s.totalClaudeLatencyMs = 10000
        XCTAssertEqual(s.averageClaudeLatencyMs, 2000, accuracy: 1)
        XCTAssertGreaterThan(s.estimatedClaudeCost, 0)
        XCTAssertTrue(s.summary.contains("🔵"))
    }

    func testZeroDivision() {
        XCTAssertEqual(SessionStats().averageClaudeLatencyMs, 0)
    }

    func testDetectorWorksForBothButPipelineFilters() {
        let d = QuestionDetector()
        XCTAssertTrue(d.isQuestion("ROI怎麼算"))
        // In pipeline, local never reaches detector - tested at integration level
    }
}
