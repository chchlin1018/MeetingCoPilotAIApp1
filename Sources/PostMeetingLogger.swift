// PostMeetingLogger.swift
// MeetingCopilot v4.3.1 — Post-Meeting Diagnostic Log Writer
// Full meeting analytics: system, audio, AI, timing, connections

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

// MARK: - Connection Status

struct ConnectionStatus: Sendable {
    let claudeAPI: ConnectionState
    let notionAPI: ConnectionState
    let notebookLM: ConnectionState
    
    enum ConnectionState: String, Sendable {
        case connected = "✅ Connected"
        case failed = "❌ Failed"
        case notConfigured = "⚠️ Not Configured"
        case notUsed = "— Not Used"
    }
    
    static let empty = ConnectionStatus(claudeAPI: .notUsed, notionAPI: .notUsed, notebookLM: .notUsed)
}

// MARK: - Speaking Time Info

struct SpeakingTimeInfo: Sendable {
    let remoteFinalSegments: Int      // 對方 isFinal 段落數
    let localFinalSegments: Int       // 我方 isFinal 段落數
    let remoteCharCount: Int          // 對方總字數
    let localCharCount: Int           // 我方總字數
    let remoteEstimatedMinutes: Double // 對方估計發言時間（分鐘）
    let localEstimatedMinutes: Double  // 我方估計發言時間（分鐘）
    
    static let empty = SpeakingTimeInfo(
        remoteFinalSegments: 0, localFinalSegments: 0,
        remoteCharCount: 0, localCharCount: 0,
        remoteEstimatedMinutes: 0, localEstimatedMinutes: 0
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
    // ★ 新增
    let audioSourceApp: String          // 會議音源 App
    let connections: ConnectionStatus   // 各服務連接狀態
    let speakingTime: SpeakingTimeInfo  // 發言時間統計
    let totalTranscriptEntries: Int     // 總轉錄條數
}

// MARK: - Post Meeting Logger

enum PostMeetingLogger {
    
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
        let durationMinutes: Double
        if let start = log.startTime {
            let secs = log.endTime.timeIntervalSince(start)
            durationMinutes = secs / 60
            duration = "\(Int(secs / 60))m \(Int(secs.truncatingRemainder(dividingBy: 60)))s"
        } else {
            durationMinutes = 0
            duration = "N/A"
        }
        let overallStatus = determineOverallStatus(log)
        var lines: [String] = []
        
        // ========== HEADER ==========
        lines.append("# MeetingCopilot Post-Meeting Diagnostic Log")
        lines.append("# Generated: \(df.string(from: log.endTime))")
        lines.append("# Version: v4.3.1")
        lines.append("")
        
        // ========== STATUS ==========
        lines.append("[STATUS]")
        lines.append("overall=\(overallStatus.emoji) \(overallStatus.text)")
        lines.append("")
        
        // ========== MEETING INFO ==========
        lines.append("[MEETING]")
        lines.append("title=\(log.meetingTitle)")
        lines.append("start_time=\(log.startTime.map { df.string(from: $0) } ?? "N/A")")
        lines.append("end_time=\(df.string(from: log.endTime))")
        lines.append("duration=\(duration)")
        lines.append("duration_minutes=\(String(format: "%.1f", durationMinutes))")
        lines.append("language=\(log.language)")
        lines.append("dual_stream=\(log.hasDualStream ? "YES" : "NO")")
        lines.append("audio_source_app=\(log.audioSourceApp.isEmpty ? "N/A" : log.audioSourceApp)")
        lines.append("total_transcript_entries=\(log.totalTranscriptEntries)")
        lines.append("")
        
        // ========== SYSTEM ==========
        lines.append("[SYSTEM]")
        lines.append("screen_recording_permission=\(log.screenRecordingPermission ? "✅ OK" : "❌ DENIED (TCC)")")
        lines.append("mic_device=\(log.micDevice)")
        lines.append("bluetooth_detected=\(log.bluetoothDetected ? "⚠️ YES (auto-switched to built-in)" : "✅ NO")")
        lines.append("")
        
