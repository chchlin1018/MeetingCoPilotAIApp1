// UsageExample.swift
// MeetingCopilot v4.3 — SwiftUI Main View
// Updated: Meeting Prep UI + Dual-stream + Keychain

import SwiftUI

// MARK: - Main View

struct MeetingTeleprompterView: View {

    @State private var coordinator: MeetingAICoordinator
    @State private var isSessionActive = false
    @State private var showPrepView = true           // ★ 預設顯示會前準備
    @State private var manualQuestion = ""
    @State private var meetingTitle = "Meeting"       // ★ 從 Prep 傳入

    init() {
        let apiKey = KeychainManager.claudeAPIKey ?? "NOT_CONFIGURED"
        let nlmConfig = KeychainManager.notebookLMConfig
        // 初始化用空 context，會前準備時再替換
        let emptyContext = MeetingContext(goals: [], preAnalysisCache: "",
            relevantQA: [], recentTranscript: "", attendeeInfo: "", meetingType: "")
        _coordinator = State(initialValue: MeetingAICoordinator(
            claudeAPIKey: apiKey, notebookLMConfig: nlmConfig, meetingContext: emptyContext
        ))
    }

    var body: some View {
        ZStack {
            // 會議主畫面
            VStack(spacing: 0) {
                headerBar
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

            // ★ 會前準備畫面（覆蓋在主畫面上）
            if showPrepView {
                Color.black.opacity(0.7).ignoresSafeArea()
                MeetingPrepView { result in
                    Task { await loadPrepAndStart(result) }
                }
                .frame(maxWidth: 900, maxHeight: 700)
                .background(.ultraThinMaterial)
                .cornerRadius(16)
                .shadow(radius: 20)
            }
        }
    }

    // MARK: 載入會前資料 + 啟動會議

    private func loadPrepAndStart(_ result: MeetingPrepResult) async {
        meetingTitle = result.context.goals.first ?? "Meeting"

        // 更新 context
        await coordinator.updateContext(result.context)

        // 載入 Q&A + TP
        await coordinator.loadKnowledgeBase(result.qaItems)
        await coordinator.loadTalkingPoints(result.talkingPoints, meetingDurationMinutes: result.durationMinutes)

        // 啟動會議
        await coordinator.startMeeting()
        isSessionActive = true
        showPrepView = false
    }

    // MARK: Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            // 引擎狀態
            HStack(spacing: 6) {
                Circle()
                    .fill(coordinator.captureState.isActive ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                if let engineType = coordinator.activeEngineType {
                    Text(engineType.rawValue)
                        .font(.system(size: 11, design: .monospaced)).foregroundColor(.gray)
                }
            }

            // 雙串流狀態
            if coordinator.hasDualStream {
                HStack(spacing: 3) {
                    Image(systemName: "person.2.wave.2").font(.system(size: 9))
                    Text("雙串流").font(.system(size: 10))
                }
                .foregroundColor(.green)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color.green.opacity(0.1)).cornerRadius(4)
            }

            notebookLMStatusBadge

            if !KeychainManager.hasClaudeAPIKey {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange).font(.system(size: 10))
                    Text("API Key 未設定").font(.system(size: 10)).foregroundColor(.orange)
                }
            }

            Spacer()

            Text(meetingTitle)
                .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                .lineLimit(1)

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

            // ★ 會議控制按鈕
            if isSessionActive {
                Button(action: { Task { await stopMeeting() } }) {
                    Text("End Meeting").font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 16).padding(.vertical, 6)
                        .background(Color.red.opacity(0.8)).cornerRadius(6)
                }.buttonStyle(.plain)
            } else {
                Button("準備會議") {
                    showPrepView = true
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 16).padding(.vertical, 6)
                .background(Color.purple.opacity(0.8)).cornerRadius(6)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color(hex: "111118"))
    }

    private func stopMeeting() async {
        await coordinator.stopMeeting()
        isSessionActive = false
    }

    private var notebookLMStatusBadge: some View {
        HStack(spacing: 4) {
            Circle().fill(coordinator.isNotebookLMAvailable ? Color.teal : Color.gray.opacity(0.5))
                .frame(width: 6, height: 6)
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
        HStack(spacing: 2) {
            Text(emoji).font(.system(size: 10))
            Text(value).font(.system(size: 11, design: .monospaced)).foregroundColor(color)
        }
    }

    private var tpCompletionBadge: some View {
        let stats = coordinator.tpStats
        let color: Color = stats.mustCompletionRate >= 1.0 ? .green
            : stats.mustCompletionRate >= 0.5 ? .yellow : .red
        return HStack(spacing: 4) {
            Text("TP").font(.system(size: 10, weight: .bold)).foregroundColor(color)
            Text("\(stats.completed)/\(stats.total)")
                .font(.system(size: 11, design: .monospaced)).foregroundColor(color)
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(color.opacity(0.1)).cornerRadius(4)
    }

    // MARK: Transcript Panel (★ 雙串流分色)

    private var transcriptPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LIVE TRANSCRIPT").font(.system(size: 11, weight: .bold)).foregroundColor(.gray)
                Spacer()
                if coordinator.hasDualStream {
                    Text("對方").font(.system(size: 9)).foregroundColor(.white.opacity(0.5))
                    Text("/").font(.system(size: 9)).foregroundColor(.gray)
                    Text("我方").font(.system(size: 9)).foregroundColor(.cyan.opacity(0.5))
                }
            }
            .padding(.horizontal, 12).padding(.top, 8)

            ScrollView {
                Text(coordinator.fullTranscript.isEmpty
                    ? "等待會議音訊..." : coordinator.fullTranscript)
                    .font(.system(size: 13)).foregroundColor(.white.opacity(0.8))
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(hex: "0D0D14"))
    }

    // MARK: Teleprompter Panel

    private var teleprompterPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("AI TELEPROMPTER")
                    .font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                Spacer()
                pipelineStatusIndicator
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            ScrollView {
                if coordinator.cards.isEmpty && !isSessionActive {
                    VStack(spacing: 12) {
                        Image(systemName: "sparkles").font(.system(size: 32)).foregroundColor(.purple.opacity(0.3))
                        Text("點擊「準備會議」開始")
                            .font(.system(size: 14)).foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 100)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(coordinator.cards) { card in AICardView(card: card) }
                    }.padding(12)
                }
            }
        }
        .background(Color(hex: "0D0D14"))
    }

    private var pipelineStatusIndicator: some View {
        HStack(spacing: 8) {
            if coordinator.isNotebookLMQuerying {
                HStack(spacing: 4) {
                    ProgressView().scaleEffect(0.5)
                    Text("NotebookLM 搜尋中...").font(.system(size: 11)).foregroundColor(.teal)
                }
            }
            if coordinator.isClaudeStreaming {
                HStack(spacing: 4) {
                    ProgressView().scaleEffect(0.5)
                    Text("Claude 思考中...").font(.system(size: 11)).foregroundColor(.purple)
                }
            }
        }
    }

    // MARK: Right Sidebar

    private var rightSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                talkingPointsPanel
                Divider().background(Color.gray.opacity(0.3))
                goalsPanel
                Divider().background(Color.gray.opacity(0.3))
                statsPanel
            }.padding(12)
        }
        .background(Color(hex: "0D0D14"))
    }

    private var talkingPointsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TALKING POINTS").font(.system(size: 11, weight: .bold)).foregroundColor(.gray)
                Spacer()
                Text(coordinator.tpStats.summary)
                    .font(.system(size: 10, design: .monospaced)).foregroundColor(.gray)
            }
            if coordinator.talkingPoints.isEmpty {
                Text("尚未載入").font(.system(size: 11)).foregroundColor(.gray.opacity(0.4))
            }
            ForEach(coordinator.talkingPoints) { tp in
                TalkingPointRow(
                    talkingPoint: tp,
                    onComplete: { Task { await coordinator.markTPCompleted(tp.id) } },
                    onSkip: { Task { await coordinator.markTPSkipped(tp.id) } }
                )
            }
        }
    }

    private var goalsPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("GOALS").font(.system(size: 11, weight: .bold)).foregroundColor(.gray)
            if coordinator.talkingPoints.isEmpty {
                Text("尚未設定").font(.system(size: 11)).foregroundColor(.gray.opacity(0.4))
            }
        }
    }

    private var statsPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SESSION STATS").font(.system(size: 11, weight: .bold)).foregroundColor(.gray)
            Group {
                statRow("Q&A Loaded", "\(coordinator.stats.qaItemsLoaded)")
                statRow("🔵 Local Match", "\(coordinator.stats.localMatches)")
                statRow("📚 NLM Queries", "\(coordinator.stats.notebookLMQueries)")
                statRow("🟣 Claude Queries", "\(coordinator.stats.claudeQueries)")
                statRow("🟠 Strategy", "\(coordinator.stats.strategyAnalyses)")
                statRow("Avg Latency", "\(String(format: "%.0f", coordinator.stats.averageClaudeLatencyMs))ms")
                statRow("AI Cost", "$\(String(format: "%.2f", coordinator.stats.estimatedClaudeCost))")
            }
            HStack {
                Text("雙串流").font(.system(size: 11)).foregroundColor(.gray)
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(coordinator.hasDualStream ? Color.green : Color.gray.opacity(0.4))
                        .frame(width: 6, height: 6)
                    Text(coordinator.hasDualStream ? "Active" : "Single")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(coordinator.hasDualStream ? .green : .gray)
                }
            }
            HStack {
                Text("API Key").font(.system(size: 11)).foregroundColor(.gray)
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(KeychainManager.hasClaudeAPIKey ? Color.green : Color.red.opacity(0.6))
                        .frame(width: 6, height: 6)
                    Text(KeychainManager.hasClaudeAPIKey ? "OK" : "Missing")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(KeychainManager.hasClaudeAPIKey ? .green : .red.opacity(0.6))
                }
            }
        }
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundColor(.gray)
            Spacer()
            Text(value).font(.system(size: 11, design: .monospaced)).foregroundColor(.white)
        }
    }

    // MARK: Manual Query Bar

    private var manualQueryBar: some View {
        HStack(spacing: 8) {
            TextField("Ask AI anything...", text: $manualQuestion)
                .textFieldStyle(.plain).font(.system(size: 13))
                .padding(8).background(Color.white.opacity(0.05)).cornerRadius(6)
            Button(action: {
                guard !manualQuestion.isEmpty else { return }
                let q = manualQuestion; manualQuestion = ""
                Task { await coordinator.manualQuery(q) }
            }) {
                Image(systemName: "paperplane.fill").foregroundColor(.purple)
            }
            .buttonStyle(.plain).disabled(manualQuestion.isEmpty)
        }
        .padding(12).background(Color(hex: "111118"))
    }
}


