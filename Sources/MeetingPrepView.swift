// ═══════════════════════════════════════════════════════════════════════════
// MeetingPrepView.swift
// MeetingCopilot v4.3 — 會前準備 UI + MeetingTEXT 預設資料夾 + 資料來源連接
// ═══════════════════════════════════════════════════════════════════════════

import SwiftUI
import AppKit

// MARK: - Editable Row Models

struct EditableQAItem: Identifiable {
    let id = UUID()
    var question: String = ""
    var keywords: String = ""
    var answer: String = ""
    var qaType: QAType = .theirQuestion   // ★ 分類

    enum QAType: String, CaseIterable {
        case myQuestion = "我方提問"
        case theirQuestion = "對方可能問"
    }
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
    let speechLocale: Locale
    let notionPageId: String       // ★ 每場會議的 Notion page
    let notebookLMNotebookId: String  // ★ 每場會議的 NotebookLM notebook
}

// MARK: - 語言選項

struct SpeechLanguageOption: Identifiable, Hashable {
    let id: String
    let label: String
    let description: String
    static let options: [SpeechLanguageOption] = [
        SpeechLanguageOption(id: "zh-TW", label: "🇹🇼 中文（台灣）", description: "中英混雜會議建議選此"),
        SpeechLanguageOption(id: "en-US", label: "🇺🇸 English (US)", description: "純英文會議"),
        SpeechLanguageOption(id: "en-GB", label: "🇬🇧 English (UK)", description: "英式英文"),
        SpeechLanguageOption(id: "zh-CN", label: "🇨🇳 中文（簡體）", description: "簡體中文會議"),
        SpeechLanguageOption(id: "ja-JP", label: "🇯🇵 日本語", description: "日文會議"),
    ]
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
    @State private var speechLanguage: String = "zh-TW"
    @State private var qaItems: [EditableQAItem] = []
    @State private var talkingPoints: [EditableTalkingPoint] = []
    @State private var statusMessage: String = ""

    // ★ 資料來源連接
    @State private var notionPageId: String = ""
    @State private var notionPageUrl: String = ""
    @State private var notebookLMNotebookId: String = ""
    @State private var notebookLMBridgeUrl: String = "http://localhost:3210"

    // ★ 系統檢查 Sheet
    @State private var showSystemCheck = false

    private let meetingTypes = [
        "Sales Proposal", "Board Meeting", "Client Presentation",
        "Interview", "Review Meeting", "1-on-1", "Team Standup", "Other"
    ]

    // ★ 預設 MeetingTEXT 資料夾路徑
    private var meetingTEXTFolderURL: URL? {
        // 嘗試找到專案目錄下的 MeetingTEXT
        if let bundlePath = Bundle.main.resourceURL?.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent() {
            let meetingTextURL = bundlePath.appendingPathComponent("MeetingTEXT")
            if FileManager.default.fileExists(atPath: meetingTextURL.path) {
                return meetingTextURL
            }
        }
        // Fallback: 從使用者的 Documents/MyProjects 搜尋
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent("Documents/MyProjects/MeetingCopilotApp1/MeetingTEXT"),
            home.appendingPathComponent("Documents/MyProjects/MeetingCoPilotAIApp1/MeetingTEXT"),
            home.appendingPathComponent("Desktop/MeetingTEXT"),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    meetingInfoSection
                    Divider().background(Color.gray.opacity(0.3))
                    sourcesSection          // ★ 資料來源連接
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
        // ★ 系統檢查 Sheet
        .sheet(isPresented: $showSystemCheck) {
            SystemCheckView()
                .frame(width: 660, height: 560)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 16)).foregroundColor(.purple)
            Text("會前準備")
                .font(.system(size: 16, weight: .bold)).foregroundColor(.white)
            Spacer()
            if !statusMessage.isEmpty {
                Text(statusMessage).font(.system(size: 11)).foregroundColor(.green).transition(.opacity)
            }

