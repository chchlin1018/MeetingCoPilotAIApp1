// PostMeetingLogger.swift
// MeetingCopilot v4.3.1 — Post-Meeting Diagnostic Log Writer
// Saves session log to MeetingTEXT folder after each meeting

import Foundation

// MARK: - Engine Diagnostic Info

struct EngineDiagnosticInfo: Sendable {
    let engineType: String
    let isActive: Bool
    let bufferCount: Int
    let restartCount: Int
    let hasReceivedSpeech: Bool
    let segmentCount: Int
    let useOnDevice: Bool
    let lastRMS: Float
    let silentBufferCount: Int
    let detectedAppName: String?
    let errors: [String]
    
    static let empty = EngineDiagnosticInfo(
        engineType: "N/A", isActive: false, bufferCount: 0, restartCount: 0,
        hasReceivedSpeech: false, segmentCount: 0, useOnDevice: false,
        lastRMS: 0, silentBufferCount: 0, detectedAppName: nil, errors: []
    )
}

// MARK: - Meeting Session Log

struct MeetingSessionLog {
    let meetingTitle: String
    let startTime: Date?
    let endTime: Date
    let language: String
    let hasDualStream: Bool
    let remoteDiag: EngineDiagnosticInfo
    let localDiag: EngineDiagnosticInfo
    let stats: SessionStats
    let tpStats: TPStats
    let screenRecordingPermission: Bool
    let micDevice: String
    let bluetoothDetected: Bool
    let errorLog: [String]
}

// MARK: - Post Meeting Logger

enum PostMeetingLogger {
    
    /// 儲存會議診斷 Log 到 MeetingTEXT 資料夾
    static func saveLog(_ log: MeetingSessionLog) {
        let content = buildLogContent(log)
        let filename = buildFilename(title: log.meetingTitle, date: log.endTime)
        
        guard let folder = findMeetingTEXTFolder() else {
            print("❌ [LOG] Cannot find MeetingTEXT folder, saving to Desktop")
            let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
            writeFile(content: content, folder: desktop, filename: filename)
            return
        }
        
        writeFile(content: content, folder: folder, filename: filename)
    }
    
    // MARK: - Build Log Content
    
    private static func buildLogContent(_ log: MeetingSessionLog) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        let duration: String
        if let start = log.startTime {
            let secs = log.endTime.timeIntervalSince(start)
            duration = "\(Int(secs / 60))m \(Int(secs.truncatingRemainder(dividingBy: 60)))s"
        } else {
            duration = "N/A"
        }
        
        let overallStatus = determineOverallStatus(log)
        
        var lines: [String] = []
        
        // Header
        lines.append("# MeetingCopilot Post-Meeting Diagnostic Log")
        lines.append("# Generated: \(df.string(from: log.endTime))")
        lines.append("")
        
        // Overall Status
        lines.append("[STATUS]")
        lines.append("overall=\(overallStatus.emoji) \(overallStatus.text)")
        lines.append("meeting_title=\(log.meetingTitle)")
        lines.append("start_time=\(log.startTime.map { df.string(from: $0) } ?? "N/A")")
        lines.append("end_time=\(df.string(from: log.endTime))")
        lines.append("duration=\(duration)")
        lines.append("language=\(log.language)")
        lines.append("dual_stream=\(log.hasDualStream ? "YES" : "NO")")
        lines.append("")
        
        // System Status
        lines.append("[SYSTEM]")
        lines.append("screen_recording_permission=\(log.screenRecordingPermission ? "✅ OK" : "❌ DENIED (TCC)")")
        lines.append("mic_device=\(log.micDevice)")
        lines.append("bluetooth_detected=\(log.bluetoothDetected ? "⚠️ YES (auto-switched to built-in)" : "✅ NO")")
        lines.append("")
        
        // Remote Engine (對方)
        lines.append("[REMOTE_ENGINE]")
        lines.append("status=\(log.remoteDiag.isActive || log.remoteDiag.hasReceivedSpeech ? "✅ OK" : "❌ FAILED")")
        lines.append("type=\(log.remoteDiag.engineType)")
        lines.append("detected_app=\(log.remoteDiag.detectedAppName ?? "N/A")")
        lines.append("recognition_mode=Server")
        lines.append("segments_recognized=\(log.remoteDiag.segmentCount)")
        lines.append("buffers_processed=\(log.remoteDiag.bufferCount)")
        lines.append("speech_restarts=\(log.remoteDiag.restartCount)")
        lines.append("ever_received_speech=\(log.remoteDiag.hasReceivedSpeech ? "YES" : "NO")")
        if !log.remoteDiag.errors.isEmpty {
            lines.append("errors=\(log.remoteDiag.errors.count)")
            for (i, err) in log.remoteDiag.errors.prefix(10).enumerated() {
                lines.append("  error_\(i+1)=\(err)")
            }
        }
        lines.append("")
        
