// TalkingPointsTrackerTests.swift
// MeetingCopilot v4.3 XCTest

import XCTest
@testable import MeetingCopilot

final class TalkingPointsTrackerTests: XCTestCase {
    var tracker: TalkingPointsTracker!

    override func setUp() async throws {
        tracker = TalkingPointsTracker()
        await tracker.loadTalkingPoints([
            TalkingPoint(content: "AVEVA 差異", priority: .must, keywords: ["AVEVA", "差異"], supportingData: "t"),
            TalkingPoint(content: "ROI", priority: .must, keywords: ["ROI", "投資報酬"], supportingData: "t"),
            TalkingPoint(content: "資安", priority: .should, keywords: ["資安", "ISO"], supportingData: "t"),
            TalkingPoint(content: "TSMC", priority: .nice, keywords: ["TSMC", "案例"], supportingData: "t")
        ], meetingDurationMinutes: 60)
        await tracker.markMeetingStarted()
    }

    func testInitialStats() async {
        let s = await tracker.getStats()
        XCTAssertEqual(s.total, 4); XCTAssertEqual(s.completed, 0); XCTAssertEqual(s.mustTotal, 2)
    }
    func testDetectsTP() async {
        _ = await tracker.analyzeTranscript("AVEVA的差異化定位是這樣")
        let pts = await tracker.getAllTalkingPoints()
        XCTAssertEqual(pts.first { $0.content.contains("AVEVA") }?.status, .completed)
    }
    func testUnrelated() async {
        _ = await tracker.analyzeTranscript("今天天氣很好")
        XCTAssertEqual((await tracker.getStats()).completed, 0)
    }
    func testManualComplete() async {
        let p = await tracker.getAllTalkingPoints()
        await tracker.markCompleted(p[0].id)
        XCTAssertEqual((await tracker.getAllTalkingPoints()).first { $0.id == p[0].id }?.status, .completed)
    }
    func testManualSkip() async {
        let p = await tracker.getAllTalkingPoints()
        await tracker.markSkipped(p.last!.id)
        XCTAssertEqual((await tracker.getAllTalkingPoints()).first { $0.id == p.last!.id }?.status, .skipped)
    }
    func testCompletionRate() async {
        let p = await tracker.getAllTalkingPoints()
        await tracker.markCompleted(p[0].id); await tracker.markCompleted(p[1].id)
        XCTAssertEqual((await tracker.getStats()).mustCompletionRate, 1.0, accuracy: 0.01)
    }
}
