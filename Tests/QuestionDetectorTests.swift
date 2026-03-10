// QuestionDetectorTests.swift
// MeetingCopilot v4.3 XCTest

import XCTest
@testable import MeetingCopilot

final class QuestionDetectorTests: XCTestCase {
    let d = QuestionDetector()

    // Chinese
    func testChinese_qmark() { XCTAssertTrue(d.isQuestion("時程是什麼？")) }
    func testChinese_shenme() { XCTAssertTrue(d.isQuestion("什麼優勢")) }
    func testChinese_ruhe() { XCTAssertTrue(d.isQuestion("如何確保資安")) }
    func testChinese_ma() { XCTAssertTrue(d.isQuestion("可以嗎")) }
    func testChinese_duoshao() { XCTAssertTrue(d.isQuestion("成本多少")) }
    // English
    func testEnglish_what() { XCTAssertTrue(d.isQuestion("What is timeline?")) }
    func testEnglish_how() { XCTAssertTrue(d.isQuestion("How does it compare?")) }
    func testEnglish_canYou() { XCTAssertTrue(d.isQuestion("Can you explain ROI?")) }
    // Non-questions
    func testStatement_cn() { XCTAssertFalse(d.isQuestion("我們的產品很好")) }
    func testStatement_en() { XCTAssertFalse(d.isQuestion("The system is running")) }
    func testGreeting() { XCTAssertFalse(d.isQuestion("Hello everyone")) }
    func testEmpty() { XCTAssertFalse(d.isQuestion("")) }
    // Edge
    func testMixed() { XCTAssertTrue(d.isQuestion("這個 solution 怎麼算")) }
    func testComparison() { XCTAssertTrue(d.isQuestion("IDTF跟AVEVA的比較")) }
}
