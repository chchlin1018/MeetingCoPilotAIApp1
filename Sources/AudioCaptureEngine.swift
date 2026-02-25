// ═══════════════════════════════════════════════════════════════════════════
// AudioCaptureEngine.swift
// MeetingCopilot v4.0 — Core Audio Capture Protocol & Types
// ═══════════════════════════════════════════════════════════════════════════
//
// 定義統一的音訊擷取介面，讓 SystemAudioCaptureEngine（主引擎）和
// MicrophoneCaptureEngine（降級方案）都實作同一個 Protocol。
// 這是 v4.0 插件化架構的基礎。
//
// Platform: macOS 14.0+
// Framework: ScreenCaptureKit, AVFoundation, Speech
// ═══════════════════════════════════════════════════════════════════════════

import Foundation
import AVFoundation
import Speech

// MARK: - 音訊擷取引擎 Protocol

/// 所有音訊擷取引擎的統一介面
/// SystemAudioCaptureEngine 和 MicrophoneCaptureEngine 都實作此 Protocol
protocol AudioCaptureEngine: AnyObject {
    
    /// 即時轉錄文字的 AsyncStream（Partial Results）
    /// UI 層直接 for await 這個 stream 即可獲得即時文字
    var transcriptStream: AsyncStream<TranscriptSegment> { get }
    
    /// 引擎目前狀態
    var state: AudioCaptureState { get }
    
    /// 啟動擷取
    func start() async throws
    
    /// 停止擷取
    func stop() async
    
    /// 引擎類型標識
    var engineType: AudioCaptureEngineType { get }
}

// MARK: - 引擎類型

enum AudioCaptureEngineType: String, Sendable {
    case systemAudio = "ScreenCaptureKit"   // 主引擎：擷取 Teams/Zoom/Meet 系統音訊
    case microphone  = "Microphone"          // 降級方案：擷取麥克風
}

// MARK: - 引擎狀態

enum AudioCaptureState: Sendable {
    case idle                   // 待機
    case preparing              // 準備中（請求權限、初始化）
    case capturing              // 擷取中
    case paused                 // 暫停
    case error(AudioCaptureError)  // 錯誤
    
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
            return "需要螢幕錄製權限才能擷取會議音訊。請在系統設定中授權 MeetingCopilot。"
        case .noAudioSourceFound:
            return "找不到正在播放音訊的會議應用程式。請確認 Teams/Zoom/Meet 正在進行會議。"
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

// MARK: - 會議應用程式識別

enum MeetingApp: String, CaseIterable, Sendable {
    case microsoftTeams = "com.microsoft.teams2"
    case zoom           = "us.zoom.xos"
    case googleMeet     = "com.google.Chrome"
    case webex          = "com.cisco.webexmeetingsapp"
    case slack          = "com.tinyspeck.slackmacgap"
    
    var bundleIdentifier: String { rawValue }
    
    var displayName: String {
        switch self {
        case .microsoftTeams: return "Microsoft Teams"
        case .zoom:           return "Zoom"
        case .googleMeet:     return "Google Meet (Chrome)"
        case .webex:          return "Webex"
        case .slack:          return "Slack"
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
