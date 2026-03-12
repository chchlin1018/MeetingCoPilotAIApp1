// UsageExample.swift
// MeetingCopilot v4.3.1 — SwiftUI Main View
// Updated: PostMeetingLogger integration + setMeetingInfo

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Main View

struct MeetingTeleprompterView: View {

    @State private var coordinator: MeetingAICoordinator
    @State private var systemMonitor = SystemMonitor()
    @State private var isSessionActive = false
    @State private var showPrepView = true
    @State private var manualQuestion = ""
    @State private var meetingTitle = "Meeting"
    @State private var activeSpeechLanguage = "zh-TW"

    @State private var showPostMeetingSave = false
    @State private var savedTranscript = ""
    @State private var savedCards: [AICard] = []
    @State private var savedStats = SessionStats()
    @State private var savedTPStats = TPStats(total: 0, completed: 0, mustTotal: 0, mustCompleted: 0, shouldTotal: 0, shouldCompleted: 0)
    @State private var savedTalkingPoints: [TalkingPoint] = []
    @State private var meetingStartTime: Date?
    @State private var reportFormat: ReportFormat = .markdown
    @State private var aiSummary: [String] = []
    @State private var actionItems: [ActionItem] = []
    @State private var isGeneratingSummary = false
    @State private var notionExportStatus: String = ""

    // ★ 啟動通知
    @State private var showStartupBanner = false
    @State private var startupBannerMessage = ""
    @State private var startupBannerIsError = false

    enum ReportFormat: String, CaseIterable {
        case markdown = "Markdown"
        case txt = "TXT"
    }

    private let reportService = PostMeetingReportService()

    init() {
        let apiKey = KeychainManager.claudeAPIKey ?? "NOT_CONFIGURED"
        let nlmConfig = KeychainManager.notebookLMConfig
        let emptyContext = MeetingContext(goals: [], preAnalysisCache: "",
            relevantQA: [], recentTranscript: "", attendeeInfo: "", meetingType: "")
        _coordinator = State(initialValue: MeetingAICoordinator(
            claudeAPIKey: apiKey, notebookLMConfig: nlmConfig, meetingContext: emptyContext
        ))
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                headerBar
                // ★ 啟動通知橫幅
                if showStartupBanner {
                    startupBannerView
                }
                HStack(spacing: 0) {
                    transcriptPanel.frame(width: 320)
                    Divider()
                    teleprompterPanel
                    Divider()
                    rightSidebar.frame(width: 300)
                }
                manualQueryBar
            }
            .background(Color(hex: "0A0A0F"))
            .preferredColorScheme(.dark)

            if showPrepView {
                Color.black.opacity(0.7).ignoresSafeArea()
                MeetingPrepView { result in
                    Task { await loadPrepAndStart(result) }
                }
                .frame(maxWidth: 900, maxHeight: 700)
                .background(.ultraThinMaterial)
                .cornerRadius(16).shadow(radius: 20)
            }

