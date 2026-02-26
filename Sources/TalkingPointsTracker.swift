// ═══════════════════════════════════════════════════════════════════════════
// TalkingPointsTracker.swift
// MeetingCopilot v4.1 — Talking Points 即時追蹤器（P0）
// ═══════════════════════════════════════════════════════════════════════════
//
//  三大場景共用核心功能：
//
//  場景 1 多人會議：追蹤哪些 TP 講了、哪些沒講，提醒用戶帶入
//  場景 2 高壓會議：確保所有 MUST TP 在會議結束前被提到
//  場景 3 面試/Review：追蹤是否有效回應面試官的問題
//
//  運作方式：
//  - 持續比對逐字稿與預載 Talking Points
//  - 偵測到 TP 被講到 → 更新為 completed
//  - 會議過半但 MUST TP 未講 → 產生提醒卡片
//  - 目前話題和某 TP 相關 → 產生時機提示
//  - 所有狀態即時反映在 UI 的 TP 面板
//
//  Platform: macOS 14.0+
// ═══════════════════════════════════════════════════════════════════════════

import Foundation

// MARK: - Talking Point 定義

struct TalkingPoint: Identifiable, Codable, Sendable {
    let id: UUID
    let content: String                  // TP 內容
    let priority: Priority
    let keywords: [String]               // 觸發關鍵字
    let supportingData: String?          // 支撐數據（提詞板顯示）
    var status: Status
    var completedAt: Date?
    var matchedTranscript: String?       // 命中的逐字稿片段

    enum Priority: String, Codable, Sendable, Comparable {
        case must = "MUST"               // 必須講到
        case should = "SHOULD"           // 應該講到
        case nice = "NICE"               // 能講到最好

        static func < (lhs: Priority, rhs: Priority) -> Bool {
            let order: [Priority] = [.must, .should, .nice]
            return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
        }
    }

    enum Status: String, Codable, Sendable {
        case pending                     // 尚未提到
        case inProgress = "in_progress"  // 正在討論中
        case completed                   // 已完成
        case skipped                     // 手動跳過
    }

    init(
        content: String,
        priority: Priority,
        keywords: [String],
        supportingData: String? = nil
    ) {
        self.id = UUID()
        self.content = content
        self.priority = priority
        self.keywords = keywords
        self.supportingData = supportingData
        self.status = .pending
        self.completedAt = nil
        self.matchedTranscript = nil
    }
}

// MARK: - TP 追蹤統計

struct TPStats: Sendable {
    let total: Int
    let completed: Int
    let mustTotal: Int
    let mustCompleted: Int
    let shouldTotal: Int
    let shouldCompleted: Int

    var completionRate: Float {
        total > 0 ? Float(completed) / Float(total) : 0
    }
    var mustCompletionRate: Float {
        mustTotal > 0 ? Float(mustCompleted) / Float(mustTotal) : 1.0
    }
    var summary: String {
        "TP: \(completed)/\(total) "
        + "(\(String(format: "%.0f", completionRate * 100))%) | "
        + "MUST: \(mustCompleted)/\(mustTotal)"
    }
}

// MARK: - TP 提醒

struct TPReminder: Sendable, Identifiable {
    let id = UUID()
    let type: ReminderType
    let talkingPoint: TalkingPoint
    let message: String
    let urgency: Urgency
    let timestamp: Date

    enum ReminderType: String, Sendable {
        case mustNotCovered              // MUST 還沒講
        case timeRunningOut              // 時間快到了
        case topicRelevant               // 話題相關，好時機帶入
        case driftWarning                // 議題偏離
    }

    enum Urgency: String, Sendable {
        case low, medium, high, critical
    }
}

// MARK: - Talking Points Tracker

