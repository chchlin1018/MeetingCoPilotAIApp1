// UsageExample.swift
// MeetingCopilot v4.1 — SwiftUI Usage Example
// Three-layer pipeline + TalkingPoints panel + NotebookLM status
// UMC Digital Twin meeting scenario

import SwiftUI

// ═══════════════════════════════════════════════════════════════════════════
// MARK: - Main View
// ═══════════════════════════════════════════════════════════════════════════

struct MeetingTeleprompterView: View {

    @State private var coordinator: MeetingAICoordinator
    @State private var isSessionActive = false
    @State private var manualQuestion = ""

    init() {
        let context = MeetingContext(
            goals: [
                "取得 UMC Digital Twin PoC 預算核准",
                "建立與 Kevin Liu (IT VP) 的直接溝通管道",
                "確認 Q1 導入時程"
            ],
            preAnalysisCache: """
            【NotebookLM Pre-analysis】
            • UMC Q3: OEE dropped 87.2% -> 85.1%, Digital Twin can improve
            • Competitor AVEVA quotes $2.1M/yr, our IDTF 60% cheaper
            • Kevin Liu asked security compliance in last 2 meetings, prepare ISO 27001
            • UMC 2024 CapEx $4.2B, Digital Twin under Smart Manufacturing
            """,
            relevantQA: [],
            recentTranscript: "",
            attendeeInfo: """
            David Chen (VP Manufacturing) - Decision maker, ROI focused
            Linda Wang (Senior Engineer) - Technical evaluator, ex-AVEVA user
            Kevin Liu (IT VP) - Security gatekeeper, data residency concern
            """,
            meetingType: "Sales Proposal / Client Presentation"
        )

        _coordinator = State(initialValue: MeetingAICoordinator(
            claudeAPIKey: "YOUR_API_KEY_HERE",
            notebookLMConfig: .enabled(
                notebookId: "YOUR_NOTEBOOK_ID"  // 會前在 NotebookLM 建好的 Notebook
            ),
            meetingContext: context
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            HStack(spacing: 0) {
                transcriptPanel
                    .frame(width: 320)
                Divider()
                teleprompterPanel
                Divider()
                rightSidebar
                    .frame(width: 300)
            }
            manualQueryBar
        }
        .background(Color(hex: "0A0A0F"))
        .preferredColorScheme(.dark)
        .task { await loadDemoData() }
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: Header Bar
    // ═══════════════════════════════════════════════════════════

    private var headerBar: some View {
        HStack(spacing: 12) {
            // 引擎狀態
            HStack(spacing: 6) {
                Circle()
                    .fill(coordinator.captureState.isActive ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                if let engineType = coordinator.activeEngineType {
                    Text(engineType.rawValue)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.gray)
                }
            }

            // NotebookLM 狀態指示器
            notebookLMStatusBadge

            Spacer()

            Text("UMC Digital Twin Meeting")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)

            Spacer()

            // 統計數據（三層 + 成本）
            HStack(spacing: 10) {
                statBadge("🔵", "\(coordinator.stats.localMatches)", .cyan)
                statBadge("📚", "\(coordinator.stats.notebookLMQueries)", .teal)
                statBadge("🟣", "\(coordinator.stats.claudeQueries)", .purple)
                statBadge("🟠", "\(coordinator.stats.strategyAnalyses)", .orange)
                Text("$\(String(format: "%.2f", coordinator.stats.estimatedClaudeCost))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.orange)
            }

            // TP 完成率
            tpCompletionBadge

            // 開始 / 結束按鈕
            Button(action: { Task { await toggleSession() } }) {
                Text(isSessionActive ? "End Meeting" : "Start Meeting")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .background(isSessionActive ? Color.red.opacity(0.8) : Color.green.opacity(0.8))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color(hex: "111118"))
    }

    /// NotebookLM 連線狀態
    private var notebookLMStatusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(coordinator.isNotebookLMAvailable ? Color.teal : Color.gray.opacity(0.5))
                .frame(width: 6, height: 6)
            if coordinator.isNotebookLMQuerying {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
                Text("RAG...")
                    .font(.system(size: 10))
                    .foregroundColor(.teal)
            } else {
                Text("NLM")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(coordinator.isNotebookLMAvailable ? .teal : .gray.opacity(0.5))
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Color.teal.opacity(coordinator.isNotebookLMAvailable ? 0.1 : 0))
        .cornerRadius(4)
    }

    /// 統計徽章
    private func statBadge(_ emoji: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 2) {
            Text(emoji).font(.system(size: 10))
            Text(value).font(.system(size: 11, design: .monospaced)).foregroundColor(color)
        }
    }

    /// TP 完成率徽章
    private var tpCompletionBadge: some View {
        let stats = coordinator.tpStats
        let color: Color = stats.mustCompletionRate >= 1.0 ? .green
            : stats.mustCompletionRate >= 0.5 ? .yellow : .red

        return HStack(spacing: 4) {
            Text("TP")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(color)
            Text("\(stats.completed)/\(stats.total)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(color)
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(color.opacity(0.1))
        .cornerRadius(4)
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: Left Panel — Live Transcript
    // ═══════════════════════════════════════════════════════════

    private var transcriptPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LIVE TRANSCRIPT")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.gray)
                .padding(.horizontal, 12).padding(.top, 8)

            ScrollView {
                Text(coordinator.fullTranscript.isEmpty
                    ? "Waiting for meeting audio..."
                    : coordinator.fullTranscript)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(hex: "0D0D14"))
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: Center Panel — AI Teleprompter
    // ═══════════════════════════════════════════════════════════

    private var teleprompterPanel: some View {
        VStack(spacing: 0) {
            // 頂部標題 + 管線狀態
            HStack {
                Text("AI TELEPROMPTER")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)

                Spacer()

                // 管線即時狀態
                pipelineStatusIndicator
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            // 卡片列表
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(coordinator.cards) { card in
                        AICardView(card: card)
                    }
                }
                .padding(12)
            }
        }
        .background(Color(hex: "0D0D14"))
    }

    /// 管線即時狀態指示器
    private var pipelineStatusIndicator: some View {
        HStack(spacing: 8) {
            if coordinator.isNotebookLMQuerying {
                HStack(spacing: 4) {
                    ProgressView().scaleEffect(0.5)
                    Text("NotebookLM 搜尋中...")
                        .font(.system(size: 11))
                        .foregroundColor(.teal)
                }
            }
            if coordinator.isClaudeStreaming {
                HStack(spacing: 4) {
                    ProgressView().scaleEffect(0.5)
                    Text("Claude 思考中...")
                        .font(.system(size: 11))
                        .foregroundColor(.purple)
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: Right Sidebar — TP Panel + Meeting Info
    // ═══════════════════════════════════════════════════════════

    private var rightSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Talking Points 面板
                talkingPointsPanel

                Divider().background(Color.gray.opacity(0.3))

                // 會議目標
                goalsPanel

                Divider().background(Color.gray.opacity(0.3))

                // 統計面板
                statsPanel
            }
            .padding(12)
        }
        .background(Color(hex: "0D0D14"))
    }

    // ─────────────────────────────────────────────────────────
    // Talking Points Panel
    // ─────────────────────────────────────────────────────────

    private var talkingPointsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TALKING POINTS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.gray)
                Spacer()
                Text(coordinator.tpStats.summary)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.gray)
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

    // ─────────────────────────────────────────────────────────
    // Goals Panel
    // ─────────────────────────────────────────────────────────

    private var goalsPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("GOALS")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.gray)