            if showPostMeetingSave {
                Color.black.opacity(0.7).ignoresSafeArea()
                postMeetingReportView
                    .frame(width: 600, height: 580)
                    .background(.ultraThinMaterial)
                    .cornerRadius(16).shadow(radius: 20)
            }
        }
        .onAppear { systemMonitor.start() }
        .onDisappear { systemMonitor.stop() }
    }

    // ★ 啟動通知橫幅
    private var startupBannerView: some View {
        HStack(spacing: 8) {
            Image(systemName: startupBannerIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(startupBannerIsError ? .orange : .green)
            Text(startupBannerMessage)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.9))
            Spacer()
            Button(action: { withAnimation { showStartupBanner = false } }) {
                Image(systemName: "xmark").font(.system(size: 9)).foregroundColor(.gray)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .background(startupBannerIsError ? Color.orange.opacity(0.15) : Color.green.opacity(0.1))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // ★ 修復：使用 result.selectedApp 建立 config + setMeetingInfo
    private func loadPrepAndStart(_ result: MeetingPrepResult) async {
        meetingTitle = result.context.goals.first ?? "Meeting"
        activeSpeechLanguage = result.speechLocale.identifier

        // ★ 傳遞會議標題和語言給 PostMeetingLogger
        coordinator.setMeetingInfo(title: meetingTitle, language: activeSpeechLanguage)

        await coordinator.updateContext(result.context)
        await coordinator.loadKnowledgeBase(result.qaItems)
        await coordinator.loadTalkingPoints(result.talkingPoints, meetingDurationMinutes: result.durationMinutes)
        let config = AudioCaptureConfiguration(
            sampleRate: 48000.0, channelCount: 1,
            speechLocale: result.speechLocale,
            enablePartialResults: true, bufferSize: 1024,
            autoDetectMeetingApp: result.selectedApp == nil,
            targetApp: result.selectedApp
        )
        await coordinator.startMeeting(config: config)
        isSessionActive = true
        showPrepView = false
        meetingStartTime = Date()

        // ★ 顯示啟動通知
        if let msg = coordinator.audioHealth.startupMessage {
            startupBannerMessage = msg
            startupBannerIsError = msg.contains("⚠️") || msg.contains("❌")
            withAnimation(.easeInOut(duration: 0.3)) { showStartupBanner = true }
            if !startupBannerIsError {
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    withAnimation { showStartupBanner = false }
                }
            }
        }
    }

    private func stopMeeting() async {
        withAnimation { showStartupBanner = false }
        savedTranscript = coordinator.fullTranscript
        savedCards = coordinator.cards
        savedTalkingPoints = coordinator.talkingPoints
        savedTPStats = coordinator.tpStats
        await coordinator.stopMeeting()
        savedStats = coordinator.stats
        isSessionActive = false
        showPostMeetingSave = true

        isGeneratingSummary = true
        async let summaryTask = reportService.generateSummary(
            transcript: savedTranscript, title: meetingTitle, tpStats: savedTPStats)
        async let actionTask = reportService.extractActionItems(from: savedTranscript)
        aiSummary = await summaryTask
        actionItems = await actionTask
        isGeneratingSummary = false
    }

    // MARK: 會後報告 UI

    private var postMeetingReportView: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24)).foregroundColor(.green)
                Text("會議結束").font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                Spacer()
                Text(savedStats.summary)
                    .font(.system(size: 10, design: .monospaced)).foregroundColor(.gray)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(Color(hex: "111118"))

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 16) {
                        reportMetric("TP 完成", "\(savedTPStats.completed)/\(savedTPStats.total)",
                                     savedTPStats.mustCompletionRate >= 1.0 ? .green : .yellow)
                        reportMetric("MUST", "\(savedTPStats.mustCompleted)/\(savedTPStats.mustTotal)",
                                     savedTPStats.mustCompletionRate >= 1.0 ? .green : .red)
                        reportMetric("AI 卡片", "\(savedCards.count)", .purple)
                        reportMetric("成本", "$\(String(format: "%.2f", savedStats.estimatedClaudeCost))", .orange)
                    }.frame(maxWidth: .infinity)

                    Divider().background(Color.gray.opacity(0.3))

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "brain.head.profile").foregroundColor(.purple).font(.system(size: 12))
                            Text("AI 會議摘要").font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                            Spacer()
                            if isGeneratingSummary {
                                ProgressView().scaleEffect(0.6)
                                Text("Claude 生成中...").font(.system(size: 10)).foregroundColor(.purple)
                            }
                        }
                        if aiSummary.isEmpty && !isGeneratingSummary {
                            Text("（無摘要）").font(.system(size: 11)).foregroundColor(.gray.opacity(0.4))
                        }
                        ForEach(Array(aiSummary.enumerated()), id: \.offset) { i, point in
                            HStack(alignment: .top, spacing: 6) {
                                Text("\(i + 1).").font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.purple.opacity(0.7))
                                Text(point).font(.system(size: 12)).foregroundColor(.white.opacity(0.9))
                            }
                        }
                    }

                    Divider().background(Color.gray.opacity(0.3))

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "checklist").foregroundColor(.green).font(.system(size: 12))
                            Text("Action Items").font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                            Spacer()
                            Text("\(actionItems.count) 項").font(.system(size: 10, design: .monospaced)).foregroundColor(.gray)
                        }
                        if actionItems.isEmpty && !isGeneratingSummary {
                            Text("（未偵測到行動項目）").font(.system(size: 11)).foregroundColor(.gray.opacity(0.4))
                        }
                        ForEach(actionItems) { item in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "square").font(.system(size: 10)).foregroundColor(.green.opacity(0.5))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.content).font(.system(size: 11)).foregroundColor(.white.opacity(0.85)).lineLimit(2)
                                    HStack(spacing: 8) {
                                        if let owner = item.owner {
                                            Text(owner).font(.system(size: 9, design: .monospaced)).foregroundColor(.cyan.opacity(0.7))
                                        }
                                        if let deadline = item.deadline {
                                            Text(deadline).font(.system(size: 9, design: .monospaced)).foregroundColor(.orange.opacity(0.7))
                                        }
                                    }
                                }
                            }.padding(.vertical, 2)
                        }
                    }
                }.padding(20)
            }

            Divider().background(Color.gray.opacity(0.3))

            HStack(spacing: 10) {
                Picker("", selection: $reportFormat) {
                    ForEach(ReportFormat.allCases, id: \.self) { f in Text(f.rawValue).tag(f) }
                }.pickerStyle(.segmented).frame(width: 160)
                Spacer()
                if !notionExportStatus.isEmpty {
                    Text(notionExportStatus).font(.system(size: 10))
                        .foregroundColor(notionExportStatus.contains("✅") ? .green : .orange)
                }
                Button("跳過") { showPostMeetingSave = false; resetReportState() }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundColor(.gray)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Color.gray.opacity(0.2)).cornerRadius(6)
                if KeychainManager.hasNotionAPIKey {
                    Button(action: { Task { await exportToNotion() } }) {
                        HStack(spacing: 4) { Image(systemName: "square.and.arrow.up"); Text("Notion") }
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Color.teal.opacity(0.8)).cornerRadius(6)
                    }.buttonStyle(.plain).disabled(isGeneratingSummary)
                }
                Button(action: saveReport) {
                    HStack(spacing: 4) { Image(systemName: "square.and.arrow.down"); Text("儲存 \(reportFormat.rawValue)") }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Color.green.opacity(0.8)).cornerRadius(6)
                }.buttonStyle(.plain).disabled(isGeneratingSummary)
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(Color(hex: "111118"))
        }
    }

    private func reportMetric(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 9)).foregroundColor(.gray)
            Text(value).font(.system(size: 16, weight: .bold, design: .monospaced)).foregroundColor(color)
        }
    }

    private func buildReport() -> MeetingReport {
        let duration = savedStats.sessionDuration.map { "\(Int($0 / 60)) 分鐘" } ?? "N/A"
        return MeetingReport(title: meetingTitle, startTime: meetingStartTime, endTime: Date(),
            duration: duration, language: activeSpeechLanguage, summary: aiSummary,
            actionItems: actionItems, transcript: savedTranscript,
            talkingPoints: savedTalkingPoints, tpStats: savedTPStats,
            cards: savedCards, stats: savedStats)
    }

    private func saveReport() {
        let report = buildReport()
        Task {
            let content: String; let ext: String; let contentType: UTType
            switch reportFormat {
            case .markdown:
                content = await reportService.buildMarkdown(report: report); ext = "md"
                contentType = UTType(filenameExtension: "md") ?? .plainText
            case .txt:
                content = await reportService.buildTXT(report: report); ext = "txt"
                contentType = .plainText
            }
            let panel = NSSavePanel(); panel.title = "儲存會議報告"
            let dateStr = formatDate(meetingStartTime ?? Date())
            let safeName = meetingTitle.replacingOccurrences(of: " ", with: "-")
            panel.nameFieldStringValue = "\(dateStr)_\(safeName).\(ext)"
            panel.allowedContentTypes = [contentType]; panel.canCreateDirectories = true
            if panel.runModal() == .OK, let url = panel.url {
                do { try content.write(to: url, atomically: true, encoding: .utf8)
                    showPostMeetingSave = false; resetReportState()
                } catch { print("❌ 儲存失敗: \(error)") }
            }
        }
    }

    private func exportToNotion() async {
        notionExportStatus = "匯出中..."
        let result = await reportService.exportToNotion(report: buildReport())
        notionExportStatus = result.success ? "✅ 已匯出" : "⚠️ 需要設定 Notion parent page"
        if result.success {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { notionExportStatus = "" }
        }
    }

    private func resetReportState() { aiSummary = []; actionItems = []; notionExportStatus = "" }
    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
    }

    // MARK: ★ Header Bar（含音訊狀態）

    private var headerBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Circle()
                    .fill(coordinator.captureState.isActive ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                if let engineType = coordinator.activeEngineType {
                    Text(engineType.rawValue)
                        .font(.system(size: 11, design: .monospaced)).foregroundColor(.gray)
                }
            }
            if coordinator.hasDualStream {
                HStack(spacing: 3) {
                    Image(systemName: "person.2.wave.2").font(.system(size: 9))
                    Text("雙串流").font(.system(size: 10))
                }.foregroundColor(.green)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color.green.opacity(0.1)).cornerRadius(4)
            }

            // ★ 偵測到的 App 名稱
            if !coordinator.detectedAppName.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "app.connected.to.app.below.fill").font(.system(size: 9))
                    Text(coordinator.detectedAppName).font(.system(size: 10, weight: .semibold, design: .monospaced))
                }.foregroundColor(.cyan)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color.cyan.opacity(0.1)).cornerRadius(4)
            }

            if isSessionActive {
                Text(activeSpeechLanguage)
                    .font(.system(size: 10, design: .monospaced)).foregroundColor(.blue)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1)).cornerRadius(4)
            }

            // ★ 音訊串流狀態 badge
            if isSessionActive { audioStreamBadge }

            notebookLMStatusBadge
            if !KeychainManager.hasClaudeAPIKey {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange).font(.system(size: 10))
                    Text("API Key 未設定").font(.system(size: 10)).foregroundColor(.orange)
                }
            }
            Spacer()
            Text(meetingTitle).font(.system(size: 13, weight: .semibold)).foregroundColor(.white).lineLimit(1)
            Spacer()
            HStack(spacing: 10) {
                statBadge("🔵", "\(coordinator.stats.localMatches)", .cyan)
                statBadge("📚", "\(coordinator.stats.notebookLMQueries)", .teal)
                statBadge("🟣", "\(coordinator.stats.claudeQueries)", .purple)
                statBadge("🟠", "\(coordinator.stats.strategyAnalyses)", .orange)
                Text("$\(String(format: "%.2f", coordinator.stats.estimatedClaudeCost))")
                    .font(.system(size: 11, design: .monospaced)).foregroundColor(.orange)
            }
            tpCompletionBadge
            if isSessionActive {
                Button(action: { Task { await stopMeeting() } }) {
                    Text("End Meeting").font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 16).padding(.vertical, 6)
                        .background(Color.red.opacity(0.8)).cornerRadius(6)
                }.buttonStyle(.plain)
            } else {
                Button("準備會議") { showPrepView = true }
                .buttonStyle(.plain).font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 16).padding(.vertical, 6)
                .background(Color.purple.opacity(0.8)).cornerRadius(6)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color(hex: "111118"))
    }

    // MARK: ★ Audio Stream Badge

    private var audioStreamBadge: some View {
        let health = coordinator.audioHealth
        let rStatus = health.remoteStatus()
        let lStatus = health.localStatus()

        return HStack(spacing: 6) {
            HStack(spacing: 2) {
                streamDot(rStatus)
                Text("對方").font(.system(size: 9)).foregroundColor(streamColor(rStatus))
                if health.remoteSegmentCount > 0 {
                    Text("\(health.remoteSegmentCount)").font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.gray.opacity(0.4))
                }
            }
            HStack(spacing: 2) {
                streamDot(lStatus)
                Text("我方").font(.system(size: 9)).foregroundColor(streamColor(lStatus))
                if health.localSegmentCount > 0 {
                    Text("\(health.localSegmentCount)").font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.gray.opacity(0.4))
                }
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(streamBadgeBackground(rStatus, lStatus))
        .cornerRadius(4)
    }

    @ViewBuilder
    private func streamDot(_ status: AudioHealthStatus.StreamStatus) -> some View {
        switch status {
        case .active: Circle().fill(Color.green).frame(width: 5, height: 5)
        case .idle: Circle().fill(Color.yellow).frame(width: 5, height: 5)
        case .disconnected: Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 7)).foregroundColor(.red)
        case .notStarted: Circle().fill(Color.gray.opacity(0.4)).frame(width: 5, height: 5)
        }
    }

    private func streamColor(_ status: AudioHealthStatus.StreamStatus) -> Color {
        switch status { case .active: return .green; case .idle: return .yellow; case .disconnected: return .red; case .notStarted: return .gray }
    }

    private func streamBadgeBackground(_ r: AudioHealthStatus.StreamStatus, _ l: AudioHealthStatus.StreamStatus) -> Color {
        if r == .disconnected || l == .disconnected { return Color.red.opacity(0.15) }
        if r == .idle || l == .idle { return Color.yellow.opacity(0.1) }
        return Color.green.opacity(0.08)
    }

    private var notebookLMStatusBadge: some View {
        HStack(spacing: 4) {
            Circle().fill(coordinator.isNotebookLMAvailable ? Color.teal : Color.gray.opacity(0.5)).frame(width: 6, height: 6)
            if coordinator.isNotebookLMQuerying {
                ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                Text("RAG...").font(.system(size: 10)).foregroundColor(.teal)
            } else {
                Text("NLM").font(.system(size: 10, design: .monospaced))
                    .foregroundColor(coordinator.isNotebookLMAvailable ? .teal : .gray.opacity(0.5))
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Color.teal.opacity(coordinator.isNotebookLMAvailable ? 0.1 : 0))
        .cornerRadius(4)
    }

    private func statBadge(_ emoji: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 2) { Text(emoji).font(.system(size: 10)); Text(value).font(.system(size: 11, design: .monospaced)).foregroundColor(color) }
    }

    private var tpCompletionBadge: some View {
        let s = coordinator.tpStats
        let color: Color = s.mustCompletionRate >= 1.0 ? .green : s.mustCompletionRate >= 0.5 ? .yellow : .red
        return HStack(spacing: 4) {
            Text("TP").font(.system(size: 10, weight: .bold)).foregroundColor(color)
            Text("\(s.completed)/\(s.total)").font(.system(size: 11, design: .monospaced)).foregroundColor(color)
        }.padding(.horizontal, 6).padding(.vertical, 2).background(color.opacity(0.1)).cornerRadius(4)
    }

    // MARK: ★ Transcript Panel

    private var transcriptPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LIVE TRANSCRIPT").font(.system(size: 11, weight: .bold)).foregroundColor(.gray)
                Spacer()
                if coordinator.hasDualStream {
                    HStack(spacing: 4) {
                        Circle().fill(Color.cyan).frame(width: 5, height: 5)
                        Text("對方").font(.system(size: 9)).foregroundColor(.cyan.opacity(0.6))
                        Circle().fill(Color.yellow).frame(width: 5, height: 5)
                        Text("我方").font(.system(size: 9)).foregroundColor(.yellow.opacity(0.6))
                    }
                }
            }.padding(.horizontal, 12).padding(.top, 8)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        if coordinator.transcriptEntries.isEmpty && !isSessionActive {
                            Text("等待會議音訊...").font(.system(size: 16)).foregroundColor(.gray.opacity(0.4))
                                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        } else if coordinator.transcriptEntries.isEmpty && isSessionActive {
                            Text("正在聆聽...").font(.system(size: 16)).foregroundColor(.gray.opacity(0.4))
                                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(coordinator.transcriptEntries) { entry in
                                TranscriptEntryRow(entry: entry, isDualStream: coordinator.hasDualStream).id(entry.id)
                            }
                        }.padding(.horizontal, 12)
                        if isSessionActive && !coordinator.recentTranscript.isEmpty {
                            let isLocal = coordinator.recentTranscript.contains("[我方]")
                            let partialColor: Color = isLocal ? .yellow : .cyan
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 12))
                                    .foregroundColor(partialColor.opacity(0.6))
                                Text(coordinator.recentTranscript)
                                    .font(.system(size: 15, design: .monospaced))
                                    .foregroundColor(partialColor.opacity(0.6))
                                    .lineLimit(3)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .id("live-partial")
                        }
                    }
                }
                .onChange(of: coordinator.transcriptEntries.count) { _, _ in
                    if let last = coordinator.transcriptEntries.last {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onChange(of: coordinator.recentTranscript) { _, _ in
                    withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo("live-partial", anchor: .bottom) }
                }
            }
        }.background(Color(hex: "0D0D14"))
    }

    // MARK: ★ Teleprompter Panel

    private var teleprompterPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("AI TELEPROMPTER").font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                Spacer()
                pipelineStatusIndicator
            }.padding(.horizontal, 12).padding(.vertical, 8)
            ScrollView {
                if coordinator.cards.isEmpty && !isSessionActive {
                    VStack(spacing: 12) {
                        Image(systemName: "sparkles").font(.system(size: 32)).foregroundColor(.purple.opacity(0.3))
                        Text("點擊「準備會議」開始").font(.system(size: 14)).foregroundColor(.gray)
                    }.frame(maxWidth: .infinity).padding(.top, 100)
                } else if coordinator.cards.isEmpty && isSessionActive {
                    VStack(alignment: .leading, spacing: 16) {
                        if let firstMust = coordinator.talkingPoints.first(where: { $0.priority == .must && $0.status == .pending }) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Text("MUST").font(.system(size: 11, weight: .heavy, design: .monospaced))
                                        .foregroundColor(.red)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.red.opacity(0.15)).cornerRadius(4)
                                    Text("下一個重點").font(.system(size: 12)).foregroundColor(.gray)
                                }
                                Text(firstMust.content)
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(4)
                                if let data = firstMust.supportingData {
                                    Text(data)
                                        .font(.system(size: 14))
                                        .foregroundColor(.gray.opacity(0.7))
                                        .lineLimit(3)
                                }
                            }
                            .padding(16)
                            .background(Color.red.opacity(0.06))
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.2), lineWidth: 1))
                        }
                        let pendingTPs = coordinator.talkingPoints.filter { $0.status == .pending }
                        if pendingTPs.count > 1 {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("待講重點").font(.system(size: 11, weight: .bold)).foregroundColor(.gray)
                                ForEach(pendingTPs.prefix(5)) { tp in
                                    HStack(spacing: 6) {
                                        Text(tp.priority.rawValue)
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                            .foregroundColor(tp.priority == .must ? .red : tp.priority == .should ? .yellow : .gray)
                                        Text(tp.content)
                                            .font(.system(size: 14))
                                            .foregroundColor(.white.opacity(0.8))
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .padding(12)
                            .background(Color.white.opacity(0.03))
                            .cornerRadius(8)
                        }
                        Text("等待對方提問，AI 將即時回應...")
                            .font(.system(size: 13))
                            .foregroundColor(.gray.opacity(0.4))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }.padding(16)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(coordinator.cards) { card in AICardView(card: card) }
                    }.padding(12)
                }
            }
        }.background(Color(hex: "0D0D14"))
    }

    private var pipelineStatusIndicator: some View {
        HStack(spacing: 8) {
            if coordinator.isNotebookLMQuerying {
                HStack(spacing: 4) { ProgressView().scaleEffect(0.5); Text("RAG 搜尋中...").font(.system(size: 11)).foregroundColor(.teal) }
            }
            if coordinator.isClaudeStreaming {
                HStack(spacing: 4) { ProgressView().scaleEffect(0.5); Text("Claude 思考中...").font(.system(size: 11)).foregroundColor(.purple) }
            }
        }
    }

    private var rightSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                talkingPointsPanel
                Divider().background(Color.gray.opacity(0.3))
                goalsPanel
                Divider().background(Color.gray.opacity(0.3))
                statsPanel
                Divider().background(Color.gray.opacity(0.3))
                systemHealthPanel
            }.padding(12)
        }.background(Color(hex: "0D0D14"))
    }

    private var talkingPointsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TALKING POINTS").font(.system(size: 11, weight: .bold)).foregroundColor(.gray)
                Spacer()
                Text(coordinator.tpStats.summary).font(.system(size: 10, design: .monospaced)).foregroundColor(.gray)
            }
            if coordinator.talkingPoints.isEmpty { Text("尚未載入").font(.system(size: 11)).foregroundColor(.gray.opacity(0.4)) }
            ForEach(coordinator.talkingPoints) { tp in
                TalkingPointRow(talkingPoint: tp,
                    onComplete: { Task { await coordinator.markTPCompleted(tp.id) } },
                    onSkip: { Task { await coordinator.markTPSkipped(tp.id) } })
            }
        }
    }

    private var goalsPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("GOALS").font(.system(size: 11, weight: .bold)).foregroundColor(.gray)
            if coordinator.talkingPoints.isEmpty { Text("尚未設定").font(.system(size: 11)).foregroundColor(.gray.opacity(0.4)) }
        }
    }

    private var statsPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SESSION STATS").font(.system(size: 11, weight: .bold)).foregroundColor(.gray)
            Group {
                statRow("Q&A Loaded", "\(coordinator.stats.qaItemsLoaded)")
                statRow("🔵 Local Match", "\(coordinator.stats.localMatches)")
                statRow("📚 RAG Queries", "\(coordinator.stats.notebookLMQueries)")
                statRow("🟣 Claude Queries", "\(coordinator.stats.claudeQueries)")
                statRow("🟠 Strategy", "\(coordinator.stats.strategyAnalyses)")
                statRow("Avg Latency", "\(String(format: "%.0f", coordinator.stats.averageClaudeLatencyMs))ms")
                statRow("AI Cost", "$\(String(format: "%.2f", coordinator.stats.estimatedClaudeCost))")
            }
            HStack { Text("雙串流").font(.system(size: 11)).foregroundColor(.gray); Spacer()
                HStack(spacing: 4) {
                    Circle().fill(coordinator.hasDualStream ? Color.green : Color.gray.opacity(0.4)).frame(width: 6, height: 6)
                    Text(coordinator.hasDualStream ? "Active" : "Single").font(.system(size: 11, design: .monospaced))
                        .foregroundColor(coordinator.hasDualStream ? .green : .gray)
                }
            }
            HStack { Text("語言").font(.system(size: 11)).foregroundColor(.gray); Spacer()
                Text(activeSpeechLanguage).font(.system(size: 11, design: .monospaced)).foregroundColor(.blue) }
            HStack { Text("API Key").font(.system(size: 11)).foregroundColor(.gray); Spacer()
                HStack(spacing: 4) {
                    Circle().fill(KeychainManager.hasClaudeAPIKey ? Color.green : Color.red.opacity(0.6)).frame(width: 6, height: 6)
                    Text(KeychainManager.hasClaudeAPIKey ? "OK" : "Missing").font(.system(size: 11, design: .monospaced))
                        .foregroundColor(KeychainManager.hasClaudeAPIKey ? .green : .red.opacity(0.6))
                }
            }
        }
    }

    private var systemHealthPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SYSTEM HEALTH").font(.system(size: 11, weight: .bold)).foregroundColor(.gray)
            let s = systemMonitor.snapshot
            HStack { Image(systemName: "cpu").font(.system(size: 10)).foregroundColor(.gray); Text("CPU").font(.system(size: 11)).foregroundColor(.gray); Spacer()
                Text("\(s.cpuPercent)%").font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundColor(cpuColor(s.cpuPercent)) }
            ProgressView(value: s.cpuUsage).tint(cpuColor(s.cpuPercent)).scaleEffect(x: 1, y: 0.5)
            HStack { Image(systemName: "memorychip").font(.system(size: 10)).foregroundColor(.gray); Text("Memory").font(.system(size: 11)).foregroundColor(.gray); Spacer()
                Text("\(s.memoryUsedMB)/\(s.memoryTotalMB) MB").font(.system(size: 10, design: .monospaced)).foregroundColor(memoryColor(s.memoryPressure)) }
            ProgressView(value: Double(s.memoryUsedPercent) / 100.0).tint(memoryColor(s.memoryPressure)).scaleEffect(x: 1, y: 0.5)
            HStack { Text(s.memoryPressure.rawValue).font(.system(size: 9, design: .monospaced)).foregroundColor(memoryColor(s.memoryPressure)); Spacer()
                Text("可用 \(s.memoryAvailableMB) MB").font(.system(size: 9, design: .monospaced)).foregroundColor(.gray.opacity(0.5)) }
            HStack { Image(systemName: "wifi").font(.system(size: 10)).foregroundColor(.gray); Text("Network").font(.system(size: 11)).foregroundColor(.gray); Spacer()
                Text(s.networkQuality.rawValue).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundColor(networkColor(s.networkQuality)) }
        }
    }

    private func cpuColor(_ p: Int) -> Color { p > 80 ? .red : p > 50 ? .yellow : .green }
    private func memoryColor(_ p: SystemSnapshot.MemoryPressure) -> Color {
        switch p { case .critical: return .red; case .warning: return .yellow; case .normal: return .green } }
    private func networkColor(_ q: SystemSnapshot.NetworkQuality) -> Color {
        switch q { case .excellent, .good: return .green; case .fair: return .yellow; case .poor: return .red; case .unknown: return .gray } }
    private func statRow(_ label: String, _ value: String) -> some View {
        HStack { Text(label).font(.system(size: 11)).foregroundColor(.gray); Spacer()
            Text(value).font(.system(size: 11, design: .monospaced)).foregroundColor(.white) } }

    private var manualQueryBar: some View {
        HStack(spacing: 8) {
            TextField("Ask AI anything...", text: $manualQuestion)
                .textFieldStyle(.plain).font(.system(size: 13))
                .padding(8).background(Color.white.opacity(0.05)).cornerRadius(6)
            Button(action: { guard !manualQuestion.isEmpty else { return }
                let q = manualQuestion; manualQuestion = ""
                Task { await coordinator.manualQuery(q) }
            }) { Image(systemName: "paperplane.fill").foregroundColor(.purple) }
            .buttonStyle(.plain).disabled(manualQuestion.isEmpty)
        }.padding(12).background(Color(hex: "111118"))
    }
}