actor TalkingPointsTracker {

    private var talkingPoints: [TalkingPoint] = []

    // 設定
    private let matchThreshold: Int = 2          // 至少 2 關鍵字命中
    private var meetingDurationMinutes: Int = 60
    private var meetingStartTime: Date?

    // 提醒冷卻
    private var lastReminderTime: Date = .distantPast
    private let reminderCooldown: TimeInterval = 120.0   // 2 分鐘
    private var sentReminders: Set<UUID> = []

    // ─────────────────────────────────────────────────────────
    // MARK: 初始化
    // ─────────────────────────────────────────────────────────

    func loadTalkingPoints(
        _ points: [TalkingPoint],
        meetingDurationMinutes: Int = 60
    ) {
        self.talkingPoints = points.sorted { $0.priority < $1.priority }
        self.meetingDurationMinutes = meetingDurationMinutes
        let must  = points.filter { $0.priority == .must }.count
        let shld  = points.filter { $0.priority == .should }.count
        let nice  = points.filter { $0.priority == .nice }.count
        print("📋 TP Tracker: \(points.count) loaded "
            + "(MUST: \(must), SHOULD: \(shld), NICE: \(nice))")
    }

    func markMeetingStarted() {
        meetingStartTime = Date()
    }

    // ─────────────────────────────────────────────────────────
    // MARK: 核心：逐字稿比對
    // ─────────────────────────────────────────────────────────

    /// 分析最新逐字稿，更新 TP 狀態，回傳提醒
    func analyzeTranscript(_ transcript: String) -> [TPReminder] {
        let recentText = String(transcript.suffix(200)).lowercased()
        var reminders: [TPReminder] = []

        for i in 0..<talkingPoints.count {
            guard talkingPoints[i].status == .pending
                || talkingPoints[i].status == .inProgress else { continue }

            let matchedKeywords = talkingPoints[i].keywords.filter {
                recentText.localizedCaseInsensitiveContains($0.lowercased())
            }

            if matchedKeywords.count >= matchThreshold {
                // TP 被講到了
                talkingPoints[i].status = .completed
                talkingPoints[i].completedAt = Date()
                talkingPoints[i].matchedTranscript = String(recentText.suffix(80))
                print("✅ TP completed: \(talkingPoints[i].content) "
                    + "[\(matchedKeywords.joined(separator: ", "))]")

            } else if matchedKeywords.count >= 1
                        && talkingPoints[i].status == .pending {
                // 部分命中 → 正在討論
                talkingPoints[i].status = .inProgress

            } else if matchedKeywords.count >= 1
                        && !sentReminders.contains(talkingPoints[i].id) {
                // 話題相關 → 好時機帶入
                reminders.append(TPReminder(
                    type: .topicRelevant,
                    talkingPoint: talkingPoints[i],
                    message: "話題與「\(talkingPoints[i].content)」相關，適合帶入",
                    urgency: .medium,
                    timestamp: Date()
                ))
            }
        }

        // 時間壓力提醒
        reminders.append(contentsOf: checkTimeBasedReminders())
        return reminders
    }

    // ─────────────────────────────────────────────────────────
    // MARK: 時間壓力提醒
    // ─────────────────────────────────────────────────────────

    private func checkTimeBasedReminders() -> [TPReminder] {
        guard let startTime = meetingStartTime else { return [] }

        let now = Date()
        guard now.timeIntervalSince(lastReminderTime) >= reminderCooldown else {
            return []
        }

        let elapsedMinutes = now.timeIntervalSince(startTime) / 60.0
        let progressRatio = elapsedMinutes / Double(meetingDurationMinutes)

        var reminders: [TPReminder] = []

        // 會議過半但 MUST 未完成
        if progressRatio > 0.5 {
            let unfinishedMust = talkingPoints.filter {
                $0.priority == .must
                && $0.status != .completed
                && $0.status != .skipped
            }

            for tp in unfinishedMust {
                guard !sentReminders.contains(tp.id) else { continue }

                let urgency: TPReminder.Urgency = progressRatio > 0.75
                    ? .critical : .high

                reminders.append(TPReminder(
                    type: .mustNotCovered,
                    talkingPoint: tp,
                    message: urgency == .critical
                        ? "⚠️ 會議即將結束，MUST「\(tp.content)」還沒講到！"
                        : "會議已過半，記得提到「\(tp.content)」",
                    urgency: urgency,
                    timestamp: now
                ))
                sentReminders.insert(tp.id)
            }
        }

        if !reminders.isEmpty { lastReminderTime = now }
        return reminders
    }

    // ─────────────────────────────────────────────────────────
    // MARK: 查詢狀態
    // ─────────────────────────────────────────────────────────

    func getAllTalkingPoints() -> [TalkingPoint] { talkingPoints }

    func getStats() -> TPStats {
        let completed = talkingPoints.filter { $0.status == .completed }.count
        let must = talkingPoints.filter { $0.priority == .must }
        let should = talkingPoints.filter { $0.priority == .should }
        return TPStats(
            total: talkingPoints.count, completed: completed,
            mustTotal: must.count,
            mustCompleted: must.filter { $0.status == .completed }.count,
            shouldTotal: should.count,
            shouldCompleted: should.filter { $0.status == .completed }.count
        )
    }

    // ─────────────────────────────────────────────────────────
    // MARK: 手動操作
    // ─────────────────────────────────────────────────────────

    func markCompleted(_ id: UUID) {
        guard let i = talkingPoints.firstIndex(where: { $0.id == id }) else { return }
        talkingPoints[i].status = .completed
        talkingPoints[i].completedAt = Date()
    }

    func markSkipped(_ id: UUID) {
        guard let i = talkingPoints.firstIndex(where: { $0.id == id }) else { return }
        talkingPoints[i].status = .skipped
    }

    func reset() {
        for i in 0..<talkingPoints.count {
            talkingPoints[i].status = .pending
            talkingPoints[i].completedAt = nil
            talkingPoints[i].matchedTranscript = nil
        }
        sentReminders.removeAll()
        lastReminderTime = .distantPast
        meetingStartTime = nil
    }
}
