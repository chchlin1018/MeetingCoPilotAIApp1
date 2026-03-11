// TranscriptOnlyView.swift
// TranscriptOnly — feature/transcript-only
// 精簡 UI：語言選擇 + App 選擇 + 開始/停止 + 分色逐字稿 + System Check

import SwiftUI

// MARK: - Supported Languages

enum RecognitionLanguage: String, CaseIterable, Identifiable {
    case zhTW = "zh-TW"
    case enUS = "en-US"
    case enGB = "en-GB"
    case zhCN = "zh-CN"
    case jaJP = "ja-JP"
    
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .zhTW: return "繁體中文 (台灣)"
        case .enUS: return "English (US)"
        case .enGB: return "English (UK)"
        case .zhCN: return "简体中文"
        case .jaJP: return "日本語"
        }
    }
    var locale: Locale { Locale(identifier: rawValue) }
    var audioConfig: AudioCaptureConfiguration {
        AudioCaptureConfiguration(
            sampleRate: 48000.0, channelCount: 1, speechLocale: locale,
            enablePartialResults: true, bufferSize: 1024,
            autoDetectMeetingApp: true, targetApp: nil
        )
    }
}

// MARK: - ViewModel

@Observable
@MainActor
final class TranscriptOnlyViewModel {
    
    // --- UI State ---
    var isRecording = false
    var selectedLanguage: RecognitionLanguage = .zhTW
    var entries: [TranscriptEntry] = []
    
    // Live Partial
    var remotePartial: String = ""
    var localPartial: String = ""
    
    // Audio Health
    var remoteStatus: AudioHealthStatus.StreamStatus = .notStarted
    var localStatus: AudioHealthStatus.StreamStatus = .notStarted
    var startupMessage: String?
    var errorMessage: String?
    var isDualStream = false
    var remoteSegmentCount = 0
    var localSegmentCount = 0
    var detectedApp: String = ""
    
    // ★ App 選擇
    var showAppPicker = false
    var detectedApps: [DetectedAppInfo] = []
    var isScanning = false
    
    // --- Pipeline ---
    private var pipeline: TranscriptPipeline?
    private var updateTask: Task<Void, Never>?
    private var healthTask: Task<Void, Never>?
    
    // MARK: - ★ Step 1: 掃描 App（按下開始會議後的第一步）
    
    func scanAndPrepare() {
        guard !isRecording else { return }
        errorMessage = nil
        isScanning = true
        
        Task {
            let apps = await AppScanner.scanActiveApps()
            self.isScanning = false
            
            if apps.isEmpty {
                self.errorMessage = "找不到支援的會議/通話 App。請先開啟 Zoom/Teams/LINE/FaceTime。"
            } else if apps.count == 1 {
                // 只有一個 App → 直接啟動
                self.startRecording(withApp: apps[0].app)
            } else {
                // 多個 App → 顯示選擇器
                self.detectedApps = apps
                self.showAppPicker = true
            }
        }
    }
    
    // MARK: - ★ Step 2: 啟動錄製（指定 App）
    
    func startRecording(withApp targetApp: MeetingApp) {
        guard !isRecording else { return }
        errorMessage = nil
        startupMessage = nil
        entries.removeAll()
        remotePartial = ""
        localPartial = ""
        detectedApp = ""
        showAppPicker = false
        
        let config = selectedLanguage.audioConfig.withTarget(targetApp)
        let newPipeline = TranscriptPipeline()
        self.pipeline = newPipeline
        
        Task {
            do {
                try await newPipeline.start(config: config)
                let health = await newPipeline.audioHealth
                self.startupMessage = health.startupMessage
                self.isDualStream = await newPipeline.hasDualStream
                self.detectedApp = health.detectedAppName ?? ""
                self.isRecording = true
                self.startUpdateConsumer(pipeline: newPipeline)
                self.startHealthMonitor(pipeline: newPipeline)
            } catch {
                self.errorMessage = error.localizedDescription
                self.pipeline = nil
            }
        }
    }
    
    // MARK: - Stop
    
    func stopRecording() {
        guard isRecording else { return }
        updateTask?.cancel(); healthTask?.cancel()
        updateTask = nil; healthTask = nil
        Task { await pipeline?.stop(); pipeline = nil }
        isRecording = false
        remoteStatus = .notStarted; localStatus = .notStarted
        remotePartial = ""; localPartial = ""; detectedApp = ""
    }
    
    // MARK: - Update Consumer
    
    private func startUpdateConsumer(pipeline: TranscriptPipeline) {
        updateTask = Task { [weak self] in
            let updates = await pipeline.updates!
            for await update in updates {
                guard !Task.isCancelled, let self = self else { break }
                switch update.speaker {
                case .remote:
                    self.remotePartial = update.segment.isFinal ? "" : String(update.segment.text.suffix(80))
                case .local:
                    self.localPartial = update.segment.isFinal ? "" : String(update.segment.text.suffix(80))
                }
                if update.entry.isFinal && update.entry.text.count > 3 {
                    self.entries.append(update.entry)
                    if self.entries.count > 500 { self.entries.removeFirst(self.entries.count - 500) }
                }
            }
        }
    }
    