// MARK: - Transcript Entry Row
struct TranscriptEntryRow: View {
    let entry: TranscriptEntry; let isDualStream: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if isDualStream {
                Text(entry.speakerLabel).font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(speakerColor.opacity(0.7)).frame(width: 28).padding(.top, 2)
                RoundedRectangle(cornerRadius: 1).fill(speakerColor.opacity(0.4)).frame(width: 2)
            }
            Text(entry.text).font(.system(size: 16)).foregroundColor(textColor).frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 3)
    }
    private var speakerColor: Color { entry.speaker == .remote ? .cyan : .yellow }
    private var textColor: Color { entry.speaker == .remote ? .cyan.opacity(0.85) : .yellow.opacity(0.8) }
}

// MARK: - Talking Point Row
struct TalkingPointRow: View {
    let talkingPoint: TalkingPoint; let onComplete: () -> Void; let onSkip: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 8) {
                statusIcon.frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) { priorityBadge
                        Text(talkingPoint.content).font(.system(size: 12, weight: isCompleted ? .regular : .medium))
                            .foregroundColor(isCompleted ? .gray : .white).strikethrough(isCompleted).lineLimit(2) }
                    if let data = talkingPoint.supportingData, !isCompleted {
                        Text(data).font(.system(size: 10)).foregroundColor(.gray.opacity(0.7)).lineLimit(1) }
                }
                Spacer()
                if talkingPoint.status == .pending || talkingPoint.status == .inProgress {
                    HStack(spacing: 4) {
                        Button(action: onComplete) { Image(systemName: "checkmark").font(.system(size: 9)).foregroundColor(.green.opacity(0.7)) }.buttonStyle(.plain)
                        Button(action: onSkip) { Image(systemName: "forward").font(.system(size: 9)).foregroundColor(.gray.opacity(0.5)) }.buttonStyle(.plain)
                    }
                }
            }
            if let speech = talkingPoint.detectedSpeech {
                HStack(spacing: 4) {
                    if talkingPoint.status == .completed {
                        Image(systemName: "checkmark.message.fill").font(.system(size: 8)).foregroundColor(.green.opacity(0.7))
                        Text("偵測到我方已講").font(.system(size: 9, weight: .medium)).foregroundColor(.green.opacity(0.7))
                    } else {
                        Image(systemName: "waveform").font(.system(size: 8)).foregroundColor(.blue.opacity(0.6))
                        Text("偵測中").font(.system(size: 9, weight: .medium)).foregroundColor(.blue.opacity(0.6))
                    }
                    Text(speech).font(.system(size: 9, design: .monospaced)).foregroundColor(.gray.opacity(0.5)).lineLimit(1)
                }.padding(.leading, 24)
            }
        }.padding(.vertical, 4).padding(.horizontal, 6).background(rowBackground).cornerRadius(6)
    }
    private var isCompleted: Bool { talkingPoint.status == .completed || talkingPoint.status == .skipped }
    private var statusIcon: some View {
        Group { switch talkingPoint.status {
        case .completed: Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.system(size: 12))
        case .inProgress: Image(systemName: "circle.dotted").foregroundColor(.blue).font(.system(size: 12))
        case .skipped: Image(systemName: "forward.circle.fill").foregroundColor(.gray).font(.system(size: 12))
        case .pending: Image(systemName: "circle").foregroundColor(.gray.opacity(0.5)).font(.system(size: 12))
        } }
    }
    private var priorityBadge: some View {
        Text(talkingPoint.priority.rawValue).font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundColor(priorityColor).padding(.horizontal, 3).padding(.vertical, 1)
            .background(priorityColor.opacity(0.15)).cornerRadius(2)
    }
    private var priorityColor: Color { switch talkingPoint.priority { case .must: return .red; case .should: return .yellow; case .nice: return .gray } }
    private var rowBackground: Color { switch talkingPoint.status { case .inProgress: return Color.blue.opacity(0.08); case .completed: return Color.green.opacity(0.04); default: return Color.clear } }
}