            ForEach(["Get PoC budget approved",
                     "Build Kevin Liu channel",
                     "Confirm Q1 timeline"], id: \.self) { goal in
                HStack(spacing: 6) {
                    Image(systemName: "circle")
                        .font(.system(size: 8))
                        .foregroundColor(.gray)
                    Text(goal)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────
    // Stats Panel
    // ─────────────────────────────────────────────────────────

    private var statsPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SESSION STATS")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.gray)

            Group {
                statRow("Q&A Loaded", "\(coordinator.stats.qaItemsLoaded)")
                statRow("🔵 Local Match", "\(coordinator.stats.localMatches)")
                statRow("📚 NLM Queries", "\(coordinator.stats.notebookLMQueries)")
                statRow("🟣 Claude Queries", "\(coordinator.stats.claudeQueries)")
                statRow("🟠 Strategy", "\(coordinator.stats.strategyAnalyses)")
                statRow("Avg Latency", "\(String(format: "%.0f", coordinator.stats.averageClaudeLatencyMs))ms")
                statRow("AI Cost", "$\(String(format: "%.2f", coordinator.stats.estimatedClaudeCost))")
            }

            // NotebookLM 連線狀態
            HStack {
                Text("NotebookLM")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(coordinator.isNotebookLMAvailable ? Color.teal : Color.red.opacity(0.6))
                        .frame(width: 6, height: 6)
                    Text(coordinator.isNotebookLMAvailable ? "Connected" : "Offline")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(coordinator.isNotebookLMAvailable ? .teal : .red.opacity(0.6))
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

    // ═══════════════════════════════════════════════════════════
    // MARK: Bottom — Manual Query Bar
    // ═══════════════════════════════════════════════════════════

    private var manualQueryBar: some View {
        HStack(spacing: 8) {
            TextField("Ask AI anything...", text: $manualQuestion)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(8)
                .background(Color.white.opacity(0.05))
                .cornerRadius(6)

            Button(action: {
                guard !manualQuestion.isEmpty else { return }
                let q = manualQuestion; manualQuestion = ""
                Task { await coordinator.manualQuery(q) }
            }) {
                Image(systemName: "paperplane.fill")
                    .foregroundColor(.purple)
            }
            .buttonStyle(.plain)
            .disabled(manualQuestion.isEmpty)
        }
        .padding(12)
        .background(Color(hex: "111118"))
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: Actions
    // ═══════════════════════════════════════════════════════════

    private func toggleSession() async {
        if isSessionActive { await coordinator.stopMeeting() }
        else { await coordinator.startMeeting() }
        isSessionActive.toggle()
    }

    private func loadDemoData() async {
        // 載入 Q&A 知識庫（第一層用）
        await coordinator.loadKnowledgeBase(demoQAItems)

        // 載入 Talking Points（v4.1 新增）
        await coordinator.loadTalkingPoints(demoTalkingPoints, meetingDurationMinutes: 60)

        // 檢查 NotebookLM
        await coordinator.checkNotebookLMAvailability()
    }
}


// ═══════════════════════════════════════════════════════════════════════════
// MARK: - Talking Point Row
// ═══════════════════════════════════════════════════════════════════════════

struct TalkingPointRow: View {
    let talkingPoint: TalkingPoint
    let onComplete: () -> Void
    let onSkip: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // 狀態圖示
            statusIcon
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                // 優先級 + 內容
                HStack(spacing: 4) {
                    priorityBadge
                    Text(talkingPoint.content)
                        .font(.system(size: 12, weight: isCompleted ? .regular : .medium))
                        .foregroundColor(isCompleted ? .gray : .white)
                        .strikethrough(isCompleted)
                        .lineLimit(2)
                }

                // 支撐數據
                if let data = talkingPoint.supportingData, !isCompleted {
                    Text(data)
                        .font(.system(size: 10))
                        .foregroundColor(.gray.opacity(0.7))
                        .lineLimit(1)
                }
            }

            Spacer()

            // 手動操作按鈕
            if talkingPoint.status == .pending || talkingPoint.status == .inProgress {
                HStack(spacing: 4) {
                    Button(action: onComplete) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9))
                            .foregroundColor(.green.opacity(0.7))
                    }
                    .buttonStyle(.plain)

                    Button(action: onSkip) {
                        Image(systemName: "forward")
                            .font(.system(size: 9))
                            .foregroundColor(.gray.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4).padding(.horizontal, 6)
        .background(rowBackground)
        .cornerRadius(6)
    }

    private var isCompleted: Bool {
        talkingPoint.status == .completed || talkingPoint.status == .skipped
    }

    private var statusIcon: some View {
        Group {
            switch talkingPoint.status {
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 12))
            case .inProgress:
                Image(systemName: "circle.dotted")
                    .foregroundColor(.blue)
                    .font(.system(size: 12))
            case .skipped:
                Image(systemName: "forward.circle.fill")
                    .foregroundColor(.gray)
                    .font(.system(size: 12))
            case .pending:
                Image(systemName: "circle")
                    .foregroundColor(.gray.opacity(0.5))
                    .font(.system(size: 12))
            }
        }
    }

