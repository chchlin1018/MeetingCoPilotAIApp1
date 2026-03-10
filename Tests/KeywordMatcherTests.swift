// KeywordMatcherTests.swift
// MeetingCopilot v4.3 XCTest

import XCTest
@testable import MeetingCopilot

final class KeywordMatcherTests: XCTestCase {
    var matcher: KeywordMatcher!

    override func setUp() async throws {
        matcher = KeywordMatcher()
        await matcher.loadKnowledgeBase([
            QAItem(question: "IDTF vs AVEVA?", keywords: ["AVEVA", "差異", "比較"],
                   shortAnswer: "IDTF open-source, AVEVA $2.1M/yr", fullAnswer: "Full"),
            QAItem(question: "ROI?", keywords: ["ROI", "投資報酬", "成本"],
                   shortAnswer: "PoC $120K, payback 4 months", fullAnswer: "Full"),
            QAItem(question: "Security?", keywords: ["資安", "ISO", "合規"],
                   shortAnswer: "ISO 27001 in progress", fullAnswer: "Full")
        ])
    }

    func testMatchAVEVA() async {
        let r = await matcher.match(transcript: "請問IDTF和AVEVA的差異是什麼")
        XCTAssertNotNil(r); XCTAssertTrue(r!.item.question.contains("AVEVA"))
    }
    func testMatchROI() async {
        let r = await matcher.match(transcript: "ROI怎麼算")
        XCTAssertNotNil(r); XCTAssertTrue(r!.item.shortAnswer.contains("$120K"))
    }
    func testNoMatch() async {
        XCTAssertNil(await matcher.match(transcript: "今天天氣很好"))
    }
    func testEmpty() async {
        XCTAssertNil(await matcher.match(transcript: ""))
    }
    func testChineseKeyword() async {
        let r = await matcher.match(transcript: "資安合規方面你們有什麼方案")
        XCTAssertNotNil(r); XCTAssertTrue(r!.item.shortAnswer.contains("ISO"))
    }
    func testLatency() async {
        let r = await matcher.match(transcript: "AVEVA的差異")
        XCTAssertNotNil(r); XCTAssertLessThan(r!.latencyMs, 200)
    }
}