// MARK: - AI Card View
struct AICardView: View {
    let card: AICard
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(card.title).font(.system(size: 14, weight: .bold)).foregroundColor(titleColor).lineLimit(1); Spacer()
                HStack(spacing: 8) {
                    Text("\(String(format: "%.0f", card.latencyMs))ms").font(.system(size: 10, design: .monospaced)).foregroundColor(.gray)
                    Text("\(String(format: "%.0f", card.confidence * 100))%").font(.system(size: 10, design: .monospaced)).foregroundColor(card.confidence > 0.9 ? .green : .yellow)
                } }
            Text(card.content).font(.system(size: 16)).foregroundColor(.white.opacity(0.9)).lineLimit(8)
        }.padding(14).background(cardBg).cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(borderColor, lineWidth: 1))
    }
    private var titleColor: Color { switch card.type { case .qaMatch: return .cyan; case .aiGenerated: return .purple; case .strategy: return .orange; case .warning: return .yellow } }
    private var borderColor: Color { titleColor.opacity(0.3) }
    private var cardBg: Color { switch card.type { case .qaMatch: return Color.cyan.opacity(0.08); case .aiGenerated: return Color.purple.opacity(0.08); case .strategy: return Color.orange.opacity(0.08); case .warning: return Color.yellow.opacity(0.08) } }
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0; Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count { case 6: (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF); default: (a, r, g, b) = (255, 0, 0, 0) }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
