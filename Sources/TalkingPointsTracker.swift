// ═══════════════════════════════════════════════════════════════════════════
// TalkingPointsTracker.swift
// MeetingCopilot v4.3 — Talking Points 即時追蹤器 + 偵測標示
// ═══════════════════════════════════════════════════════════════════════════

import Foundation

// MARK: - Talking Point 定義

struct TalkingPoint: Identifiable, Codable, Sendable {
    let id: UUID
    let content: String
    let priority: Priority
    let keywords: [String]
    let supportingData: String?
    var status: Status
    var completedAt: Date?
    var matchedTranscript: String?       // 命中的逐字稿片段
    var detectedSpeech: String?          // ★ 偵測到我方說的內容（UI 顯示用）

    enum Priority: String, Codable, Sendable, Comparable {
        case must = "MUST"
        case should = "SHOULD"
        case nice = "NICE"
        static func < (lhs: Priority, rhs: Priority) -> Bool {
            let order: [Priority] = [.must, .should, .nice]
            return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
        }
    }

    enum Status: String, Codable, Sendable {
        case pending
        case inProgress = "in_progress"
        case completed
        case skipped
    }

    init(
        content: String, priority: Priority, keywords: [String],
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
        self.detectedSpeech = nil
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

    var completionRate: Float { total > 0 ? Float(completed) / Float(total) : 0 }
    var mustCompletionRate: Float { mustTotal > 0 ? Float(mustCompleted) / Float(mustTotal) : 1.0 }
    var summary: String {
        "TP: \(completed)/\(total) (\(String(format: "%.0f", completionRate * 100))%) | MUST: \(mustCompleted)/\(mustTotal)"
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
        case mustNotCovered
        case timeRunningOut
        case topicRelevant
        case driftWarning
    }
    enum Urgency: String, Sendable {
        case low, medium, high, critical
    }
}

// MARK: - Talking Points Tracker

actor TalkingPointsTracker {

    private var talkingPoints: [TalkingPoint] = []
    private let matchThreshold: Int = 2
    private var meetingDurationMinutes: Int = 60
    private var meetingStartTime: Date?
    private var lastReminderTime: Date = .distantPast
    private let reminderCooldown: TimeInterval = 120.0
    private var sentReminders: Set<UUID> = []

    func loadTalkingPoints(_ points: [TalkingPoint], meetingDurationMinutes: Int = 60) {
        self.talkingPoints = points.sorted { $0.priority < $1.priority }
        self.meetingDurationMinutes = meetingDurationMinutes
        let must  = points.filter { $0.priority == .must }.count
        let shld  = points.filter { $0.priority == .should }.count
        let nice  = points.filter { $0.priority == .nice }.count
        print("📋 TP Tracker: \(points.count) loaded (MUST: \(must), SHOULD: \(shld), NICE: \(nice))")
    }

    func markMeetingStarted() { meetingStartTime = Date() }

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
                talkingPoints[i].status = .completed
                talkingPoints[i].completedAt = Date()
                talkingPoints[i].matchedTranscript = String(recentText.suffix(80))
                // ★ 記錄偵測到的說話內容
                talkingPoints[i].detectedSpeech = String(recentText.suffix(50))
                print("✅ TP completed: \(talkingPoints[i].content) [\(matchedKeywords.joined(separator: ", "))]")

            } else if matchedKeywords.count >= 1 && talkingPoints[i].status == .pending {
                talkingPoints[i].status = .inProgress
                // ★ 部分命中也記錄
                talkingPoints[i].detectedSpeech = "...提到 \(matchedKeywords.joined(separator: "、"))..."

            } else if matchedKeywords.count >= 1
                        && !sentReminders.contains(talkingPoints[i].id) {
                reminders.append(TPReminder(
                    type: .topicRelevant,
                    talkingPoint: talkingPoints[i],
                    message: "話題與「\(talkingPoints[i].content)」相關，適合帶入",
                    urgency: .medium,
                    timestamp: Date()
                ))
            }
        }

        reminders.append(contentsOf: checkTimeBasedReminders())
        return reminders
    }

    private func checkTimeBasedReminders() -> [TPReminder] {
        guard let startTime = meetingStartTime else { return [] }
        let now = Date()
        guard now.timeIntervalSince(lastReminderTime) >= reminderCooldown else { return [] }
        let elapsedMinutes = now.timeIntervalSince(startTime) / 60.0
        let progressRatio = elapsedMinutes / Double(meetingDurationMinutes)
        var reminders: [TPReminder] = []

        if progressRatio > 0.5 {
            let unfinishedMust = talkingPoints.filter {
                $0.priority == .must && $0.status != .completed && $0.status != .skipped
            }
            for tp in unfinishedMust {
                guard !sentReminders.contains(tp.id) else { continue }
                let urgency: TPReminder.Urgency = progressRatio > 0.75 ? .critical : .high
                reminders.append(TPReminder(
                    type: .mustNotCovered, talkingPoint: tp,
                    message: urgency == .critical
                        ? "⚠️ 會議即將結束，MUST「\(tp.content)」還沒講到！"
                        : "會議已過半，記得提到「\(tp.content)」",
                    urgency: urgency, timestamp: now
                ))
                sentReminders.insert(tp.id)
            }
        }
        if !reminders.isEmpty { lastReminderTime = now }
        return reminders
    }

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
            talkingPoints[i].detectedSpeech = nil
        }
        sentReminders.removeAll()
        lastReminderTime = .distantPast
        meetingStartTime = nil
    }
}
