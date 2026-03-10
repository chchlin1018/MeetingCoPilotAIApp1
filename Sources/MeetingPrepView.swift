// ═══════════════════════════════════════════════════════════════════════════
// MeetingPrepView.swift
// MeetingCopilot v4.3 — 會前準備設定 UI + TXT 儲存/讀取
// ═══════════════════════════════════════════════════════════════════════════
//
//  功能：
//  - 輸入會議資料（目標、參與者、Q&A、TP）
//  - 儲存為明文 TXT 檔案（可人工編輯）
//  - 從 TXT 檔案讀取（快速載入上次的會議準備）
//  - 載入 Demo 資料
//
//  TXT 格式範例：
//  [MEETING]
//  title=UMC Digital Twin Meeting
//  type=Sales Proposal
//  duration=60
//
//  [GOALS]
//  取得 PoC 預算核准
//  確認 Q1 導入時程
//
//  [ATTENDEES]
//  David Chen - VP Manufacturing
//
//  [QA]
//  Q: ROI 怎麼算？
//  K: ROI,投資,成本
//  A: PoC $120K, 單線 $450K/yr
//
//  [TP]
//  MUST|AVEVA 差異化|AVEVA,差異,定位|AVEVA 專注 Asset Lifecycle
//
//  [PREANALYSIS]
//  NotebookLM pre-analysis content...
//
//  Platform: macOS 14.0+
// ═══════════════════════════════════════════════════════════════════════════

import SwiftUI
import AppKit

// MARK: - Editable Row Models

struct EditableQAItem: Identifiable {
    let id = UUID()
    var question: String = ""
    var keywords: String = ""
    var answer: String = ""
}

struct EditableTalkingPoint: Identifiable {
    let id = UUID()
    var content: String = ""
    var priority: TalkingPoint.Priority = .must
    var keywords: String = ""
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

    @State private var meetingTitle: String = ""
    @State private var goalsText: String = ""
    @State private var attendeeInfo: String = ""
    @State private var meetingType: String = "Sales Proposal"
    @State private var preAnalysis: String = ""
    @State private var durationMinutes: Int = 60
    @State private var qaItems: [EditableQAItem] = []
    @State private var talkingPoints: [EditableTalkingPoint] = []
    @State private var statusMessage: String = ""

