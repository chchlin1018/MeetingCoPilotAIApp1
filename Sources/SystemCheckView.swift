//
//  SystemCheckView.swift
//  MeetingCopilot
//
//  Pre-Meeting System Diagnostics
//  Tests: Microphone, Speech Recognition, System Audio,
//         Claude AI, Notion API, NotebookLM Bridge
//

import SwiftUI
import AVFoundation
import Speech

// MARK: - Check Item Model

enum CheckStatus: String {
    case pending = "pending"
    case testing = "testing"
    case passed = "passed"
    case failed = "failed"
    case skipped = "skipped"
    
    var icon: String {
        switch self {
        case .pending: return "circle"
        case .testing: return "arrow.triangle.2.circlepath"
        case .passed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .skipped: return "minus.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .pending: return .gray
        case .testing: return .orange
        case .passed: return .green
        case .failed: return .red
        case .skipped: return .yellow
        }
    }
}

struct CheckItem: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    var status: CheckStatus = .pending
    var detail: String = ""
    var latencyMs: Int? = nil
}

// MARK: - System Check ViewModel

@MainActor
class SystemCheckViewModel: ObservableObject {
    @Published var checks: [CheckItem] = [
        CheckItem(name: "麥克風權限", description: "Microphone Permission"),
        CheckItem(name: "語音辨識權限", description: "Speech Recognition Permission"),
        CheckItem(name: "螢幕錄製權限", description: "Screen Recording Permission"),
        CheckItem(name: "麥克風音訊擷取", description: "Microphone Audio Capture"),
        CheckItem(name: "語音辨識 (zh-TW)", description: "Speech-to-Text Chinese"),
        CheckItem(name: "Claude AI 連接", description: "Claude API Connection"),
        CheckItem(name: "Notion API 連接", description: "Notion API Connection"),
        CheckItem(name: "NotebookLM Bridge", description: "NotebookLM Bridge Connection"),
    ]
    
    @Published var isRunning = false
    @Published var allPassed = false
    @Published var speechTranscript = ""
    @Published var audioLevel: Float = 0.0
    @Published var showMicTest = false
    
    private var audioEngine: AVAudioEngine?
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var micTestTimer: Timer?
    
    // MARK: - Run All Checks
    
    func runAllChecks() {
        isRunning = true
        allPassed = false
        
        // Reset all to pending
        for i in checks.indices {
            checks[i].status = .pending
            checks[i].detail = ""
            checks[i].latencyMs = nil
        }
        
        Task {
            await checkMicrophonePermission()
            await checkSpeechPermission()
            await checkScreenRecording()
            await checkMicrophoneCapture()
            await checkSpeechRecognition()
            await checkClaudeAPI()
            await checkNotionAPI()
            await checkNotebookLMBridge()
            
            isRunning = false
            allPassed = checks.allSatisfy { $0.status == .passed || $0.status == .skipped }
        }
    }
    
    // MARK: - Individual Checks
    
    private func checkMicrophonePermission() async {
        updateStatus(0, .testing)
        
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            updateStatus(0, .passed, detail: "已授權")
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            updateStatus(0, granted ? .passed : .failed, detail: granted ? "已授權" : "用戶拒絕")
        case .denied:
            updateStatus(0, .failed, detail: "請到 System Settings → Privacy & Security → Microphone 開啟")
        case .restricted:
            updateStatus(0, .failed, detail: "裝置受限")
        @unknown default:
            updateStatus(0, .failed, detail: "未知狀態")
        }
        