    private var priorityBadge: some View {
        Text(talkingPoint.priority.rawValue)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundColor(priorityColor)
            .padding(.horizontal, 3).padding(.vertical, 1)
            .background(priorityColor.opacity(0.15))
            .cornerRadius(2)
    }

    private var priorityColor: Color {
        switch talkingPoint.priority {
        case .must: return .red
        case .should: return .yellow
        case .nice: return .gray
        }
    }

    private var rowBackground: Color {
        switch talkingPoint.status {
        case .inProgress: return Color.blue.opacity(0.08)
        case .completed:  return Color.green.opacity(0.04)
        default:          return Color.clear
        }
    }
}


// ═══════════════════════════════════════════════════════════════════════════
// MARK: - AI Card View (v4.1 — 含文件佐證標示)
// ═══════════════════════════════════════════════════════════════════════════

struct AICardView: View {
    let card: AICard

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(card.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(titleColor)
                    .lineLimit(1)

                Spacer()

                HStack(spacing: 8) {
                    Text("\(String(format: "%.0f", card.latencyMs))ms")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.gray)
                    Text("\(String(format: "%.0f", card.confidence * 100))%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(card.confidence > 0.9 ? .green : .yellow)
                }
            }

            Text(card.content)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(6)
        }
        .padding(12)
        .background(cardBackground)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var titleColor: Color {
        switch card.type {
        case .qaMatch:     return .cyan
        case .aiGenerated: return .purple
        case .strategy:    return .orange
        case .warning:     return .yellow
        }
    }

    private var borderColor: Color { titleColor.opacity(0.3) }

    private var cardBackground: Color {
        switch card.type {
        case .qaMatch:     return Color.cyan.opacity(0.08)
        case .aiGenerated: return Color.purple.opacity(0.08)
        case .strategy:    return Color.orange.opacity(0.08)
        case .warning:     return Color.yellow.opacity(0.08)
        }
    }
}