    private let meetingTypes = [
        "Sales Proposal", "Board Meeting", "Client Presentation",
        "Interview", "Review Meeting", "1-on-1", "Team Standup", "Other"
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
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
            bottomBar
        }
        .background(Color(hex: "0A0A0F"))
        .preferredColorScheme(.dark)
    }

    // MARK: Header（含儲存/讀取按鈕）

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 16)).foregroundColor(.purple)
            Text("會前準備")
                .font(.system(size: 16, weight: .bold)).foregroundColor(.white)

            Spacer()

            // 狀態訊息
            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.system(size: 11))
                    .foregroundColor(.green)
                    .transition(.opacity)
            }

            // ★ 讀取 TXT
            Button(action: loadFromFile) {
                HStack(spacing: 4) {
                    Image(systemName: "folder.badge.plus")
                    Text("讀取")
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundColor(.blue)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color.blue.opacity(0.15))
            .cornerRadius(4)

            // ★ 儲存 TXT
            Button(action: saveToFile) {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.down")
                    Text("儲存")
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundColor(.green)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color.green.opacity(0.15))
            .cornerRadius(4)

            // 載入 Demo
            Button("Demo 資料") { loadDemoData() }
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
                    .textFieldStyle(.roundedBorder).font(.system(size: 13))
            }
            HStack(alignment: .top, spacing: 16) {
                LabeledField("會議目標（每行一個）") {
                    TextEditor(text: $goalsText).font(.system(size: 12))
                        .frame(height: 70).scrollContentBackground(.hidden)
                        .background(Color.white.opacity(0.05)).cornerRadius(6)
                }
                LabeledField("參與者資訊") {
                    TextEditor(text: $attendeeInfo).font(.system(size: 12))
                        .frame(height: 70).scrollContentBackground(.hidden)
                        .background(Color.white.opacity(0.05)).cornerRadius(6)
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
                        .textFieldStyle(.roundedBorder).frame(width: 80)
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
                Text("點擊 + 新增預想問題，或讀取 TXT 檔案")
                    .font(.system(size: 12)).foregroundColor(.gray.opacity(0.5)).padding(.vertical, 8)
            }
            ForEach($qaItems) { $item in
                HStack(alignment: .top, spacing: 8) {
                    VStack(spacing: 4) {
                        TextField("問題", text: $item.question).font(.system(size: 12)).textFieldStyle(.roundedBorder)
                        HStack(spacing: 4) {
                            TextField("關鍵字（逗號分隔）", text: $item.keywords).font(.system(size: 11)).textFieldStyle(.roundedBorder)
                            TextField("簡短答案", text: $item.answer).font(.system(size: 11)).textFieldStyle(.roundedBorder)
                        }
                    }
                    Button(action: { qaItems.removeAll { $0.id == item.id } }) {
                        Image(systemName: "xmark.circle").foregroundColor(.red.opacity(0.6)).font(.system(size: 12))
                    }.buttonStyle(.plain)
                }
                .padding(8).background(Color.cyan.opacity(0.05)).cornerRadius(6)
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
                    .font(.system(size: 12)).foregroundColor(.gray.opacity(0.5)).padding(.vertical, 8)
            }
            ForEach($talkingPoints) { $tp in
                HStack(alignment: .top, spacing: 8) {
                    Picker("", selection: $tp.priority) {
                        Text("MUST").tag(TalkingPoint.Priority.must)
                        Text("SHOULD").tag(TalkingPoint.Priority.should)
                        Text("NICE").tag(TalkingPoint.Priority.nice)
                    }.labelsHidden().frame(width: 85)
                    VStack(spacing: 4) {
                        TextField("重點內容", text: $tp.content).font(.system(size: 12)).textFieldStyle(.roundedBorder)
                        HStack(spacing: 4) {
                            TextField("關鍵字（逗號分隔）", text: $tp.keywords).font(.system(size: 11)).textFieldStyle(.roundedBorder)
                            TextField("支撐數據（選填）", text: $tp.supportingData).font(.system(size: 11)).textFieldStyle(.roundedBorder)
                        }
                    }
                    Button(action: { talkingPoints.removeAll { $0.id == tp.id } }) {
                        Image(systemName: "xmark.circle").foregroundColor(.red.opacity(0.6)).font(.system(size: 12))
                    }.buttonStyle(.plain)
                }
                .padding(8).background(priorityBg(tp.priority)).cornerRadius(6)
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
                    .frame(height: 60).scrollContentBackground(.hidden)
                    .background(Color.white.opacity(0.05)).cornerRadius(6)
            }
        }
    }

    // MARK: Bottom Bar

    private var bottomBar: some View {
        HStack {
            Group {
                Text("\(qaItems.count) Q&A").foregroundColor(.cyan)
                Text("·").foregroundColor(.gray)
                Text("\(talkingPoints.filter { $0.priority == .must }.count) MUST").foregroundColor(.red)
                Text("\(talkingPoints.filter { $0.priority == .should }.count) SHOULD").foregroundColor(.yellow)
                Text("\(talkingPoints.filter { $0.priority == .nice }.count) NICE").foregroundColor(.gray)
            }.font(.system(size: 11, design: .monospaced))
            Spacer()
            Button("清除全部") { clearAll() }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundColor(.gray)
            Button(action: startMeeting) {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                    Text("開始會議")
                }
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 20).padding(.vertical, 8)
                .background(Color.green.opacity(0.8)).cornerRadius(8)
            }
            .buttonStyle(.plain).disabled(!isValid)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(Color(hex: "111118"))
    }

    // MARK: - Helpers

    private var isValid: Bool {
        !meetingTitle.isEmpty || !goalsText.isEmpty || !qaItems.isEmpty || !talkingPoints.isEmpty
    }
    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 13, weight: .bold)).foregroundColor(.white)
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
        let context = MeetingContext(goals: goals, preAnalysisCache: preAnalysis,
            relevantQA: [], recentTranscript: "", attendeeInfo: attendeeInfo, meetingType: meetingType)
        let builtQA = qaItems.compactMap { item -> QAItem? in
            guard !item.question.isEmpty, !item.answer.isEmpty else { return nil }
            let kw = item.keywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            return QAItem(question: item.question, keywords: kw, shortAnswer: item.answer, fullAnswer: item.answer)
        }
        let builtTP = talkingPoints.compactMap { tp -> TalkingPoint? in
            guard !tp.content.isEmpty else { return nil }
            let kw = tp.keywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            return TalkingPoint(content: tp.content, priority: tp.priority,
                                keywords: kw, supportingData: tp.supportingData.isEmpty ? nil : tp.supportingData)
        }
        onStart(MeetingPrepResult(context: context, qaItems: builtQA, talkingPoints: builtTP, durationMinutes: durationMinutes))
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - ★ 儲存為 TXT
    // ═══════════════════════════════════════════════════════════

    private func saveToFile() {
        let content = buildTXTContent()
        let panel = NSSavePanel()
        panel.title = "儲存會前準備"
        panel.nameFieldStringValue = sanitizeFilename(meetingTitle.isEmpty ? "meeting-prep" : meetingTitle) + ".txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
                statusMessage = "✅ 已儲存"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { statusMessage = "" }
            } catch {
                statusMessage = "❌ 儲存失敗"
            }
        }
    }

    private func buildTXTContent() -> String {
        var lines: [String] = []
        lines.append("# MeetingCopilot 會前準備檔案")
        lines.append("# 可直接用文字編輯器修改此檔案")
        lines.append("")

        lines.append("[MEETING]")
        lines.append("title=\(meetingTitle)")
        lines.append("type=\(meetingType)")
        lines.append("duration=\(durationMinutes)")
        lines.append("")

        lines.append("[GOALS]")
        for goal in goalsText.split(separator: "\n") where !goal.isEmpty {
            lines.append(String(goal))
        }
        lines.append("")

        lines.append("[ATTENDEES]")
        for line in attendeeInfo.split(separator: "\n") where !line.isEmpty {
            lines.append(String(line))
        }
        lines.append("")

        lines.append("[QA]")
        for item in qaItems where !item.question.isEmpty {
            lines.append("Q: \(item.question)")
            lines.append("K: \(item.keywords)")
            lines.append("A: \(item.answer)")
            lines.append("")
        }

        lines.append("[TP]")
        for tp in talkingPoints where !tp.content.isEmpty {
            // 格式: PRIORITY|內容|關鍵字|支撐數據
            lines.append("\(tp.priority.rawValue)|\(tp.content)|\(tp.keywords)|\(tp.supportingData)")
        }
        lines.append("")

        lines.append("[PREANALYSIS]")
        lines.append(preAnalysis)

        return lines.joined(separator: "\n")
    }

    private func sanitizeFilename(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_ "))
        return name.unicodeScalars.filter { allowed.contains($0) }.map(String.init).joined()
            .replacingOccurrences(of: " ", with: "-")
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - ★ 從 TXT 讀取
    // ═══════════════════════════════════════════════════════════

    private func loadFromFile() {
        let panel = NSOpenPanel()
        panel.title = "讀取會前準備"
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                parseTXTContent(content)
                statusMessage = "✅ 已讀取: \(url.lastPathComponent)"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { statusMessage = "" }
            } catch {
                statusMessage = "❌ 讀取失敗"
            }
        }
    }

    private func parseTXTContent(_ content: String) {
        clearAll()

        var currentSection = ""
        var goalsLines: [String] = []
        var attendeeLines: [String] = []
        var preAnalysisLines: [String] = []
        var currentQA: (q: String, k: String, a: String) = ("", "", "")

        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)

            // 跳過註解
            if line.hasPrefix("#") { continue }

            // Section header
            if line.hasPrefix("[") && line.hasSuffix("]") {
                // 儲存上一個未完成的 QA
                if !currentQA.q.isEmpty {
                    qaItems.append(EditableQAItem(question: currentQA.q, keywords: currentQA.k, answer: currentQA.a))
                    currentQA = ("", "", "")
                }
                currentSection = line.uppercased()
                continue
            }

            switch currentSection {
            case "[MEETING]":
                if line.hasPrefix("title=") { meetingTitle = String(line.dropFirst(6)) }
                else if line.hasPrefix("type=") { meetingType = String(line.dropFirst(5)) }
                else if line.hasPrefix("duration=") { durationMinutes = Int(line.dropFirst(9)) ?? 60 }

            case "[GOALS]":
                if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    goalsLines.append(line)
                }

            case "[ATTENDEES]":
                if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    attendeeLines.append(line)
                }

            case "[QA]":
                if line.hasPrefix("Q: ") || line.hasPrefix("Q:") {
                    // 儲存上一筆
                    if !currentQA.q.isEmpty {
                        qaItems.append(EditableQAItem(question: currentQA.q, keywords: currentQA.k, answer: currentQA.a))
                    }
                    currentQA = (String(line.dropFirst(line.hasPrefix("Q: ") ? 3 : 2)), "", "")
                } else if line.hasPrefix("K: ") || line.hasPrefix("K:") {
                    currentQA.k = String(line.dropFirst(line.hasPrefix("K: ") ? 3 : 2))
                } else if line.hasPrefix("A: ") || line.hasPrefix("A:") {
                    currentQA.a = String(line.dropFirst(line.hasPrefix("A: ") ? 3 : 2))
                }

            case "[TP]":
                let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                if parts.count >= 2 {
                    let priority: TalkingPoint.Priority
                    switch parts[0].uppercased() {
                    case "MUST": priority = .must
                    case "SHOULD": priority = .should
                    default: priority = .nice
                    }
                    talkingPoints.append(EditableTalkingPoint(
                        content: parts[1],
                        priority: priority,
                        keywords: parts.count > 2 ? parts[2] : "",
                        supportingData: parts.count > 3 ? parts[3] : ""
                    ))
                }

            case "[PREANALYSIS]":
                preAnalysisLines.append(line)

            default:
                break
            }
        }

        // 最後一筆 QA
        if !currentQA.q.isEmpty {
            qaItems.append(EditableQAItem(question: currentQA.q, keywords: currentQA.k, answer: currentQA.a))
        }

        goalsText = goalsLines.joined(separator: "\n")
        attendeeInfo = attendeeLines.joined(separator: "\n")
        preAnalysis = preAnalysisLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
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
            EditableQAItem(question: qa.question, keywords: qa.keywords.joined(separator: ", "), answer: qa.shortAnswer)
        }
        talkingPoints = demo.umcTalkingPoints.map { tp in
            EditableTalkingPoint(content: tp.content, priority: tp.priority,
                                keywords: tp.keywords.joined(separator: ", "), supportingData: tp.supportingData ?? "")
        }
    }

    private func clearAll() {
        meetingTitle = ""; goalsText = ""; attendeeInfo = ""
        preAnalysis = ""; qaItems = []; talkingPoints = []; durationMinutes = 60
    }
}

// MARK: - Labeled Field Helper

struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content
    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11, weight: .medium)).foregroundColor(.gray)
            content
        }
    }
}