        try? await Task.sleep(nanoseconds: 300_000_000)
    }
    
    private func checkSpeechPermission() async {
        updateStatus(1, .testing)
        
        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .authorized:
            updateStatus(1, .passed, detail: "已授權")
        case .notDetermined:
            await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { newStatus in
                    Task { @MainActor in
                        self.updateStatus(1, newStatus == .authorized ? .passed : .failed,
                                        detail: newStatus == .authorized ? "已授權" : "用戶拒絕")
                        continuation.resume()
                    }
                }
            }
        case .denied:
            updateStatus(1, .failed, detail: "請到 System Settings → Privacy & Security → Speech Recognition 開啟")
        case .restricted:
            updateStatus(1, .failed, detail: "裝置受限")
        @unknown default:
            updateStatus(1, .failed, detail: "未知狀態")
        }
        
        try? await Task.sleep(nanoseconds: 300_000_000)
    }
    
    private func checkScreenRecording() async {
        updateStatus(2, .testing)
        
        // ScreenCaptureKit availability check
        if #available(macOS 13.0, *) {
            // We can't directly check screen recording permission without trying
            // Best we can do is check if ScreenCaptureKit is available
            updateStatus(2, .passed, detail: "ScreenCaptureKit 可用。實際權限需開始會議時驗證")
        } else {
            updateStatus(2, .failed, detail: "需要 macOS 13.0+")
        }
        
        try? await Task.sleep(nanoseconds: 300_000_000)
    }
    
    private func checkMicrophoneCapture() async {
        updateStatus(3, .testing)
        
        guard checks[0].status == .passed else {
            updateStatus(3, .skipped, detail: "麥克風權限未通過")
            return
        }
        
        do {
            let engine = AVAudioEngine()
            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            
            var maxLevel: Float = 0
            
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                let channelData = buffer.floatChannelData?[0]
                let frameLength = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<frameLength {
                    sum += abs(channelData?[i] ?? 0)
                }
                let avg = sum / Float(frameLength)
                if avg > maxLevel { maxLevel = avg }
                Task { @MainActor in
                    self.audioLevel = avg
                }
            }
            
            try engine.start()
            
            // Listen for 2 seconds
            try await Task.sleep(nanoseconds: 2_000_000_000)
            
            inputNode.removeTap(onBus: 0)
            engine.stop()
            
            if maxLevel > 0.001 {
                updateStatus(3, .passed, detail: String(format: "音訊正常，最大音量: %.4f", maxLevel))
            } else {
                updateStatus(3, .passed, detail: "音訊引擎正常（未偵測到聲音，請對麥克風說話測試）")
            }
        } catch {
            updateStatus(3, .failed, detail: "音訊引擎錯誤: \(error.localizedDescription)")
        }
        
        try? await Task.sleep(nanoseconds: 300_000_000)
    }
    
    private func checkSpeechRecognition() async {
        updateStatus(4, .testing, detail: "請對麥克風說「測試一二三」...")
        
        guard checks[1].status == .passed else {
            updateStatus(4, .skipped, detail: "語音辨識權限未通過")
            return
        }
        
        showMicTest = true
        speechTranscript = ""
        
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-TW"))
        guard let recognizer = recognizer, recognizer.isAvailable else {
            updateStatus(4, .failed, detail: "zh-TW 語音辨識器不可用")
            showMicTest = false
            return
        }
        
        do {
            let engine = AVAudioEngine()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            
            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            
            try engine.start()
            
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let result = result {
                    Task { @MainActor in
                        self.speechTranscript = result.bestTranscription.formattedString
                    }
                }
            }
            
            // Listen for 5 seconds
            try await Task.sleep(nanoseconds: 5_000_000_000)
            
            task.cancel()
            inputNode.removeTap(onBus: 0)
            engine.stop()
            
            if !speechTranscript.isEmpty {
                updateStatus(4, .passed, detail: "辨識結果: \(speechTranscript)")
            } else {
                updateStatus(4, .failed, detail: "未偵測到語音。請對麥克風說話再試一次")
            }
        } catch {
            updateStatus(4, .failed, detail: "錯誤: \(error.localizedDescription)")
        }
        
        showMicTest = false
    }
    
    private func checkClaudeAPI() async {
        updateStatus(5, .testing)
        let start = Date()
        
        // Read API key from Keychain
        guard let apiKey = KeychainManager.shared.retrieve(key: "claude_api_key"),
              !apiKey.isEmpty else {
            updateStatus(5, .failed, detail: "Claude API Key 未設定。請在 App 設定頁面填入")
            return
        }
        
        // Test API with minimal request
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 10
        
        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 20,
            "messages": [["role": "user", "content": "Reply only: OK"]]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let latency = Int(Date().timeIntervalSince(start) * 1000)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    updateStatus(5, .passed, detail: "API 連接正常", latency: latency)
                } else if httpResponse.statusCode == 401 {
                    updateStatus(5, .failed, detail: "API Key 無效 (401)", latency: latency)
                } else {
                    let errorText = String(data: data, encoding: .utf8) ?? "Unknown"
                    updateStatus(5, .failed, detail: "HTTP \(httpResponse.statusCode): \(errorText.prefix(100))", latency: latency)
                }
            }
        } catch {
            let latency = Int(Date().timeIntervalSince(start) * 1000)
            updateStatus(5, .failed, detail: "網路錯誤: \(error.localizedDescription)", latency: latency)
        }
        
        try? await Task.sleep(nanoseconds: 300_000_000)
    }
    
    private func checkNotionAPI() async {
        updateStatus(6, .testing)
        let start = Date()
        
        guard let apiKey = KeychainManager.shared.retrieve(key: "notion_api_key"),
              !apiKey.isEmpty else {
            updateStatus(6, .skipped, detail: "Notion API Key 未設定（選填）")
            return
        }
        
        // Test by reading the MeetingCopilot parent page
        var request = URLRequest(url: URL(string: "https://api.notion.com/v1/pages/320f154a-6472-804f-a226-c3694c1bb319")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
        request.timeoutInterval = 10
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let latency = Int(Date().timeIntervalSince(start) * 1000)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    // Parse page title
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let properties = json["properties"] as? [String: Any],
                       let title = properties["title"] as? [String: Any],
                       let titleArray = title["title"] as? [[String: Any]],
                       let firstTitle = titleArray.first,
                       let plainText = firstTitle["plain_text"] as? String {
                        updateStatus(6, .passed, detail: "頁面: \(plainText)", latency: latency)
                    } else {
                        updateStatus(6, .passed, detail: "Notion 連接正常", latency: latency)
                    }
                } else if httpResponse.statusCode == 401 {
                    updateStatus(6, .failed, detail: "API Key 無效 (401)", latency: latency)
                } else {
                    updateStatus(6, .failed, detail: "HTTP \(httpResponse.statusCode)", latency: latency)
                }
            }
        } catch {
            let latency = Int(Date().timeIntervalSince(start) * 1000)
            updateStatus(6, .failed, detail: "網路錯誤: \(error.localizedDescription)", latency: latency)
        }
        
        try? await Task.sleep(nanoseconds: 300_000_000)
    }
    
    private func checkNotebookLMBridge() async {
        updateStatus(7, .testing)
        let start = Date()
        
        let bridgeURL = KeychainManager.shared.retrieve(key: "notebooklm_bridge_url") ?? "http://localhost:3210"
        
        guard let url = URL(string: "\(bridgeURL)/health") else {
            updateStatus(7, .failed, detail: "Bridge URL 無效")
            return
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let latency = Int(Date().timeIntervalSince(start) * 1000)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                updateStatus(7, .passed, detail: "Bridge 運行中 (\(bridgeURL))", latency: latency)
            } else {
                updateStatus(7, .failed, detail: "Bridge 無回應", latency: latency)
            }
        } catch {
            let latency = Int(Date().timeIntervalSince(start) * 1000)
            updateStatus(7, .skipped, detail: "Bridge 未啟動（選填，\(bridgeURL)\uff09", latency: latency)
        }
    }
    
    // MARK: - Helpers
    
    private func updateStatus(_ index: Int, _ status: CheckStatus, detail: String = "", latency: Int? = nil) {
        guard index < checks.count else { return }
        checks[index].status = status
        if !detail.isEmpty { checks[index].detail = detail }
        if let latency = latency { checks[index].latencyMs = latency }
    }
}