// ═══════════════════════════════════════════════════════════════════════════
// MARK: - Demo Data
// ═══════════════════════════════════════════════════════════════════════════

// Demo Q&A Knowledge Base (Layer 1)
private let demoQAItems: [QAItem] = [
    QAItem(
        question: "IDTF vs AVEVA difference?",
        keywords: ["AVEVA", "差異", "不同", "比較", "競品"],
        shortAnswer: "IDTF: open-source neutral, 60% cheaper. AVEVA locked to Schneider, $2.1M/yr. IDTF supports OpenUSD + Teamcenter dual standard.",
        fullAnswer: "Three differentiators: (1) Open-source vendor neutral (2) $840K vs AVEVA $2.1M (3) Native OpenUSD + Teamcenter, AVEVA proprietary only."
    ),
    QAItem(
        question: "OpenUSD + Teamcenter integration?",
        keywords: ["OpenUSD", "Teamcenter", "整合", "標準", "格式"],
        shortAnswer: "IADL for real-time data, FDL for 3D geometry (OpenUSD). Teamcenter as PLM backbone, bidirectional sync. Validated at TSMC advanced packaging.",
        fullAnswer: "Three-layer: IADL (sensor data) + FDL (3D models) + Teamcenter REST API bidirectional BOM sync."
    ),
    QAItem(
        question: "Security compliance?",
        keywords: ["資安", "安全", "合規", "ISO", "data residency", "隱私"],
        shortAnswer: "ISO 27001 in progress, data stays in Taiwan (GCP asia-east1). VPC Service Controls, all APIs via mTLS. Passed TSMC Cybersecurity Assessment.",
        fullAnswer: "Four layers: ISO 27001 + Taiwan GCP + VPC isolation + mTLS. Passed TSMC security audit."
    ),
    QAItem(
        question: "Implementation timeline?",
        keywords: ["時程", "多久", "timeline", "什麼時候", "上線"],
        shortAnswer: "PoC 8 weeks (1 line), Pilot 12 weeks (3 lines), Full Rollout 6 months. Start Q1 PoC, see ROI by Q3.",
        fullAnswer: "Phase 1 PoC (8w) -> Phase 2 Pilot (12w) -> Phase 3 Rollout (24w). PoC investment $120K."
    ),
    QAItem(
        question: "ROI calculation?",
        keywords: ["ROI", "投資報酬", "效益", "省多少", "成本"],
        shortAnswer: "PoC $120K investment, single line saves $450K/yr (OEE +2%, unplanned downtime -15%). Payback ~4 months. Full rollout ROI 380%.",
        fullAnswer: "PoC $120K -> $450K/line/yr. 10-line rollout: $840K/yr -> $3.2M benefit. Payback 3.2 months."
    ),
    QAItem(
        question: "Team size and experience?",
        keywords: ["團隊", "經驗", "背景", "誰", "多少人"],
        shortAnswer: "Core team 6 people. Founder: 20yr semiconductor + industrial software (ex-AVEVA Taiwan Head). Advisors include ex-TSMC VP. GitHub 2K+ Stars.",
        fullAnswer: "CEO: 20yr enterprise + semiconductor. CTO: 15yr 3D engine. Advisor: ex-TSMC VP + HTFA committee."
    )
]

