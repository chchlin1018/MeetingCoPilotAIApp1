// ═══════════════════════════════════════════════════════════════════════════
// MeetingPrepView.swift
// MeetingCopilot v4.3 — 會前準備設定 UI
// ═══════════════════════════════════════════════════════════════════════════
//
//  讓用戶在 App 內直接輸入每場會議的資料，不用改 code、不用重新 build。
//
//  設定項目：
//  - 會議目標
//  - 參與者資訊
//  - 會議類型
//  - Q&A 預載（第一層用）
//  - Talking Points（MUST / SHOULD / NICE）
//  - NotebookLM Notebook ID
//  - 會議時長
//
//  Platform: macOS 14.0+
// ═══════════════════════════════════════════════════════════════════════════

import SwiftUI

// MARK: - Editable Row Models

struct EditableQAItem: Identifiable {
    let id = UUID()
    var question: String = ""
    var keywords: String = ""     // 逗號分隔
    var answer: String = ""
}

struct EditableTalkingPoint: Identifiable {
    let id = UUID()
    var content: String = ""
    var priority: TalkingPoint.Priority = .must
    var keywords: String = ""     // 逗號分隔
    var supportingData: String = ""
}

// MARK: - Prep Result

struct MeetingPrepResult {
    let context: MeetingContext
    let qaItems: [QAItem]
    let talkingPoints: [TalkingPoint]
    let durationMinutes: Int
}

// MARK: - Meeting Prep View

struct MeetingPrepView: View {
    let onStart: (MeetingPrepResult) -> Void

    // 會議基本資訊
    @State private var meetingTitle: String = ""
    @State private var goalsText: String = ""
    @State private var attendeeInfo: String = ""
    @State private var meetingType: String = "Sales Proposal"
    @State private var preAnalysis: String = ""
    @State private var durationMinutes: Int = 60

    // Q&A 預載
    @State private var qaItems: [EditableQAItem] = []

    // Talking Points
    @State private var talkingPoints: [EditableTalkingPoint] = []

    private let meetingTypes = [
        "Sales Proposal", "Board Meeting", "Client Presentation",
        "Interview", "Review Meeting", "1-on-1", "Team Standup", "Other"
    ]

    var body: some View {
        VStack(spacing: 0) {
            // 標題列
            header

            // 內容
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    meetingInfoSection
                    Divider().background(Color.gray.opacity(0.3))
                    qaSection
                    Divider().background(Color.gray.opacity(0.3))
                    tpSection
                    Divider().background(Color.gray.opacity(0.3))
                    advancedSection
                }
                .padding(20)
            }

