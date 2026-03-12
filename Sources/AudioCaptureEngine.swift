// ═══════════════════════════════════════════════════════════════════════════
// AudioCaptureEngine.swift
// MeetingCopilot v4.3.1 — Core Audio Capture Protocol & Types
// ═══════════════════════════════════════════════════════════════════════════

import Foundation
import AVFoundation
import Speech
import ScreenCaptureKit

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
    // ── 會議軟體 (Tier 0) ──
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
    
    var detectionPriority: Int {
        switch self {
        case .microsoftTeams, .zoom, .webex: return 0
        case .googleMeet: return 1
        case .slack, .discord: return 2
        case .line, .whatsapp, .whatsappNative, .telegram, .facetime: return 3
        }
    }
    
    static func from(bundleID: String) -> MeetingApp? {
        allCases.first { $0.bundleIdentifier == bundleID }
    }
}

// MARK: - ★ 偵測結果（用於 App 選擇 UI）

struct DetectedAppInfo: Identifiable, Sendable {
    let id = UUID()
    let app: MeetingApp
    let windowArea: CGFloat
    let priority: Int
    
    var displayName: String { app.displayName }
    
    var tierLabel: String {
        switch priority {
        case 0: return "會議"
        case 1: return "瀏覽器"
        case 2: return "協作"
        case 3: return "通訊"
        default: return ""
        }
    }
}

// MARK: - ★ 靜態工具：掃描活躍 App

enum AppScanner {
    static func scanActiveApps() async -> [DetectedAppInfo] {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            var results: [DetectedAppInfo] = []
            for app in content.applications {
                guard let meetingApp = MeetingApp.from(bundleID: app.bundleIdentifier) else { continue }
                let activeWindows = content.windows.filter { w in
                    w.owningApplication?.bundleIdentifier == app.bundleIdentifier
                    && w.isOnScreen && w.frame.width > 200 && w.frame.height > 200
                }
                guard !activeWindows.isEmpty else { continue }
                let maxArea = activeWindows.map { $0.frame.width * $0.frame.height }.max() ?? 0
                results.append(DetectedAppInfo(app: meetingApp, windowArea: maxArea, priority: meetingApp.detectionPriority))
            }
            let browserBundles = ["com.google.Chrome", "com.apple.Safari", "com.microsoft.edgemac", "org.mozilla.firefox"]
            for app in content.applications {
                if browserBundles.contains(app.bundleIdentifier) {
                    for window in content.windows where window.owningApplication?.bundleIdentifier == app.bundleIdentifier {
                        if let title = window.title, (title.contains("Meet") || title.contains("meet.google.com")) {
                            let area = window.frame.width * window.frame.height
                            if !results.contains(where: { $0.app == .googleMeet }) {
                                results.append(DetectedAppInfo(app: .googleMeet, windowArea: area, priority: 1))
                            }
                            break
                        }
                    }
                }
            }
            return results.sorted { a, b in
                if a.priority != b.priority { return a.priority < b.priority }
                return a.windowArea > b.windowArea
            }
        } catch { return [] }
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
    let targetApp: MeetingApp?
    
    static let `default` = AudioCaptureConfiguration(
        sampleRate: 48000.0, channelCount: 1,
        speechLocale: Locale(identifier: "zh-TW"),
        enablePartialResults: true, bufferSize: 1024,
        autoDetectMeetingApp: true, targetApp: nil
    )
    
    static let english = AudioCaptureConfiguration(
        sampleRate: 48000.0, channelCount: 1,
        speechLocale: Locale(identifier: "en-US"),
        enablePartialResults: true, bufferSize: 1024,
        autoDetectMeetingApp: true, targetApp: nil
    )
    
    func withTarget(_ app: MeetingApp) -> AudioCaptureConfiguration {
        AudioCaptureConfiguration(
            sampleRate: sampleRate, channelCount: channelCount,
            speechLocale: speechLocale, enablePartialResults: enablePartialResults,
            bufferSize: bufferSize, autoDetectMeetingApp: false, targetApp: app
        )
    }
}
