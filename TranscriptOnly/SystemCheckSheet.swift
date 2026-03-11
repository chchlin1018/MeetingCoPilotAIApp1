// SystemCheckSheet.swift
// TranscriptOnly — feature/transcript-only
// 會前系統檢查：權限 + 功能診斷

import SwiftUI
import AVFoundation
import Speech
import ScreenCaptureKit

// MARK: - Check Item

struct CheckItem: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    var status: CheckStatus = .pending
    var detail: String = ""
    var latencyMs: Int?
    
    enum CheckStatus: String {
        case pending = "等待中"
        case testing = "檢測中..."
        case passed  = "通過"
        case failed  = "失敗"
        case warning = "警告"
    }
}

// MARK: - ViewModel

@Observable
@MainActor
class SystemCheckViewModel {
    var checks: [CheckItem] = []
    var isRunning = false
    var allPassed = false
    var summary = ""
    
    func runAllChecks(language: RecognitionLanguage) {
        isRunning = true
        allPassed = false
        summary = ""
        
        // 初始化 7 項檢查
        checks = [
            CheckItem(name: "麥克風權限", icon: "mic.fill"),
            CheckItem(name: "語音辨識權限", icon: "waveform"),
            CheckItem(name: "螢幕錄製權限", icon: "rectangle.dashed.badge.record"),
            CheckItem(name: "麥克風音訊擷取", icon: "mic.badge.plus"),
            CheckItem(name: "語音辨識引擎 (\(language.rawValue))", icon: "text.bubble"),
            CheckItem(name: "會議/通話 App 偵測", icon: "app.connected.to.app.below.fill"),
            CheckItem(name: "ScreenCaptureKit 音訊擷取", icon: "speaker.wave.3.fill"),
        ]
        
        Task {
            await check0_micPermission()
            await check1_speechPermission()
            await check2_screenRecordPermission()
            await check3_micAudioCapture()
            await check4_speechRecognizer(language: language)
            await check5_detectApp()
            await check6_screenCaptureAudio()
            
            // 統計
            let passedCount = checks.filter { $0.status == .passed }.count
            let warningCount = checks.filter { $0.status == .warning }.count
            let failedCount = checks.filter { $0.status == .failed }.count
            allPassed = failedCount == 0
            
            if failedCount == 0 && warningCount == 0 {
                summary = "✅ 全部通過！可以開始會議"
            } else if failedCount == 0 {
                summary = "⚠️ \(passedCount) 項通過，\(warningCount) 項警告（可以試試看）"
            } else {
                summary = "❌ \(failedCount) 項失敗，請修復後再試"
            }
            
            isRunning = false
        }
    }
    
    // MARK: - 0. 麥克風權限
    