        // Local Engine (我方)
        lines.append("[LOCAL_ENGINE]")
        lines.append("status=\(log.localDiag.isActive || log.localDiag.hasReceivedSpeech ? "✅ OK" : "❌ FAILED")")
        lines.append("type=\(log.localDiag.engineType)")
        lines.append("recognition_mode=\(log.localDiag.useOnDevice ? "On-Device" : "Server")")
        lines.append("segments_recognized=\(log.localDiag.segmentCount)")
        lines.append("buffers_processed=\(log.localDiag.bufferCount)")
        lines.append("speech_restarts=\(log.localDiag.restartCount)")
        lines.append("ever_received_speech=\(log.localDiag.hasReceivedSpeech ? "YES" : "NO")")
        let silentPct = log.localDiag.bufferCount > 0 ? Float(log.localDiag.silentBufferCount) / Float(log.localDiag.bufferCount) * 100 : 0
        lines.append("last_rms=\(String(format: "%.6f", log.localDiag.lastRMS))")
        lines.append("silent_buffers=\(log.localDiag.silentBufferCount)/\(log.localDiag.bufferCount) (\(String(format: "%.0f", silentPct))%)")
        if !log.localDiag.errors.isEmpty {
            lines.append("errors=\(log.localDiag.errors.count)")
            for (i, err) in log.localDiag.errors.prefix(10).enumerated() {
                lines.append("  error_\(i+1)=\(err)")
            }
        }
        lines.append("")
        
        // AI Stats
        lines.append("[AI_STATS]")
        lines.append("qa_items_loaded=\(log.stats.qaItemsLoaded)")
        lines.append("local_matches=\(log.stats.localMatches)")
        lines.append("notebooklm_queries=\(log.stats.notebookLMQueries)")
        lines.append("claude_queries=\(log.stats.claudeQueries)")
        lines.append("strategy_analyses=\(log.stats.strategyAnalyses)")
        lines.append("total_cards=\(log.stats.totalCards)")
        lines.append("avg_claude_latency_ms=\(String(format: "%.0f", log.stats.averageClaudeLatencyMs))")
        lines.append("estimated_cost=$\(String(format: "%.2f", log.stats.estimatedClaudeCost))")
        lines.append("")
        
        // Talking Points
        lines.append("[TALKING_POINTS]")
        lines.append("total=\(log.tpStats.total)")
        lines.append("completed=\(log.tpStats.completed)")
        lines.append("must_total=\(log.tpStats.mustTotal)")
        lines.append("must_completed=\(log.tpStats.mustCompleted)")
        lines.append("completion_rate=\(String(format: "%.0f", log.tpStats.mustCompletionRate * 100))%")
        lines.append("")
        
        // Error Log
        if !log.errorLog.isEmpty {
            lines.append("[ERROR_LOG]")
            for (i, err) in log.errorLog.enumerated() {
                lines.append("\(i+1). \(err)")
            }
            lines.append("")
        }
        
        // Summary
        lines.append("[SUMMARY]")
        lines.append("\(overallStatus.emoji) \(overallStatus.detail)")
        lines.append("")
        lines.append("# End of Log")
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Overall Status
    
    private struct OverallStatus {
        let emoji: String
        let text: String
        let detail: String
    }
    
    private static func determineOverallStatus(_ log: MeetingSessionLog) -> OverallStatus {
        var issues: [String] = []
        
        if !log.screenRecordingPermission {
            issues.append("螢幕錄製權限未授權（對方音訊無法擷取）")
        }
        if !log.remoteDiag.hasReceivedSpeech && log.remoteDiag.segmentCount == 0 {
            issues.append("對方音訊未辨識到任何語音")
        }
        if !log.localDiag.hasReceivedSpeech && log.localDiag.segmentCount == 0 {
            issues.append("我方麥克風未辨識到任何語音")
        }
        if log.localDiag.bufferCount > 0 {
            let silentPct = Float(log.localDiag.silentBufferCount) / Float(log.localDiag.bufferCount)
            if silentPct > 0.95 { issues.append("麥克風 95%+ 靜音（可能裝置問題）") }
        }
        if log.remoteDiag.restartCount > 20 { issues.append("對方語音辨識重啟過多 (\(log.remoteDiag.restartCount))") }
        if log.localDiag.restartCount > 20 { issues.append("我方語音辨識重啟過多 (\(log.localDiag.restartCount))") }
        if log.bluetoothDetected { issues.append("偵測到藍牙麥克風（已自動切換）") }
        
        if issues.isEmpty {
            return OverallStatus(emoji: "✅", text: "ALL OK", detail: "會議系統運作正常，無錯誤")
        } else if issues.contains(where: { $0.contains("未授權") || $0.contains("未辨識") }) {
            return OverallStatus(emoji: "❌", text: "ISSUES FOUND", detail: issues.joined(separator: "; "))
        } else {
            return OverallStatus(emoji: "⚠️", text: "OK WITH WARNINGS", detail: issues.joined(separator: "; "))
        }
    }
    
    // MARK: - File Operations
    
    private static func buildFilename(title: String, date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd_HHmm"
        let dateStr = df.string(from: date)
        let safeName = title.replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return "\(dateStr)_\(safeName)_LOG.txt"
    }
    
    private static func findMeetingTEXTFolder() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent("Documents/MyProjects/MeetingCopilotApp1/MeetingTEXT"),
            home.appendingPathComponent("Documents/MyProjects/MeetingCoPilotAIApp1/MeetingTEXT"),
            home.appendingPathComponent("Desktop/MeetingTEXT"),
        ]
        if let found = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            return found
        }
        // 嘗試建立第一個路徑
        let preferred = candidates[0]
        try? FileManager.default.createDirectory(at: preferred, withIntermediateDirectories: true)
        return FileManager.default.fileExists(atPath: preferred.path) ? preferred : nil
    }
    
    private static func writeFile(content: String, folder: URL, filename: String) {
        let url = folder.appendingPathComponent(filename)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            print("📝 [LOG] Meeting log saved: \(url.path)")
        } catch {
            print("❌ [LOG] Failed to save meeting log: \(error)")
        }
    }
}
