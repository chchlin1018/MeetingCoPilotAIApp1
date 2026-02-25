// UsageExample.swift
// MeetingCopilot v4.0 — SwiftUI Usage Example
// Complete demo with UMC Digital Twin meeting scenario

import SwiftUI

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
            meetingContext: context
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            HStack(spacing: 0) {
                transcriptPanel.frame(width: 350)
                Divider()
                teleprompterPanel
                Divider()
                meetingInfoPanel.frame(width: 280)
            }
            manualQueryBar
        }
        .background(Color(hex: "0A0A0F"))
        .preferredColorScheme(.dark)
        .task { await loadDemoKnowledgeBase() }
    }

    private var headerBar: some View {
        HStack {
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
            Spacer()
            Text("UMC Digital Twin Meeting")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
            HStack(spacing: 12) {
                Label("\(coordinator.stats.localMatches)", systemImage: "checkmark.circle").foregroundColor(.cyan)
                Label("\(coordinator.stats.claudeQueries)", systemImage: "brain").foregroundColor(.purple)
                Label("$\(String(format: "%.2f", coordinator.stats.estimatedClaudeCost))", systemImage: "dollarsign.circle").foregroundColor(.orange)
            }
            .font(.system(size: 11, design: .monospaced))
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

    private var transcriptPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Live Transcript")
                .font(.system(size: 11, weight: .bold)).foregroundColor(.gray)
                .padding(.horizontal, 12).padding(.top, 8)
            ScrollView {
                Text(coordinator.fullTranscript.isEmpty ? "Waiting for meeting..." : coordinator.fullTranscript)
                    .font(.system(size: 13)).foregroundColor(.white.opacity(0.8))
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(hex: "0D0D14"))
    }

    private var teleprompterPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("AI Teleprompter").font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                Spacer()
                if coordinator.isClaudeStreaming {
                    HStack(spacing: 4) {
                        ProgressView().scaleEffect(0.6)
                        Text("Claude thinking...").font(.system(size: 11)).foregroundColor(.purple)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(coordinator.cards) { card in AICardView(card: card) }
                }
                .padding(12)
            }
        }
        .background(Color(hex: "0D0D14"))
    }

    private var meetingInfoPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Goals").font(.system(size: 11, weight: .bold)).foregroundColor(.gray)
            ForEach(["Get PoC budget approved", "Build Kevin channel", "Confirm Q1 timeline"], id: \.self) { goal in
                Text("⬜ \(goal)").font(.system(size: 12)).foregroundColor(.white.opacity(0.9))
            }
            Divider().background(Color.gray.opacity(0.3))
            Text("Stats").font(.system(size: 11, weight: .bold)).foregroundColor(.gray)
            VStack(alignment: .leading, spacing: 4) {
                statRow("Q&A Loaded", "\(coordinator.stats.qaItemsLoaded)")
                statRow("Local Match", "\(coordinator.stats.localMatches)")
                statRow("Claude Queries", "\(coordinator.stats.claudeQueries)")
                statRow("Strategy", "\(coordinator.stats.strategyAnalyses)")
            }
        }
        .padding(12).background(Color(hex: "0D0D14"))
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundColor(.gray)
            Spacer()
            Text(value).font(.system(size: 11, design: .monospaced)).foregroundColor(.white)
        }
    }

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

    private func toggleSession() async {
        if isSessionActive { await coordinator.stopMeeting() }
        else { await coordinator.startMeeting() }
        isSessionActive.toggle()
    }

    private func loadDemoKnowledgeBase() async {
        let demoQA: [QAItem] = [
            QAItem(question: "IDTF vs AVEVA difference?",
                   keywords: ["AVEVA", "差異", "不同", "比較", "競品"],
                   shortAnswer: "IDTF: open-source neutral, 60% cheaper. AVEVA locked to Schneider, $2.1M/yr. IDTF supports OpenUSD + Teamcenter dual standard.",
                   fullAnswer: "Three differentiators: (1) Open-source vendor neutral (2) $840K vs AVEVA $2.1M (3) Native OpenUSD + Teamcenter, AVEVA proprietary only."),
            QAItem(question: "OpenUSD + Teamcenter integration?",
                   keywords: ["OpenUSD", "Teamcenter", "整合", "標準", "格式"],
                   shortAnswer: "IADL for real-time data, FDL for 3D geometry (OpenUSD). Teamcenter as PLM backbone, bidirectional sync. Validated at TSMC advanced packaging.",
                   fullAnswer: "Three-layer: IADL (sensor data) + FDL (3D models) + Teamcenter REST API bidirectional BOM sync."),
            QAItem(question: "Security compliance?",
                   keywords: ["資安", "安全", "合規", "ISO", "data residency", "隱私"],
                   shortAnswer: "ISO 27001 in progress, data stays in Taiwan (GCP asia-east1). VPC Service Controls, all APIs via mTLS. Passed TSMC Cybersecurity Assessment.",
                   fullAnswer: "Four layers: ISO 27001 + Taiwan GCP + VPC isolation + mTLS. Passed TSMC security audit."),
            QAItem(question: "Implementation timeline?",
                   keywords: ["時程", "多久", "timeline", "什麼時候", "上線"],
                   shortAnswer: "PoC 8 weeks (1 line), Pilot 12 weeks (3 lines), Full Rollout 6 months. Start Q1 PoC, see ROI by Q3.",
                   fullAnswer: "Phase 1 PoC (8w) -> Phase 2 Pilot (12w) -> Phase 3 Rollout (24w). PoC investment $120K."),
            QAItem(question: "ROI calculation?",
                   keywords: ["ROI", "投資報酬", "效益", "省多少", "成本"],
                   shortAnswer: "PoC $120K investment, single line saves $450K/yr (OEE +2%, unplanned downtime -15%). Payback ~4 months. Full rollout ROI 380%.",
                   fullAnswer: "PoC $120K -> $450K/line/yr. 10-line rollout: $840K/yr -> $3.2M benefit. Payback 3.2 months."),
            QAItem(question: "Team size and experience?",
                   keywords: ["團隊", "經驗", "背景", "誰", "多少人"],
                   shortAnswer: "Core team 6 people. Founder: 20yr semiconductor + industrial software (ex-AVEVA Taiwan Head). Advisors include ex-TSMC VP. GitHub 2K+ Stars.",
                   fullAnswer: "CEO: 20yr enterprise + semiconductor. CTO: 15yr 3D engine. Advisor: ex-TSMC VP + HTFA committee.")
        ]
        await coordinator.loadKnowledgeBase(demoQA)
    }
}

// MARK: - AI Card View

struct AICardView: View {
    let card: AICard

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(card.title).font(.system(size: 12, weight: .bold)).foregroundColor(titleColor)
                Spacer()
                HStack(spacing: 8) {
                    Text("\(String(format: "%.0f", card.latencyMs))ms").font(.system(size: 10, design: .monospaced)).foregroundColor(.gray)
                    Text("\(String(format: "%.0f", card.confidence * 100))%").font(.system(size: 10, design: .monospaced))
                        .foregroundColor(card.confidence > 0.9 ? .green : .yellow)
                }
            }
            Text(card.content).font(.system(size: 13)).foregroundColor(.white.opacity(0.9)).lineLimit(5)
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
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
