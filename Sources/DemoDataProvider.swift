// ═══════════════════════════════════════════════════════════════════════════
// DemoDataProvider.swift
// MeetingCopilot v4.2 — Demo 資料隔離（從 UsageExample 抽出）
// ═══════════════════════════════════════════════════════════════════════════
//
//  所有 demo 用硬編碼資料集中在這裡。Production 版本不應引用此檔案。
//
//  Platform: macOS 14.0+
// ═══════════════════════════════════════════════════════════════════════════

import Foundation

enum DemoDataProvider {

    static let umcMeetingContext = MeetingContext(
        goals: [
            "取得 UMC Digital Twin PoC 預算核准",
            "建立與 Kevin Liu (IT VP) 的直接溝通管道",
            "確認 Q1 導入時程"
        ],
        preAnalysisCache: """
        【NotebookLM Pre-analysis】
        • UMC Q3: OEE dropped 87.2% -> 85.1%, Digital Twin can improve
        • Competitor AVEVA quotes $2.1M/yr, our IDTF 60% cheaper
        • Kevin Liu asked security compliance in last 2 meetings
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

    static let umcQAItems: [QAItem] = [
        QAItem(question: "IDTF vs AVEVA difference?",
               keywords: ["AVEVA", "差異", "不同", "比較", "競品"],
               shortAnswer: "IDTF: open-source neutral, 60% cheaper. AVEVA locked to Schneider, $2.1M/yr.",
               fullAnswer: "(1) Open-source vendor neutral (2) $840K vs AVEVA $2.1M (3) Native OpenUSD + Teamcenter."),
        QAItem(question: "OpenUSD + Teamcenter integration?",
               keywords: ["OpenUSD", "Teamcenter", "整合", "標準", "格式"],
               shortAnswer: "IADL for real-time data, FDL for 3D geometry (OpenUSD). Teamcenter bidirectional sync.",
               fullAnswer: "Three-layer: IADL + FDL + Teamcenter REST API bidirectional BOM sync."),
        QAItem(question: "Security compliance?",
               keywords: ["資安", "安全", "合規", "ISO", "data residency", "隱私"],
               shortAnswer: "ISO 27001 in progress, data in Taiwan (GCP asia-east1). mTLS. Passed TSMC audit.",
               fullAnswer: "ISO 27001 + Taiwan GCP + VPC isolation + mTLS."),
        QAItem(question: "Implementation timeline?",
               keywords: ["時程", "多久", "timeline", "什麼時候", "上線"],
               shortAnswer: "PoC 8 weeks, Pilot 12 weeks, Full Rollout 6 months.",
               fullAnswer: "Phase 1 PoC (8w) -> Phase 2 Pilot (12w) -> Phase 3 Rollout (24w). PoC $120K."),
        QAItem(question: "ROI calculation?",
               keywords: ["ROI", "投資報酬", "效益", "省多少", "成本"],
               shortAnswer: "PoC $120K, saves $450K/yr per line. Payback ~4 months. Full ROI 380%.",
               fullAnswer: "PoC $120K -> $450K/line/yr. 10-line: $840K/yr -> $3.2M benefit."),
        QAItem(question: "Team size and experience?",
               keywords: ["團隊", "經驗", "背景", "誰", "多少人"],
               shortAnswer: "Core team 6. Founder: 20yr semiconductor (ex-AVEVA Taiwan Head). GitHub 2K+ Stars.",
               fullAnswer: "CEO: 20yr enterprise. CTO: 15yr 3D engine. Advisor: ex-TSMC VP.")
    ]

    static let umcTalkingPoints: [TalkingPoint] = [
        TalkingPoint(content: "IDTF 與 AVEVA 差異化定位", priority: .must,
                     keywords: ["AVEVA", "差異", "定位", "互補", "競品"],
                     supportingData: "AVEVA 專注 Asset Lifecycle，IDTF 專注設備層級即時數據"),
        TalkingPoint(content: "PoC 預算核准 — $120K / 8 週", priority: .must,
                     keywords: ["預算", "budget", "PoC", "核准", "投資"],
                     supportingData: "$120K 含 1 條產線，8 週交付 MVP"),
        TalkingPoint(content: "ROI 預估與回收時程", priority: .must,
                     keywords: ["ROI", "投資報酬", "回收", "效益", "payback"],
                     supportingData: "單線 $450K/yr 節省，4 個月回收"),
        TalkingPoint(content: "資安合規方案（Kevin 關注）", priority: .should,
                     keywords: ["資安", "security", "合規", "ISO", "Kevin"],
                     supportingData: "ISO 27001 + SEMI E187 + 台灣 GCP"),
        TalkingPoint(content: "Q1 導入時程確認", priority: .should,
                     keywords: ["Q1", "時程", "timeline", "導入", "上線"],
                     supportingData: "1月啟動 → 3月 PoC 交付 → Q2 Pilot"),
        TalkingPoint(content: "TSMC 先進封裝成功案例", priority: .nice,
                     keywords: ["TSMC", "台積", "案例", "封裝", "reference"],
                     supportingData: "TSMC CoWoS 產線 PoC，OEE +2.1%")
    ]
}