    // MARK: - Health Monitor
    
    private func startHealthMonitor(pipeline: TranscriptPipeline) {
        healthTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled, let self = self else { break }
                let health = await pipeline.audioHealth
                let now = Date()
                self.remoteStatus = health.remoteStatus(now: now)
                self.localStatus = health.localStatus(now: now)
                self.remoteSegmentCount = health.remoteSegmentCount
                self.localSegmentCount = health.localSegmentCount
            }
        }
    }
    
    // MARK: - Export
    
    func exportTranscript() -> String {
        let header = """
        # Transcript Export
        # Date: \(Date().formatted())
        # Language: \(selectedLanguage.displayName)
        # Dual Stream: \(isDualStream)
        # Detected App: \(detectedApp)
        # Entries: \(entries.count)
        
        """
        let body = entries.map { e in
            "\(e.timestamp.formatted(date: .omitted, time: .standard)) [\(e.speakerLabel)] \(e.text)"
        }.joined(separator: "\n")
        return header + body
    }
}

// MARK: - Main View

struct TranscriptOnlyView: View {
    @State private var vm = TranscriptOnlyViewModel()
    @State private var autoScroll = true
    @State private var showSystemCheck = false
    
    var body: some View {
        VStack(spacing: 0) {
            controlBar
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.ultraThinMaterial)
            Divider()
            
            if let msg = vm.startupMessage {
                HStack {
                    Text(msg).font(.system(size: 12))
                        .foregroundStyle(msg.hasPrefix("✅") ? .green : msg.hasPrefix("❌") ? .red : .orange)
                    Spacer()
                }.padding(.horizontal, 16).padding(.vertical, 6)
                .background(Color.black.opacity(0.3))
            }
            
            transcriptScrollView
            Divider()
            
            statusBar
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(.ultraThinMaterial)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showSystemCheck) {
            SystemCheckSheet(language: vm.selectedLanguage)
        }
        .sheet(isPresented: $vm.showAppPicker) {
            appPickerSheet
        }
    }
    
    // MARK: - ★ App Picker Sheet
    
    private var appPickerSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "app.connected.to.app.below.fill")
                    .font(.title2).foregroundStyle(.cyan)
                Text("選擇音訊來源")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                Button("取消") { vm.showAppPicker = false }
                    .keyboardShortcut(.escape)
            }.padding()
            
            Divider()
            
            Text("偵測到 \(vm.detectedApps.count) 個應用程式，請選擇要擷取音訊的來源：")
                .font(.system(size: 13)).foregroundStyle(.secondary)
                .padding(.horizontal).padding(.top, 12)
            
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(vm.detectedApps) { info in
                        Button {
                            vm.startRecording(withApp: info.app)
                        } label: {
                            HStack(spacing: 12) {
                                // App Icon placeholder
                                Image(systemName: appIcon(for: info.app))
                                    .font(.system(size: 20))
                                    .foregroundStyle(.cyan)
                                    .frame(width: 32)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(info.displayName)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    Text("\(info.tierLabel) • \(info.app.bundleIdentifier)")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                // 優先級 badge
                                if info.priority == 0 {
                                    Text("推薦")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(.green).cornerRadius(4)
                                }
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                }.padding()
            }
            
            Divider()
            
            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text("選擇後將開始擷取該 App 的音訊 + 麥克風")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
            }.padding()
        }
        .frame(width: 450, height: 380)
    }
    
    private func appIcon(for app: MeetingApp) -> String {
        switch app {
        case .zoom: return "video.fill"
        case .microsoftTeams: return "person.3.fill"
        case .googleMeet: return "globe"
        case .webex: return "video.badge.checkmark"
        case .slack: return "number"
        case .discord: return "gamecontroller.fill"
        case .line: return "message.fill"
        case .whatsapp, .whatsappNative: return "phone.fill"
        case .telegram: return "paperplane.fill"
        case .facetime: return "video.circle.fill"
        }
    }
    
    // MARK: - Control Bar
    
    private var controlBar: some View {
        HStack(spacing: 16) {
            Text("TranscriptOnly")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
            
            Divider().frame(height: 20)
            
            Picker("語言", selection: $vm.selectedLanguage) {
                ForEach(RecognitionLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .pickerStyle(.menu).frame(width: 200)
            .disabled(vm.isRecording)
            
            Button {
                showSystemCheck = true
            } label: {
                Image(systemName: "stethoscope").font(.system(size: 14))
            }
            .buttonStyle(.borderless)
            .disabled(vm.isRecording)
            .help("系統檢查")
            
            Spacer()
            
            Text("\(vm.entries.count) 條")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
            
            Button { exportToFile() } label: {
                Image(systemName: "square.and.arrow.up").font(.system(size: 14))
            }.buttonStyle(.borderless).disabled(vm.entries.isEmpty).help("匯出 TXT")
            
            Button { vm.entries.removeAll() } label: {
                Image(systemName: "trash").font(.system(size: 14))
            }.buttonStyle(.borderless).disabled(vm.entries.isEmpty || vm.isRecording).help("清除")
            
            // ★ 開始/停止按鈕
            Button {
                if vm.isRecording {
                    vm.stopRecording()
                } else {
                    vm.scanAndPrepare()  // ★ 先掃描，再決定是否顯示選擇器
                }
            } label: {
                HStack(spacing: 6) {
                    if vm.isScanning {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: vm.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                            .font(.title2)
                    }
                    Text(vm.isScanning ? "掃描中..." : vm.isRecording ? "停止" : "開始會議")
                        .fontWeight(.medium)
                }.padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(vm.isRecording ? .red : .green)
            .disabled(vm.isScanning)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }
    
    // MARK: - Transcript Scroll View
    
    private var transcriptScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(vm.entries) { entry in
                        transcriptRow(entry).id(entry.id)
                    }
                    if vm.isRecording && !vm.remotePartial.isEmpty {
                        partialRow(text: vm.remotePartial, speaker: .remote).id("partial-remote")
                    }
                    if vm.isRecording && !vm.localPartial.isEmpty {
                        partialRow(text: vm.localPartial, speaker: .local).id("partial-local")
                    }
                    if vm.entries.isEmpty && !vm.isRecording {
                        VStack(spacing: 12) {
                            Image(systemName: "waveform.badge.mic")
                                .font(.system(size: 40)).foregroundStyle(.tertiary)
                            Text("選擇語言 → 開啟 Zoom/Teams/LINE → 按「開始會議」")
                                .font(.system(size: 14)).foregroundStyle(.secondary)
                            Text("多個 App 時會讓你手動選擇音訊來源")
                                .font(.system(size: 12)).foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 100)
                    }
                }.padding(.vertical, 12)
            }
            .onChange(of: vm.entries.count) { _, _ in
                if autoScroll, let last = vm.entries.last {
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }
    
    private func transcriptRow(_ entry: TranscriptEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
            Text(entry.speakerLabel)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(speakerColor(entry.speaker)).frame(width: 32)
            Text(entry.text).font(.system(size: 16))
                .foregroundStyle(speakerColor(entry.speaker)).textSelection(.enabled)
        }.padding(.horizontal, 16).padding(.vertical, 2)
    }
    
    private func partialRow(text: String, speaker: SpeakerSource) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "waveform").font(.system(size: 11)).foregroundStyle(.purple)
                .frame(width: 70, alignment: .trailing)
            Text(speaker == .remote ? "對方" : "我方")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.purple.opacity(0.6)).frame(width: 32)
            Text(text).font(.system(size: 15)).foregroundStyle(.purple.opacity(0.7)).italic()
        }.padding(.horizontal, 16).padding(.vertical, 2)
    }
    
    // MARK: - Status Bar
    
    private var statusBar: some View {
        HStack(spacing: 16) {
            if vm.isRecording {
                HStack(spacing: 4) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text("REC").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(.red)
                }
            }
            if vm.isDualStream {
                Text("DUAL").font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.green.opacity(0.2)).cornerRadius(4)
            }
            if !vm.detectedApp.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "app.connected.to.app.below.fill").font(.system(size: 10))
                    Text(vm.detectedApp).font(.system(size: 11, weight: .semibold, design: .monospaced))
                }.foregroundStyle(.cyan)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.cyan.opacity(0.15)).cornerRadius(4)
            }
            Divider().frame(height: 16)
            audioStatusBadge("遠端(對方)", status: vm.remoteStatus, count: vm.remoteSegmentCount)
            audioStatusBadge("本地(我方)", status: vm.localStatus, count: vm.localSegmentCount)
            Spacer()
            Toggle("自動捲動", isOn: $autoScroll).toggleStyle(.switch).controlSize(.mini).font(.system(size: 11))
            if let error = vm.errorMessage {
                Text(error).font(.system(size: 11)).foregroundStyle(.red).lineLimit(1)
            }
        }
    }
    
    private func speakerColor(_ speaker: SpeakerSource) -> Color {
        speaker == .remote ? .cyan : .yellow
    }
    
    private func audioStatusBadge(_ label: String, status: AudioHealthStatus.StreamStatus, count: Int) -> some View {
        HStack(spacing: 4) {
            Circle().fill(statusColor(status)).frame(width: 6, height: 6)
            Text("\(label): \(status.rawValue)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            if count > 0 { Text("(\(count))").font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary) }
        }
    }
    
    private func statusColor(_ status: AudioHealthStatus.StreamStatus) -> Color {
        switch status {
        case .active: return .green; case .idle: return .orange
        case .disconnected: return .red; case .notStarted: return .gray
        }
    }
    
    private func exportToFile() {
        let content = vm.exportTranscript()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        let dateStr = Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")
        panel.nameFieldStringValue = "transcript_\(dateStr).txt"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? content.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}

#Preview {
    TranscriptOnlyView().frame(width: 900, height: 650)
}