// MARK: - System Check View

struct SystemCheckView: View {
    @StateObject private var vm = SystemCheckViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Check List
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(vm.checks) { check in
                        checkRow(check)
                    }
                    
                    // Mic Test Area
                    if vm.showMicTest {
                        micTestView
                    }
                    
                    // Result Summary
                    if !vm.isRunning && vm.checks.first?.status != .pending {
                        resultSummary
                    }
                }
                .padding(20)
            }
            
            Divider()
            
            // Bottom Bar
            bottomBar
        }
        .frame(minWidth: 600, minHeight: 500)
        .background(Color(.windowBackgroundColor))
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            Image(systemName: "stethoscope")
                .font(.title2)
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("會議前系統檢查")
                    .font(.headline)
                Text("Pre-Meeting System Diagnostics")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if vm.isRunning {
                ProgressView()
                    .scaleEffect(0.8)
                    .padding(.trailing, 8)
                Text("檢查中...")
                    .foregroundColor(.orange)
            } else if vm.allPassed {
                Label("全部通過", systemImage: "checkmark.seal.fill")
                    .foregroundColor(.green)
                    .font(.headline)
            }
        }
        .padding(16)
    }
    
    // MARK: - Check Row
    
    private func checkRow(_ check: CheckItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: check.status.icon)
                .foregroundColor(check.status.color)
                .font(.title3)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(check.name)
                        .fontWeight(.medium)
                    Text(check.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if !check.detail.isEmpty {
                    Text(check.detail)
                        .font(.caption)
                        .foregroundColor(check.status == .failed ? .red : .secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            if let latency = check.latencyMs {
                Text("\(latency)ms")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(check.status == .failed ? Color.red.opacity(0.1) :
                      check.status == .passed ? Color.green.opacity(0.05) :
                      Color(.controlBackgroundColor))
        )
    }
    
    // MARK: - Mic Test View
    
    private var micTestView: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "mic.fill")
                    .foregroundColor(.red)
                Text("🎤 請對麥克風說「測試一二三」")
                    .font(.headline)
            }
            
            // Audio level meter
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(vm.audioLevel > 0.05 ? Color.green : Color.orange)
                        .frame(width: max(0, geo.size.width * CGFloat(min(vm.audioLevel * 10, 1.0))))
                }
            }
            .frame(height: 8)
            
            if !vm.speechTranscript.isEmpty {
                Text("辨識結果: \(vm.speechTranscript)")
                    .font(.body)
                    .foregroundColor(.green)
                    .padding(8)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
            } else {
                Text("等待語音輸入... (5秒)")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Result Summary
    
    private var resultSummary: some View {
        let passed = vm.checks.filter { $0.status == .passed }.count
        let failed = vm.checks.filter { $0.status == .failed }.count
        let skipped = vm.checks.filter { $0.status == .skipped }.count
        let total = vm.checks.count
        
        return VStack(spacing: 8) {
            Divider()
            
            HStack(spacing: 20) {
                Label("\(passed)/\(total) 通過", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                
                if failed > 0 {
                    Label("\(failed) 失敗", systemImage: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
                
                if skipped > 0 {
                    Label("\(skipped) 跳過", systemImage: "minus.circle.fill")
                        .foregroundColor(.yellow)
                }
            }
            .font(.subheadline)
            
            if vm.allPassed {
                Text("✅ 系統就緒，可以開始會議！")
                    .font(.headline)
                    .foregroundColor(.green)
            } else if failed > 0 {
                Text("⚠️ 請修復失敗項目後再次檢查")
                    .font(.headline)
                    .foregroundColor(.orange)
            }
        }
        .padding(.top, 8)
    }
    
    // MARK: - Bottom Bar
    
    private var bottomBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Text("關閉")
            }
            .keyboardShortcut(.escape)
            
            Spacer()
            
            Button(action: { vm.runAllChecks() }) {
                Label(vm.isRunning ? "檢查中..." : "執行系統檢查", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isRunning)
            .keyboardShortcut(.return)
            
            if vm.allPassed {
                Button(action: { dismiss() }) {
                    Label("開始會議", systemImage: "video.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .padding(16)
    }
}

// MARK: - Preview

#Preview {
    SystemCheckView()
        .frame(width: 650, height: 550)
}
