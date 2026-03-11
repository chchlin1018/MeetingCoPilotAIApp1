// ═══════════════════════════════════════════════════════════════════════════
// AudioCaptureEngine.swift
// MeetingCopilot v4.3.1 — Core Audio Capture Protocol & Types
// ═══════════════════════════════════════════════════════════════════════════
//
// Platform: macOS 14.0+
// Framework: ScreenCaptureKit, AVFoundation, Speech
// Supported Apps: 11 (Teams/Zoom/Meet/Webex/Slack/LINE/WhatsApp/Telegram/Discord/FaceTime)
// ═══════════════════════════════════════════════════════════════════════════

import Foundation
import AVFoundation
import Speech

// MARK: - 音訊擷取引擎 Protocol

protocol AudioCaptureEngine: AnyObject {
    var transcriptStream: AsyncStream<TranscriptSegment> { get }
    var state: AudioCaptureState { get }
    func start() async throws
    func stop() async
    var engineType: AudioCaptureEngineType { get }
}

// MARK: - 引擎類型

enum AudioCaptureEngineType: String, Sendable {
    case systemAudio = "ScreenCaptureKit"
    case microphone  = "Microphone"
}

// MARK: - 引擎狀態

enum AudioCaptureState: Sendable {
    case idle
    case preparing
    case capturing
    case paused
    case error(AudioCaptureError)
    
    var isActive: Bool {
        if case .capturing = self { return true }
        return false
    }
}

// MARK: - 錯誤類型

enum AudioCaptureError: Error, LocalizedError, Sendable {
    case permissionDenied
    case noAudioSourceFound
    case speechRecognizerUnavailable
    case engineStartFailed(String)
    case captureInterrupted(String)
    case configurationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "需要螢幕錄製權限才能擷取會議音訊。請在系統設定中授權。"
        case .noAudioSourceFound:
            return "找不到正在播放音訊的應用程式。請確認 Teams/Zoom/Meet/LINE/WhatsApp/FaceTime 正在通話中。"
        case .speechRecognizerUnavailable:
            return "語音辨識服務目前不可用。請確認網路連線正常。"
        case .engineStartFailed(let detail):
            return "音訊擷取引擎啟動失敗：\(detail)"
        case .captureInterrupted(let reason):
            return "音訊擷取中斷：\(reason)"
        case .configurationFailed(let detail):
            return "設定失敗：\(detail)"
        }
    }
}

// MARK: - 轉錄片段

struct TranscriptSegment: Sendable, Identifiable {
    let id = UUID()
    let text: String
    let timestamp: Date
    let isFinal: Bool
    let confidence: Float
    let locale: Locale
    let source: AudioCaptureEngineType
    
    var recentText: String {
        String(text.suffix(50))
    }
}

// MARK: - 會議/通話應用程式識別（11 個 App）

enum MeetingApp: String, CaseIterable, Sendable {
    // ── 會議軟體 (Tier 1) ──
    case microsoftTeams = "com.microsoft.teams2"
    case zoom           = "us.zoom.xos"
    case googleMeet     = "com.google.Chrome"
    case webex          = "com.cisco.webexmeetingsapp"
    // ── 團隊協作 (Tier 2) ──
    case slack          = "com.tinyspeck.slackmacgap"
    case discord        = "com.hnc.Discord"
    // ── 通訊軟體 (Tier 3) ──
    case line           = "jp.naver.line.mac"
    case whatsapp       = "net.whatsapp.WhatsApp"
    case whatsappNative = "WhatsApp"
    case telegram       = "ru.keepcoder.Telegram"
    case facetime       = "com.apple.FaceTime"
    
    var bundleIdentifier: String { rawValue }
    
    var displayName: String {
        switch self {
        case .microsoftTeams: return "Microsoft Teams"
        case .zoom:           return "Zoom"
        case .googleMeet:     return "Google Meet (Chrome)"
        case .webex:          return "Webex"
        case .slack:          return "Slack"
        case .discord:        return "Discord"
        case .line:           return "LINE"
        case .whatsapp:       return "WhatsApp"
        case .whatsappNative: return "WhatsApp (Native)"
        case .telegram:       return "Telegram"
        case .facetime:       return "FaceTime"
        }
    }
    
    /// ★ 偵測優先級（數字越小優先級越高）
    /// Tier 0: Zoom/Teams/Webex — 專業會議軟體，最優先
    /// Tier 1: Google Meet — 瀏覽器會議
    /// Tier 2: Slack/Discord — 團隊協作
    /// Tier 3: LINE/WhatsApp/Telegram/FaceTime — 通訊軟體
    var detectionPriority: Int {
        switch self {
        case .microsoftTeams, .zoom, .webex:
            return 0
        case .googleMeet:
            return 1
        case .slack, .discord:
            return 2
        case .line, .whatsapp, .whatsappNative, .telegram, .facetime:
            return 3
        }
    }
    
    static func from(bundleID: String) -> MeetingApp? {
        allCases.first { $0.bundleIdentifier == bundleID }
    }
}

// MARK: - 音訊擷取設定

struct AudioCaptureConfiguration: Sendable {
    let sampleRate: Double
    let channelCount: Int
    let speechLocale: Locale
    let enablePartialResults: Bool
    let bufferSize: AVAudioFrameCount
    let autoDetectMeetingApp: Bool
    
    static let `default` = AudioCaptureConfiguration(
        sampleRate: 48000.0,
        channelCount: 1,
        speechLocale: Locale(identifier: "zh-TW"),
        enablePartialResults: true,
        bufferSize: 1024,
        autoDetectMeetingApp: true
    )
    
    static let english = AudioCaptureConfiguration(
        sampleRate: 48000.0,
        channelCount: 1,
        speechLocale: Locale(identifier: "en-US"),
        enablePartialResults: true,
        bufferSize: 1024,
        autoDetectMeetingApp: true
    )
}