        // ========== CONNECTIONS ==========
        lines.append("[CONNECTIONS]")
        lines.append("claude_api=\(log.connections.claudeAPI.rawValue)")
        lines.append("notion_api=\(log.connections.notionAPI.rawValue)")
        lines.append("notebooklm=\(log.connections.notebookLM.rawValue)")
        lines.append("")
        
        // ========== REMOTE ENGINE ==========
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
            lines.append("error_count=\(log.remoteDiag.errors.count)")
            for (i, err) in log.remoteDiag.errors.prefix(10).enumerated() {
                lines.append("  error_\(i+1)=\(err)")
            }
        }
        lines.append("")
        
        // ========== LOCAL ENGINE ==========
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
            lines.append("error_count=\(log.localDiag.errors.count)")
            for (i, err) in log.localDiag.errors.prefix(10).enumerated() {
                lines.append("  error_\(i+1)=\(err)")
            }
        }
        lines.append("")
        
        // ========== SPEAKING TIME ==========
        lines.append("[SPEAKING_TIME]")
        lines.append("remote_final_segments=\(log.speakingTime.remoteFinalSegments)")
        lines.append("local_final_segments=\(log.speakingTime.localFinalSegments)")
        lines.append("remote_char_count=\(log.speakingTime.remoteCharCount)")
        lines.append("local_char_count=\(log.speakingTime.localCharCount)")
        lines.append("remote_estimated_speaking_minutes=\(String(format: "%.1f", log.speakingTime.remoteEstimatedMinutes))")
        lines.append("local_estimated_speaking_minutes=\(String(format: "%.1f", log.speakingTime.localEstimatedMinutes))")
        let totalSpeaking = log.speakingTime.remoteEstimatedMinutes + log.speakingTime.localEstimatedMinutes
        if totalSpeaking > 0 {
            let remotePct = log.speakingTime.remoteEstimatedMinutes / totalSpeaking * 100
            let localPct = log.speakingTime.localEstimatedMinutes / totalSpeaking * 100
            lines.append("remote_speaking_ratio=\(String(format: "%.0f", remotePct))%")
            lines.append("local_speaking_ratio=\(String(format: "%.0f", localPct))%")
        }
        if durationMinutes > 0 {
            let silenceMinutes = durationMinutes - totalSpeaking
            lines.append("silence_minutes=\(String(format: "%.1f", max(0, silenceMinutes)))")
        }
        lines.append("")
        
        // ========== AI USAGE ==========
        lines.append("[AI_USAGE]")
        lines.append("qa_items_loaded=\(log.stats.qaItemsLoaded)")
        lines.append("local_keyword_matches=\(log.stats.localMatches)")
        lines.append("notebooklm_rag_queries=\(log.stats.notebookLMQueries)")
        lines.append("claude_ai_queries=\(log.stats.claudeQueries)")
        lines.append("claude_strategy_analyses=\(log.stats.strategyAnalyses)")
        lines.append("total_ai_cards_generated=\(log.stats.totalCards)")
        let totalAIQueries = log.stats.claudeQueries + log.stats.strategyAnalyses
        lines.append("total_ai_api_calls=\(totalAIQueries)")
        lines.append("avg_claude_latency_ms=\(String(format: "%.0f", log.stats.averageClaudeLatencyMs))")
        lines.append("total_claude_latency_ms=\(String(format: "%.0f", log.stats.totalClaudeLatencyMs))")
        lines.append("estimated_ai_cost_usd=$\(String(format: "%.3f", log.stats.estimatedClaudeCost))")
        // 估算 token 使用量（粗略估算）
        let estimatedInputTokens = totalAIQueries * 2000  // 平均每次查詢 ~2000 input tokens
        let estimatedOutputTokens = totalAIQueries * 500   // 平均每次回應 ~500 output tokens
        lines.append("estimated_input_tokens=~\(estimatedInputTokens)")
        lines.append("estimated_output_tokens=~\(estimatedOutputTokens)")
        lines.append("")
        
        // ========== TALKING POINTS ==========
        lines.append("[TALKING_POINTS]")
        lines.append("total=\(log.tpStats.total)")
        lines.append("completed=\(log.tpStats.completed)")
        lines.append("must_total=\(log.tpStats.mustTotal)")
        lines.append("must_completed=\(log.tpStats.mustCompleted)")
        lines.append("should_total=\(log.tpStats.shouldTotal)")
        lines.append("should_completed=\(log.tpStats.shouldCompleted)")
        lines.append("must_completion_rate=\(String(format: "%.0f", log.tpStats.mustCompletionRate * 100))%")
        lines.append("")
        
        // ========== ERROR LOG ==========
        if !log.errorLog.isEmpty {
            lines.append("[ERROR_LOG]")
            for (i, err) in log.errorLog.enumerated() {
                lines.append("\(i+1). \(err)")
            }
            lines.append("")
        }
        
        // ========== SUMMARY ==========
        lines.append("[SUMMARY]")
        lines.append("\(overallStatus.emoji) \(overallStatus.detail)")
        lines.append("")
        lines.append("Meeting: \(log.meetingTitle) | Duration: \(duration) | Language: \(log.language)")
        lines.append("Audio Source: \(log.audioSourceApp.isEmpty ? "N/A" : log.audioSourceApp) | Dual Stream: \(log.hasDualStream ? "YES" : "NO")")
        lines.append("Remote Segments: \(log.remoteDiag.segmentCount) | Local Segments: \(log.localDiag.segmentCount)")
        if totalSpeaking > 0 {
            lines.append("Speaking: Remote \(String(format: "%.1f", log.speakingTime.remoteEstimatedMinutes))min / Local \(String(format: "%.1f", log.speakingTime.localEstimatedMinutes))min")
        }
        lines.append("AI: \(totalAIQueries) queries | \(log.stats.totalCards) cards | $\(String(format: "%.3f", log.stats.estimatedClaudeCost))")
        lines.append("TP: \(log.tpStats.completed)/\(log.tpStats.total) completed (MUST: \(log.tpStats.mustCompleted)/\(log.tpStats.mustTotal))")
        lines.append("")
        lines.append("# End of Log")
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Overall Status
    
    private struct OverallStatus { let emoji: String; let text: String; let detail: String }
    
    private static func determineOverallStatus(_ log: MeetingSessionLog) -> OverallStatus {
        var issues: [String] = []
        if !log.screenRecordingPermission { issues.append("螢幕錄製權限未授權") }
        if !log.remoteDiag.hasReceivedSpeech && log.remoteDiag.segmentCount == 0 { issues.append("對方音訊未辨識") }
        if !log.localDiag.hasReceivedSpeech && log.localDiag.segmentCount == 0 { issues.append("我方麥克風未辨識") }
        if log.localDiag.bufferCount > 0 {
            let sp = Float(log.localDiag.silentBufferCount) / Float(log.localDiag.bufferCount)
            if sp > 0.95 { issues.append("麥克風 95%+ 靜音") }
        }
        if log.remoteDiag.restartCount > 20 { issues.append("對方重啟過多(\(log.remoteDiag.restartCount))") }
        if log.localDiag.restartCount > 20 { issues.append("我方重啟過多(\(log.localDiag.restartCount))") }
        if log.bluetoothDetected { issues.append("藍牙麥克風已自動切換") }
        if log.connections.claudeAPI == .failed { issues.append("Claude API 連接失敗") }
        
        if issues.isEmpty {
            return OverallStatus(emoji: "✅", text: "ALL OK", detail: "會議系統運作正常")
        } else if issues.contains(where: { $0.contains("未授權") || $0.contains("未辨識") || $0.contains("失敗") }) {
            return OverallStatus(emoji: "❌", text: "ISSUES FOUND", detail: issues.joined(separator: "; "))
        } else {
            return OverallStatus(emoji: "⚠️", text: "OK WITH WARNINGS", detail: issues.joined(separator: "; "))
        }
    }
    
    // MARK: - File Operations
    
    private static func buildFilename(title: String, date: Date) -> String {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd_HHmm"
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
        if let found = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) { return found }
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