// Demo Talking Points (v4.1 new)
private let demoTalkingPoints: [TalkingPoint] = [
    TalkingPoint(
        content: "IDTF 與 AVEVA 差異化定位",
        priority: .must,
        keywords: ["AVEVA", "差異", "定位", "互補", "競品"],
        supportingData: "AVEVA 專注 Asset Lifecycle，IDTF 專注設備層級即時數據"
    ),
    TalkingPoint(
        content: "PoC 預算核准 — $120K / 8 週",
        priority: .must,
        keywords: ["預算", "budget", "PoC", "核准", "投資"],
        supportingData: "$120K 含 1 條產線，8 週交付 MVP"
    ),
    TalkingPoint(
        content: "ROI 預估與回收時程",
        priority: .must,
        keywords: ["ROI", "投資報酬", "回收", "效益", "payback"],
        supportingData: "單線 $450K/yr 節省，4 個月回收"
    ),
    TalkingPoint(
        content: "資安合規方案（Kevin 關注）",
        priority: .should,
        keywords: ["資安", "security", "合規", "ISO", "Kevin"],
        supportingData: "ISO 27001 + SEMI E187 + 台灣 GCP"
    ),
    TalkingPoint(
        content: "Q1 導入時程確認",
        priority: .should,
        keywords: ["Q1", "時程", "timeline", "導入", "上線"],
        supportingData: "1月啟動 → 3月 PoC 交付 → Q2 Pilot"
    ),
    TalkingPoint(
        content: "TSMC 先進封裝成功案例",
        priority: .nice,
        keywords: ["TSMC", "台積", "案例", "封裝", "reference"],
        supportingData: "TSMC CoWoS 產線 PoC，OEE +2.1%"
    )
]


// ═══════════════════════════════════════════════════════════════════════════
// MARK: - Color Extension
// ═══════════════════════════════════════════════════════════════════════════

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