// MARK: - Talking Point Row

struct TalkingPointRow: View {
    let talkingPoint: TalkingPoint
    let onComplete: () -> Void
    let onSkip: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            statusIcon.frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    priorityBadge
                    Text(talkingPoint.content)
                        .font(.system(size: 12, weight: isCompleted ? .regular : .medium))
                        .foregroundColor(isCompleted ? .gray : .white)
                        .strikethrough(isCompleted).lineLimit(2)
                }
                if let data = talkingPoint.supportingData, !isCompleted {
                    Text(data).font(.system(size: 10))
                        .foregroundColor(.gray.opacity(0.7)).lineLimit(1)
                }
            }
            Spacer()
            if talkingPoint.status == .pending || talkingPoint.status == .inProgress {
                HStack(spacing: 4) {
                    Button(action: onComplete) {
                        Image(systemName: "checkmark").font(.system(size: 9)).foregroundColor(.green.opacity(0.7))
                    }.buttonStyle(.plain)
                    Button(action: onSkip) {
                        Image(systemName: "forward").font(.system(size: 9)).foregroundColor(.gray.opacity(0.5))
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4).padding(.horizontal, 6)
        .background(rowBackground).cornerRadius(6)
    }
    private var isCompleted: Bool { talkingPoint.status == .completed || talkingPoint.status == .skipped }
    private var statusIcon: some View {
        Group {
            switch talkingPoint.status {
            case .completed: Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.system(size: 12))
            case .inProgress: Image(systemName: "circle.dotted").foregroundColor(.blue).font(.system(size: 12))
            case .skipped: Image(systemName: "forward.circle.fill").foregroundColor(.gray).font(.system(size: 12))
            case .pending: Image(systemName: "circle").foregroundColor(.gray.opacity(0.5)).font(.system(size: 12))
            }
        }
    }
    private var priorityBadge: some View {
        Text(talkingPoint.priority.rawValue)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundColor(priorityColor)
            .padding(.horizontal, 3).padding(.vertical, 1)
            .background(priorityColor.opacity(0.15)).cornerRadius(2)
    }
    private var priorityColor: Color {
        switch talkingPoint.priority {
        case .must: return .red; case .should: return .yellow; case .nice: return .gray
        }
    }
    private var rowBackground: Color {
        switch talkingPoint.status {
        case .inProgress: return Color.blue.opacity(0.08)
        case .completed: return Color.green.opacity(0.04)
        default: return Color.clear
        }
    }
}


