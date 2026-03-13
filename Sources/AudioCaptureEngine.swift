// ═══════════════════════════════════════════════════════════════════════════
// AudioCaptureEngine.swift
// MeetingCopilot v4.3.1 — Core Audio Capture Protocol & Types
// + Teams/Meet Web detection on Edge/Chrome/Safari/Firefox
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

// MARK: - 會議/通話應用程式識別（13 個 App）

enum MeetingApp: String, CaseIterable, Sendable {
    // ── 會議軟體 (Tier 0) ──
    case microsoftTeams = "com.microsoft.teams2"
    case zoom           = "us.zoom.xos"
    case webex          = "com.cisco.webexmeetingsapp"
    // ── 瀏覽器會議 (Tier 1) ──
    case googleMeet     = "com.google.Chrome"         // Meet on Chrome
    case teamsWeb       = "com.microsoft.edgemac"      // Teams on Edge
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
        case .teamsWeb:       return "Microsoft Teams (Edge)"
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
        case .googleMeet, .teamsWeb: return 1
        case .slack, .discord: return 2
        case .line, .whatsapp, .whatsappNative, .telegram, .facetime: return 3
        }
    }
    
    static func from(bundleID: String) -> MeetingApp? {
        // ★ 瀏覽器 bundleID 可能對應多個 App（Meet 或 Teams Web）
        // 需要用視窗標題來區分，所以瀏覽器不在這裡直接 match
        let browserBundles = ["com.google.Chrome", "com.microsoft.edgemac", "com.apple.Safari", "org.mozilla.firefox"]
        if browserBundles.contains(bundleID) {
            return nil  // 瀏覽器由 AppScanner 的視窗標題偵測處理
        }
        return allCases.first { $0.bundleIdentifier == bundleID }
    }
}

// MARK: - ★ 偵測結果（用於 App 選擇 UI）

struct DetectedAppInfo: Identifiable, Sendable {
    let id = UUID()
    let app: MeetingApp
    let windowArea: CGFloat
    let priority: Int
    let browserSource: String?  // ★ 新增：瀏覽器名稱（例如 "Edge", "Chrome", "Safari"）
    
    var displayName: String {
        if let browser = browserSource {
            switch app {
            case .teamsWeb: return "Microsoft Teams (\(browser))"
            case .googleMeet: return "Google Meet (\(browser))"
            default: return app.displayName
            }
        }
        return app.displayName
    }
    
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

// MARK: - ★ 瀏覽器會議偵測器

enum BrowserMeetingDetector {
    
    /// 瀏覽器 bundleID 對應名稱
    static let browserNames: [String: String] = [
        "com.google.Chrome": "Chrome",
        "com.microsoft.edgemac": "Edge",
        "com.apple.Safari": "Safari",
        "org.mozilla.firefox": "Firefox",
    ]
    
    static let browserBundles = Array(browserNames.keys)
    
    /// 從瀏覽器視窗標題偵測會議類型
    static func detectFromWindowTitle(_ title: String) -> MeetingApp? {
        let lower = title.lowercased()
        
        // ★ Teams Web 偵測
        if lower.contains("teams") || lower.contains("teams.microsoft.com") || lower.contains("teams.live.com") {
            return .teamsWeb
        }
        
        // ★ Google Meet 偵測
        if lower.contains("meet") || lower.contains("meet.google.com") {
            return .googleMeet
        }
        
        // ★ Zoom Web 偵測
        if lower.contains("zoom") || lower.contains("zoom.us") {
            return .zoom
        }
        
        // ★ Webex Web 偵測
        if lower.contains("webex") {
            return .webex
        }
        
        return nil
    }
}

// MARK: - ★ 靜態工具：掃描活躍 App

enum AppScanner {
    static func scanActiveApps() async -> [DetectedAppInfo] {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            var results: [DetectedAppInfo] = []
            
            // ★ Step 1: 偵測原生 App（非瀏覽器）
            for app in content.applications {
                guard let meetingApp = MeetingApp.from(bundleID: app.bundleIdentifier) else { continue }
                let activeWindows = content.windows.filter { w in
                    w.owningApplication?.bundleIdentifier == app.bundleIdentifier
                    && w.isOnScreen && w.frame.width > 200 && w.frame.height > 200
                }
                guard !activeWindows.isEmpty else { continue }
                let maxArea = activeWindows.map { $0.frame.width * $0.frame.height }.max() ?? 0
                results.append(DetectedAppInfo(app: meetingApp, windowArea: maxArea, priority: meetingApp.detectionPriority, browserSource: nil))
            }
            
            // ★ Step 2: 偵測瀏覽器中的會議（Teams Web / Meet / Zoom Web / Webex Web）
            for app in content.applications {
                guard BrowserMeetingDetector.browserBundles.contains(app.bundleIdentifier) else { continue }
                let browserName = BrowserMeetingDetector.browserNames[app.bundleIdentifier] ?? "Browser"
                
                for window in content.windows where window.owningApplication?.bundleIdentifier == app.bundleIdentifier {
                    guard let title = window.title, window.isOnScreen, window.frame.width > 200, window.frame.height > 200 else { continue }
                    
                    if let detectedApp = BrowserMeetingDetector.detectFromWindowTitle(title) {
                        // 避免重複加入同一類型
                        if !results.contains(where: { $0.app == detectedApp }) {
                            let area = window.frame.width * window.frame.height
                            let priority = detectedApp.detectionPriority
                            results.append(DetectedAppInfo(app: detectedApp, windowArea: area, priority: priority, browserSource: browserName))
                            print("  🌐 Browser meeting detected: \(detectedApp.displayName) on \(browserName) (title: \"\(title.prefix(50))\")")
                        }
                        break
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