            // 底部按鈕
            bottomBar
        }
        .background(Color(hex: "0A0A0F"))
        .preferredColorScheme(.dark)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 16))
                .foregroundColor(.purple)
            Text("會前準備")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
            Spacer()
            Button("載入 Demo 資料") {
                loadDemoData()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundColor(.teal)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color.teal.opacity(0.15))
            .cornerRadius(4)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Color(hex: "111118"))
    }

    // MARK: Meeting Info

    private var meetingInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("會議資訊")

            LabeledField("會議名稱") {
                TextField("UMC Digital Twin Proposal", text: $meetingTitle)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
            }

            HStack(alignment: .top, spacing: 16) {
                LabeledField("會議目標（每行一個）") {
                    TextEditor(text: $goalsText)
                        .font(.system(size: 12))
                        .frame(height: 70)
                        .scrollContentBackground(.hidden)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(6)
                }

                LabeledField("參與者資訊") {
                    TextEditor(text: $attendeeInfo)
                        .font(.system(size: 12))
                        .frame(height: 70)
                        .scrollContentBackground(.hidden)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(6)
                }
            }

            HStack(spacing: 16) {
                LabeledField("會議類型") {
                    Picker("", selection: $meetingType) {
                        ForEach(meetingTypes, id: \.self) { Text($0) }
                    }.labelsHidden()
                }
                LabeledField("會議時長（分鐘）") {
                    TextField("60", value: $durationMinutes, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
            }
        }
    }

    // MARK: Q&A Section

    private var qaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle("Q&A 預載（第一層）")
                Spacer()
                Text("\(qaItems.count) 題").font(.system(size: 11, design: .monospaced)).foregroundColor(.gray)
                Button(action: { qaItems.append(EditableQAItem()) }) {
                    Image(systemName: "plus.circle").foregroundColor(.cyan)
                }.buttonStyle(.plain)
            }

            if qaItems.isEmpty {
                Text("點擊 + 新增預想問題，或載入 Demo 資料")
                    .font(.system(size: 12)).foregroundColor(.gray.opacity(0.5))
                    .padding(.vertical, 8)
            }

            ForEach($qaItems) { $item in
                HStack(alignment: .top, spacing: 8) {
                    VStack(spacing: 4) {
                        TextField("問題", text: $item.question)
                            .font(.system(size: 12))
                            .textFieldStyle(.roundedBorder)
                        HStack(spacing: 4) {
                            TextField("關鍵字（逗號分隔）", text: $item.keywords)
                                .font(.system(size: 11)).textFieldStyle(.roundedBorder)
                            TextField("簡短答案", text: $item.answer)
                                .font(.system(size: 11)).textFieldStyle(.roundedBorder)
                        }
                    }
                    Button(action: { qaItems.removeAll { $0.id == item.id } }) {
                        Image(systemName: "xmark.circle").foregroundColor(.red.opacity(0.6)).font(.system(size: 12))
                    }.buttonStyle(.plain)
                }
                .padding(8)
                .background(Color.cyan.opacity(0.05))
                .cornerRadius(6)
            }
        }
    }

    // MARK: Talking Points Section

    private var tpSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle("Talking Points")
                Spacer()
                Text("\(talkingPoints.count) 點").font(.system(size: 11, design: .monospaced)).foregroundColor(.gray)
                Button(action: { talkingPoints.append(EditableTalkingPoint()) }) {
                    Image(systemName: "plus.circle").foregroundColor(.orange)
                }.buttonStyle(.plain)
            }

            if talkingPoints.isEmpty {
                Text("點擊 + 新增這場會議一定要講的重點")
                    .font(.system(size: 12)).foregroundColor(.gray.opacity(0.5))
                    .padding(.vertical, 8)
            }

            ForEach($talkingPoints) { $tp in
                HStack(alignment: .top, spacing: 8) {
                    // 優先級選擇器
                    Picker("", selection: $tp.priority) {
                        Text("MUST").tag(TalkingPoint.Priority.must)
                        Text("SHOULD").tag(TalkingPoint.Priority.should)
                        Text("NICE").tag(TalkingPoint.Priority.nice)
                    }
                    .labelsHidden()
                    .frame(width: 85)

                    VStack(spacing: 4) {
                        TextField("重點內容", text: $tp.content)
                            .font(.system(size: 12)).textFieldStyle(.roundedBorder)
                        HStack(spacing: 4) {
                            TextField("關鍵字（逗號分隔）", text: $tp.keywords)
                                .font(.system(size: 11)).textFieldStyle(.roundedBorder)
                            TextField("支擐數據（選填）", text: $tp.supportingData)
                                .font(.system(size: 11)).textFieldStyle(.roundedBorder)
                        }
                    }
                    Button(action: { talkingPoints.removeAll { $0.id == tp.id } }) {
                        Image(systemName: "xmark.circle").foregroundColor(.red.opacity(0.6)).font(.system(size: 12))
                    }.buttonStyle(.plain)
                }
                .padding(8)
                .background(priorityBg(tp.priority))
                .cornerRadius(6)
            }
        }
    }

    // MARK: Advanced

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("進階設定")
            LabeledField("NotebookLM Pre-analysis（會前分析結果，選填）") {
                TextEditor(text: $preAnalysis)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 60)
                    .scrollContentBackground(.hidden)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(6)
            }
        }
    }

    // MARK: Bottom Bar

    private var bottomBar: some View {
        HStack {
            // 資訊摘要
            Group {
                Text("\(qaItems.count) Q&A").foregroundColor(.cyan)
                Text("·").foregroundColor(.gray)
                Text("\(talkingPoints.filter { $0.priority == .must }.count) MUST").foregroundColor(.red)
                Text("\(talkingPoints.filter { $0.priority == .should }.count) SHOULD").foregroundColor(.yellow)
                Text("\(talkingPoints.filter { $0.priority == .nice }.count) NICE").foregroundColor(.gray)
            }
            .font(.system(size: 11, design: .monospaced))

            Spacer()

            Button("清除全部") {
                clearAll()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12)).foregroundColor(.gray)

            Button(action: startMeeting) {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                    Text("開始會議")
                }
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 20).padding(.vertical, 8)
                .background(Color.green.opacity(0.8))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(!isValid)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(Color(hex: "111118"))
    }

    // MARK: - Helpers

    private var isValid: Bool {
        !meetingTitle.isEmpty || !goalsText.isEmpty || !qaItems.isEmpty || !talkingPoints.isEmpty
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(.white)
    }

    private func priorityBg(_ p: TalkingPoint.Priority) -> Color {
        switch p {
        case .must: return Color.red.opacity(0.06)
        case .should: return Color.yellow.opacity(0.05)
        case .nice: return Color.gray.opacity(0.05)
        }
    }

    // MARK: - Build Result

    private func startMeeting() {
        let goals = goalsText.split(separator: "\n").map(String.init).filter { !$0.isEmpty }

        let context = MeetingContext(
            goals: goals,
            preAnalysisCache: preAnalysis,
            relevantQA: [],
            recentTranscript: "",
            attendeeInfo: attendeeInfo,
            meetingType: meetingType
        )

        let builtQA = qaItems.compactMap { item -> QAItem? in
            guard !item.question.isEmpty, !item.answer.isEmpty else { return nil }
            let kw = item.keywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            return QAItem(question: item.question, keywords: kw,
                          shortAnswer: item.answer, fullAnswer: item.answer)
        }

        let builtTP = talkingPoints.compactMap { tp -> TalkingPoint? in
            guard !tp.content.isEmpty else { return nil }
            let kw = tp.keywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            return TalkingPoint(content: tp.content, priority: tp.priority,
                                keywords: kw, supportingData: tp.supportingData.isEmpty ? nil : tp.supportingData)
        }

        onStart(MeetingPrepResult(
            context: context, qaItems: builtQA,
            talkingPoints: builtTP, durationMinutes: durationMinutes
        ))
    }

    // MARK: - Load Demo

    private func loadDemoData() {
        let demo = DemoDataProvider.self
        meetingTitle = "UMC Digital Twin Meeting"
        goalsText = demo.umcMeetingContext.goals.joined(separator: "\n")
        attendeeInfo = demo.umcMeetingContext.attendeeInfo
        meetingType = demo.umcMeetingContext.meetingType
        preAnalysis = demo.umcMeetingContext.preAnalysisCache

        qaItems = demo.umcQAItems.map { qa in
            EditableQAItem(question: qa.question,
                           keywords: qa.keywords.joined(separator: ", "),
                           answer: qa.shortAnswer)
        }

        talkingPoints = demo.umcTalkingPoints.map { tp in
            EditableTalkingPoint(content: tp.content, priority: tp.priority,
                                keywords: tp.keywords.joined(separator: ", "),
                                supportingData: tp.supportingData ?? "")
        }
    }

    private func clearAll() {
        meetingTitle = ""; goalsText = ""; attendeeInfo = ""
        preAnalysis = ""; qaItems = []; talkingPoints = []
    }
}

// MARK: - Labeled Field Helper

struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.gray)
            content
        }
    }
}