            // ★ 系統檢查按鈕
            Button(action: { showSystemCheck = true }) {
                HStack(spacing: 4) { Image(systemName: "stethoscope"); Text("系統檢查") }
            }
            .buttonStyle(.plain).font(.system(size: 12)).foregroundColor(.orange)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color.orange.opacity(0.15)).cornerRadius(4)

            Button(action: loadFromFile) {
                HStack(spacing: 4) { Image(systemName: "folder.badge.plus"); Text("讀取") }
            }
            .buttonStyle(.plain).font(.system(size: 12)).foregroundColor(.blue)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color.blue.opacity(0.15)).cornerRadius(4)

            Button(action: saveToFile) {
                HStack(spacing: 4) { Image(systemName: "square.and.arrow.down"); Text("儲存") }
            }
            .buttonStyle(.plain).font(.system(size: 12)).foregroundColor(.green)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color.green.opacity(0.15)).cornerRadius(4)

            Button("Demo 資料") { loadDemoData() }
            .buttonStyle(.plain).font(.system(size: 12)).foregroundColor(.teal)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color.teal.opacity(0.15)).cornerRadius(4)
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
                LabeledField("時長（分鐘）") {
                    TextField("60", value: $durationMinutes, format: .number)
                        .textFieldStyle(.roundedBorder).frame(width: 80)
                }
                LabeledField("語音辨識語言") {
                    Picker("", selection: $speechLanguage) {
                        ForEach(SpeechLanguageOption.options) { opt in
                            Text(opt.label).tag(opt.id)
                        }
                    }.labelsHidden().frame(minWidth: 160)
                }
            }
            if let opt = SpeechLanguageOption.options.first(where: { $0.id == speechLanguage }) {
                Text(opt.description).font(.system(size: 10)).foregroundColor(.gray.opacity(0.6))
            }
        }
    }

    // MARK: ★ Sources Section（資料來源連接）

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("資料來源連接")
            Text("每場會議連接獨立的 Notion page 和 NotebookLM notebook")
                .font(.system(size: 10)).foregroundColor(.gray.opacity(0.5))

            // Notion
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("📝").font(.system(size: 12))
                        Text("Notion Page").font(.system(size: 11, weight: .medium)).foregroundColor(.teal)
                        if !notionPageId.isEmpty {
                            Text("✅").font(.system(size: 9))
                        }
                    }
                    TextField("Page ID 或 URL", text: $notionPageId)
                        .textFieldStyle(.roundedBorder).font(.system(size: 11))
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("📄").font(.system(size: 12))
                        Text("NotebookLM").font(.system(size: 11, weight: .medium)).foregroundColor(.purple)
                        if !notebookLMNotebookId.isEmpty {
                            Text("✅").font(.system(size: 9))
                        }
                    }
                    TextField("Notebook ID", text: $notebookLMNotebookId)
                        .textFieldStyle(.roundedBorder).font(.system(size: 11))
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.02))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.15), lineWidth: 1))
    }

    // MARK: Q&A Section（分我方/對方）

    private var qaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle("Q&A 預載")
                Spacer()
                let myCount = qaItems.filter { $0.qaType == .myQuestion }.count
                let theirCount = qaItems.filter { $0.qaType == .theirQuestion }.count
                Text("我方 \(myCount) | 對方 \(theirCount)").font(.system(size: 10, design: .monospaced)).foregroundColor(.gray)
                Button(action: { qaItems.append(EditableQAItem(qaType: .theirQuestion)) }) {
                    Image(systemName: "plus.circle").foregroundColor(.cyan)
                }.buttonStyle(.plain)
            }
            if qaItems.isEmpty {
                Text("點擊 + 新增預想問題，或讀取 TXT 檔案")
                    .font(.system(size: 12)).foregroundColor(.gray.opacity(0.5)).padding(.vertical, 8)
            }
            ForEach($qaItems) { $item in
                HStack(alignment: .top, spacing: 8) {
                    // ★ 類型選擇
                    Picker("", selection: $item.qaType) {
                        Text("我方").tag(EditableQAItem.QAType.myQuestion)
                        Text("對方").tag(EditableQAItem.QAType.theirQuestion)
                    }.labelsHidden().frame(width: 65)
                    VStack(spacing: 4) {
                        TextField("問題", text: $item.question).font(.system(size: 12)).textFieldStyle(.roundedBorder)
                        HStack(spacing: 4) {
                            TextField("關鍵字（逗號分隔）", text: $item.keywords).font(.system(size: 11)).textFieldStyle(.roundedBorder)
                            TextField(item.qaType == .myQuestion ? "提問目的" : "建議回答", text: $item.answer)
                                .font(.system(size: 11)).textFieldStyle(.roundedBorder)
                        }
                    }
                    Button(action: { qaItems.removeAll { $0.id == item.id } }) {
                        Image(systemName: "xmark.circle").foregroundColor(.red.opacity(0.6)).font(.system(size: 12))
                    }.buttonStyle(.plain)
                }
                .padding(8)
                .background(item.qaType == .myQuestion ? Color.blue.opacity(0.05) : Color.cyan.opacity(0.05))
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
            LabeledField("Pre-analysis（會前分析結果，選填）") {
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
                let myQ = qaItems.filter { $0.qaType == .myQuestion }.count
                let theirQ = qaItems.filter { $0.qaType == .theirQuestion }.count
                Text("\(myQ)+\(theirQ) Q&A").foregroundColor(.cyan)
                Text("·").foregroundColor(.gray)
                Text("\(talkingPoints.filter { $0.priority == .must }.count) MUST").foregroundColor(.red)
                Text("\(talkingPoints.filter { $0.priority == .should }.count) SHOULD").foregroundColor(.yellow)
                Text("\(talkingPoints.filter { $0.priority == .nice }.count) NICE").foregroundColor(.gray)
                Text("·").foregroundColor(.gray)
                Text(speechLanguage).foregroundColor(.blue)
                if !notionPageId.isEmpty { Text("📝").font(.system(size: 10)) }
                if !notebookLMNotebookId.isEmpty { Text("📄").font(.system(size: 10)) }
            }.font(.system(size: 11, design: .monospaced))
            Spacer()
            Button("清除全部") { clearAll() }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundColor(.gray)
            Button(action: startMeeting) {
                HStack(spacing: 6) { Image(systemName: "play.fill"); Text("開始會議") }
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
        switch p { case .must: return Color.red.opacity(0.06); case .should: return Color.yellow.opacity(0.05); case .nice: return Color.gray.opacity(0.05) }
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
        onStart(MeetingPrepResult(
            context: context, qaItems: builtQA, talkingPoints: builtTP,
            durationMinutes: durationMinutes,
            speechLocale: Locale(identifier: speechLanguage),
            notionPageId: notionPageId,
            notebookLMNotebookId: notebookLMNotebookId
        ))
    }

    // MARK: - ★ 儲存 TXT（預設 MeetingTEXT 資料夾）

    private func saveToFile() {
        let content = buildTXTContent()
        let panel = NSSavePanel()
        panel.title = "儲存會前準備"
        // ★ 預設到 MeetingTEXT 資料夾
        if let folder = meetingTEXTFolderURL { panel.directoryURL = folder }
        let dateStr = formatDate(Date())
        let safeName = sanitizeFilename(meetingTitle.isEmpty ? "meeting-prep" : meetingTitle)
        panel.nameFieldStringValue = "\(dateStr)_\(safeName).txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
                statusMessage = "✅ 已儲存"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { statusMessage = "" }
            } catch { statusMessage = "❌ 儲存失敗" }
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
        lines.append("language=\(speechLanguage)")
        lines.append("")
        // ★ 資料來源
        lines.append("[SOURCES]")
        lines.append("notion_page_id=\(notionPageId)")
        lines.append("notion_page_url=\(notionPageUrl)")
        lines.append("notebooklm_notebook_id=\(notebookLMNotebookId)")
        lines.append("notebooklm_bridge_url=\(notebookLMBridgeUrl)")
        lines.append("")
        lines.append("[GOALS]")
        for goal in goalsText.split(separator: "\n") where !goal.isEmpty { lines.append(String(goal)) }
        lines.append("")
        lines.append("[ATTENDEES]")
        for line in attendeeInfo.split(separator: "\n") where !line.isEmpty { lines.append(String(line)) }
        lines.append("")
        // ★ 分兩類 Q&A
        lines.append("[QA_MY_QUESTIONS]")
        lines.append("# 我方可能想問的問題（主動提問）")
        lines.append("# 格式: Q: 問題 / K: 關鍵字 / A: 預期答案/目的")
        for item in qaItems where !item.question.isEmpty && item.qaType == .myQuestion {
            lines.append(""); lines.append("Q: \(item.question)")
            lines.append("K: \(item.keywords)"); lines.append("A: \(item.answer)")
        }
        lines.append("")
        lines.append("[QA_THEIR_QUESTIONS]")
        lines.append("# 對方可能發問的問題（防禦準備）")
        lines.append("# 格式: Q: 問題 / K: 關鍵字 / A: 建議回答")
        for item in qaItems where !item.question.isEmpty && item.qaType == .theirQuestion {
            lines.append(""); lines.append("Q: \(item.question)")
            lines.append("K: \(item.keywords)"); lines.append("A: \(item.answer)")
        }
        lines.append("")
        lines.append("[TP]")
        for tp in talkingPoints where !tp.content.isEmpty {
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
    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
    }

    // MARK: - ★ 讀取 TXT（預設 MeetingTEXT 資料夾）

    private func loadFromFile() {
        let panel = NSOpenPanel()
        panel.title = "讀取會前準備"
        // ★ 預設到 MeetingTEXT 資料夾
        if let folder = meetingTEXTFolderURL { panel.directoryURL = folder }
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                parseTXTContent(content)
                statusMessage = "✅ 已讀取: \(url.lastPathComponent)"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { statusMessage = "" }
            } catch { statusMessage = "❌ 讀取失敗" }
        }
    }

    private func parseTXTContent(_ content: String) {
        clearAll()
        var currentSection = ""
        var goalsLines: [String] = []
        var attendeeLines: [String] = []
        var preAnalysisLines: [String] = []
        var currentQA: (q: String, k: String, a: String) = ("", "", "")
        var currentQAType: EditableQAItem.QAType = .theirQuestion

        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix("#") { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                // 儲存上一個 QA
                if !currentQA.q.isEmpty {
                    qaItems.append(EditableQAItem(question: currentQA.q, keywords: currentQA.k,
                                                  answer: currentQA.a, qaType: currentQAType))
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
                else if line.hasPrefix("language=") { speechLanguage = String(line.dropFirst(9)) }
            case "[SOURCES]":
                if line.hasPrefix("notion_page_id=") { notionPageId = String(line.dropFirst(15)) }
                else if line.hasPrefix("notion_page_url=") { notionPageUrl = String(line.dropFirst(16)) }
                else if line.hasPrefix("notebooklm_notebook_id=") { notebookLMNotebookId = String(line.dropFirst(23)) }
                else if line.hasPrefix("notebooklm_bridge_url=") { notebookLMBridgeUrl = String(line.dropFirst(22)) }
            case "[GOALS]":
                if !line.trimmingCharacters(in: .whitespaces).isEmpty { goalsLines.append(line) }
            case "[ATTENDEES]":
                if !line.trimmingCharacters(in: .whitespaces).isEmpty { attendeeLines.append(line) }
            case "[QA]", "[QA_MY_QUESTIONS]", "[QA_THEIR_QUESTIONS]":
                // 判斷 QA 類型
                if currentSection == "[QA_MY_QUESTIONS]" { currentQAType = .myQuestion }
                else { currentQAType = .theirQuestion }

                if line.hasPrefix("Q: ") || line.hasPrefix("Q:") {
                    if !currentQA.q.isEmpty {
                        qaItems.append(EditableQAItem(question: currentQA.q, keywords: currentQA.k,
                                                      answer: currentQA.a, qaType: currentQAType))
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
                    case "MUST": priority = .must; case "SHOULD": priority = .should; default: priority = .nice
                    }
                    talkingPoints.append(EditableTalkingPoint(
                        content: parts[1], priority: priority,
                        keywords: parts.count > 2 ? parts[2] : "",
                        supportingData: parts.count > 3 ? parts[3] : ""
                    ))
                }
            case "[PREANALYSIS]":
                preAnalysisLines.append(line)
            default: break
            }
        }
        if !currentQA.q.isEmpty {
            qaItems.append(EditableQAItem(question: currentQA.q, keywords: currentQA.k,
                                          answer: currentQA.a, qaType: currentQAType))
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
        speechLanguage = "zh-TW"
        qaItems = demo.umcQAItems.map { qa in
            EditableQAItem(question: qa.question, keywords: qa.keywords.joined(separator: ", "),
                          answer: qa.shortAnswer, qaType: .theirQuestion)
        }
        talkingPoints = demo.umcTalkingPoints.map { tp in
            EditableTalkingPoint(content: tp.content, priority: tp.priority,
                                keywords: tp.keywords.joined(separator: ", "), supportingData: tp.supportingData ?? "")
        }
    }

    private func clearAll() {
        meetingTitle = ""; goalsText = ""; attendeeInfo = ""
        preAnalysis = ""; qaItems = []; talkingPoints = []
        durationMinutes = 60; speechLanguage = "zh-TW"
        notionPageId = ""; notionPageUrl = ""
        notebookLMNotebookId = ""; notebookLMBridgeUrl = "http://localhost:3210"
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