// MARK: - AI Card View

struct AICardView: View {
    let card: AICard
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(card.title).font(.system(size: 12, weight: .bold))
                    .foregroundColor(titleColor).lineLimit(1)
                Spacer()
                HStack(spacing: 8) {
                    Text("\(String(format: "%.0f", card.latencyMs))ms")
                        .font(.system(size: 10, design: .monospaced)).foregroundColor(.gray)
                    Text("\(String(format: "%.0f", card.confidence * 100))%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(card.confidence > 0.9 ? .green : .yellow)
                }
            }
            Text(card.content).font(.system(size: 13))
                .foregroundColor(.white.opacity(0.9)).lineLimit(6)
        }
        .padding(12).background(cardBackground).cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(borderColor, lineWidth: 1))
    }
    private var titleColor: Color {
        switch card.type {
        case .qaMatch: return .cyan; case .aiGenerated: return .purple
        case .strategy: return .orange; case .warning: return .yellow
        }
    }
    private var borderColor: Color { titleColor.opacity(0.3) }
    private var cardBackground: Color {
        switch card.type {
        case .qaMatch: return Color.cyan.opacity(0.08); case .aiGenerated: return Color.purple.opacity(0.08)
        case .strategy: return Color.orange.opacity(0.08); case .warning: return Color.yellow.opacity(0.08)
        }
    }
}


// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6: (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255,
                  blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