    private func check0_micPermission() async {
        checks[0].status = .testing
        let start = Date()
        
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            checks[0].status = .passed
            checks[0].detail = "已授權"
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            checks[0].status = granted ? .passed : .failed
            checks[0].detail = granted ? "已授權" : "使用者拒絕"
        case .denied:
            checks[0].status = .failed
            checks[0].detail = "已拒絕 → System Settings → Privacy → Microphone"
        case .restricted:
            checks[0].status = .failed
            checks[0].detail = "受限（系統政策）"
        @unknown default:
            checks[0].status = .warning
            checks[0].detail = "未知狀態"
        }
        checks[0].latencyMs = Int(Date().timeIntervalSince(start) * 1000)
    }
    
    // MARK: - 1. 語音辨識權限
    
    private func check1_speechPermission() async {
        checks[1].status = .testing
        let start = Date()
        
        let status = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
        
        switch status {
        case .authorized:
            checks[1].status = .passed
            checks[1].detail = "已授權"
        case .denied:
            checks[1].status = .failed
            checks[1].detail = "已拒絕 → System Settings → Privacy → Speech Recognition"
        case .restricted:
            checks[1].status = .failed
            checks[1].detail = "受限"
        case .notDetermined:
            checks[1].status = .warning
            checks[1].detail = "未決定"
        @unknown default:
            checks[1].status = .warning
            checks[1].detail = "未知"
        }
        checks[1].latencyMs = Int(Date().timeIntervalSince(start) * 1000)
    }
    
    // MARK: - 2. 螢幕錄製權限 (ScreenCaptureKit)
    
    private func check2_screenRecordPermission() async {
        checks[2].status = .testing
        let start = Date()
        
        do {
            let _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            checks[2].status = .passed
            checks[2].detail = "已授權"
        } catch {
            checks[2].status = .failed
            checks[2].detail = "未授權 → System Settings → Privacy → Screen & System Audio Recording"
        }
        checks[2].latencyMs = Int(Date().timeIntervalSince(start) * 1000)
    }
    
    // MARK: - 3. 麥克風音訊擷取
    
    private func check3_micAudioCapture() async {
        checks[3].status = .testing
        let start = Date()
        
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        
        if format.sampleRate > 0 && format.channelCount > 0 {
            checks[3].status = .passed
            checks[3].detail = "\(Int(format.sampleRate))Hz / \(format.channelCount)ch"
        } else {
            checks[3].status = .failed
            checks[3].detail = "無法取得音訊格式"
        }
        checks[3].latencyMs = Int(Date().timeIntervalSince(start) * 1000)
    }
    
    // MARK: - 4. 語音辨識引擎
    
    private func check4_speechRecognizer(language: RecognitionLanguage) async {
        checks[4].status = .testing
        let start = Date()
        
        let locale = Locale(identifier: language.rawValue)
        if let recognizer = SFSpeechRecognizer(locale: locale) {
            if recognizer.isAvailable {
                let onDevice = recognizer.supportsOnDeviceRecognition
                checks[4].status = .passed
                checks[4].detail = "可用" + (onDevice ? " (支援離線)" : " (需網路)")
            } else {
                checks[4].status = .warning
                checks[4].detail = "引擎存在但目前不可用（請檢查網路）"
            }
        } else {
            checks[4].status = .failed
            checks[4].detail = "不支援 \(language.rawValue)"
        }
        checks[4].latencyMs = Int(Date().timeIntervalSince(start) * 1000)
    }
    
    // MARK: - 5. App 偵測
    
    private func check5_detectApp() async {
        checks[5].status = .testing
        let start = Date()
        
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            var detectedApps: [String] = []
            
            for app in content.applications {
                if let meetingApp = MeetingApp.from(bundleID: app.bundleIdentifier) {
                    detectedApps.append(meetingApp.displayName)
                }
            }
            
            if detectedApps.isEmpty {
                checks[5].status = .warning
                checks[5].detail = "未偵測到支援的 App（請開啟 Teams/Zoom/LINE/WhatsApp/FaceTime）"
            } else {
                checks[5].status = .passed
                checks[5].detail = detectedApps.joined(separator: ", ")
            }
        } catch {
            checks[5].status = .failed
            checks[5].detail = "無法存取 ScreenCaptureKit"
        }
        checks[5].latencyMs = Int(Date().timeIntervalSince(start) * 1000)
    }
    
    // MARK: - 6. ScreenCaptureKit 音訊擷取
    
    private func check6_screenCaptureAudio() async {
        checks[6].status = .testing
        let start = Date()
        
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            
            // 找任何一個支援的 App 的視窗
            var targetWindow: SCWindow?
            for app in content.applications {
                if MeetingApp.from(bundleID: app.bundleIdentifier) != nil {
                    targetWindow = content.windows.first { w in
                        w.owningApplication?.bundleIdentifier == app.bundleIdentifier
                        && w.isOnScreen
                        && w.frame.width > 100 && w.frame.height > 100
                    }
                    if targetWindow != nil { break }
                }
            }
            
            if let window = targetWindow {
                // 嘗試建立 SCStream
                let filter = SCContentFilter(desktopIndependentWindow: window)
                let config = SCStreamConfiguration()
                config.capturesAudio = true
                config.excludesCurrentProcessAudio = true
                config.width = 1
                config.height = 1
                
                let stream = SCStream(filter: filter, configuration: config, delegate: nil)
                // 如果能建立 stream 就算通過
                checks[6].status = .passed
                checks[6].detail = "可擷取音訊"
                _ = stream // 避免 unused warning
            } else {
                checks[6].status = .warning
                checks[6].detail = "無目標視窗（開啟通話 App 後再測試）"
            }
        } catch {
            checks[6].status = .failed
            checks[6].detail = "\(error.localizedDescription)"
        }
        checks[6].latencyMs = Int(Date().timeIntervalSince(start) * 1000)
    }
}

// MARK: - System Check Sheet View

struct SystemCheckSheet: View {
    @State private var vm = SystemCheckViewModel()
    let language: RecognitionLanguage
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "stethoscope")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("系統檢查")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                if !vm.isRunning {
                    Button("關閉") { dismiss() }
                        .keyboardShortcut(.escape)
                }
            }
            .padding()
            
            Divider()
            
            // Check Items
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(vm.checks) { check in
                        checkRow(check)
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer
            HStack {
                if !vm.summary.isEmpty {
                    Text(vm.summary)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(vm.allPassed ? .green : .orange)
                }
                
                Spacer()
                
                Button {
                    vm.runAllChecks(language: language)
                } label: {
                    HStack(spacing: 6) {
                        if vm.isRunning {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(vm.isRunning ? "檢測中..." : "開始檢查")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.isRunning)
            }
            .padding()
        }
        .frame(width: 550, height: 450)
        .onAppear {
            vm.runAllChecks(language: language)
        }
    }
    
    // MARK: - Check Row
    
    private func checkRow(_ check: CheckItem) -> some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: check.icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            
            // Name
            Text(check.name)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 200, alignment: .leading)
            
            // Status
            statusBadge(check.status)
            
            // Detail
            Text(check.detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            
            Spacer()
            
            // Latency
            if let ms = check.latencyMs {
                Text("\(ms)ms")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(rowBackground(check.status))
        .cornerRadius(8)
    }
    
    private func statusBadge(_ status: CheckItem.CheckStatus) -> some View {
        HStack(spacing: 4) {
            switch status {
            case .pending:
                Image(systemName: "circle")
                    .foregroundStyle(.gray)
            case .testing:
                ProgressView()
                    .controlSize(.mini)
            case .passed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            case .warning:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            
            Text(status.rawValue)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(statusColor(status))
        }
        .frame(width: 80)
    }
    
    private func statusColor(_ status: CheckItem.CheckStatus) -> Color {
        switch status {
        case .pending: return .gray
        case .testing: return .blue
        case .passed:  return .green
        case .failed:  return .red
        case .warning: return .orange
        }
    }
    
    private func rowBackground(_ status: CheckItem.CheckStatus) -> Color {
        switch status {
        case .passed:  return .green.opacity(0.08)
        case .failed:  return .red.opacity(0.08)
        case .warning: return .orange.opacity(0.08)
        default:       return .clear
        }
    }
}
