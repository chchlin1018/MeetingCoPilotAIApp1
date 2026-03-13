// SpeakerPrompterView.swift
// SpeakerPrompter v1.0 — 主 UI
// Fixed: onKeyPress closure + Sendable

import SwiftUI
import UniformTypeIdentifiers

struct SpeakerPrompterView: View {
    
    @State private var speechConfig = SpeechConfig()
    @State private var speechTimer = SpeechTimer()
    @State private var isLoaded = false
    @State private var showFileImporter = false
    
    var body: some View {
        if !isLoaded {
            loadView
        } else {
            prompterView
                .focusable()
                .onKeyPress { press in
                    handleKeyPress(press)
                }
        }
    }
    
    // MARK: - Key Handler
    
    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .rightArrow:
            speechTimer.nextSection()
            return .handled
        case .leftArrow:
            speechTimer.previousSection()
            return .handled
        case .space:
            toggleTimer()
            return .handled
        default:
            if press.characters.lowercased() == "r" {
                speechTimer.reset()
                return .handled
            }
            return .ignored
        }
    }
    
    // MARK: - Load View
    
    private var loadView: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.wave.2.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange.opacity(0.8))
            
            Text("SpeakerPrompter")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)
            
            Text("個人演講提示版")
                .font(.system(size: 16))
                .foregroundColor(.gray)
            
            Button(action: { showFileImporter = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                    Text("讀取演講 TXT 檔")
                }
                .font(.system(size: 16, weight: .semibold))
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.orange.opacity(0.8))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            
            Button(action: loadDemo) {
                Text("或使用範例")
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex2: "0A0A0F"))
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.plainText]) { result in
            if case .success(let url) = result {
                loadFile(url: url)
            }
        }
    }
    
    // MARK: - Prompter View
    
    private var prompterView: some View {
        VStack(spacing: 0) {
            topBar
            
            HStack(spacing: 0) {
                agendaPanel.frame(width: 300)
                Divider()
                centerPanel
                Divider()
                rightPanel.frame(width: 280)
            }
            
            timerBar
        }
        .background(Color(hex2: "0A0A0F"))
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Top Bar
    
    private var topBar: some View {
        HStack(spacing: 12) {
            Text(speechConfig.title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
            
            Text(speechConfig.type)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.orange)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.orange.opacity(0.15)).cornerRadius(4)
            
            Spacer()
            
            HStack(spacing: 8) {
                switch speechTimer.state {
                case .idle:
                    Button(action: { speechTimer.start() }) {
                        HStack(spacing: 4) { Image(systemName: "play.fill"); Text("開始演講") }
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 16).padding(.vertical, 6)
                        .background(Color.green.opacity(0.8)).cornerRadius(6)
                    }.buttonStyle(.plain)
                case .running:
                    Button(action: { speechTimer.pause() }) {
                        HStack(spacing: 4) { Image(systemName: "pause.fill"); Text("暫停") }
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 16).padding(.vertical, 6)
                        .background(Color.yellow.opacity(0.8)).cornerRadius(6)
                    }.buttonStyle(.plain)
                case .paused:
                    Button(action: { speechTimer.start() }) {
                        HStack(spacing: 4) { Image(systemName: "play.fill"); Text("繼續") }
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 16).padding(.vertical, 6)
                        .background(Color.green.opacity(0.8)).cornerRadius(6)
                    }.buttonStyle(.plain)
                case .finished:
                    Text("✅ 演講結束")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.green)
                }
                if speechTimer.state != .idle {
                    Button(action: { speechTimer.reset() }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12)).foregroundColor(.gray)
                    }.buttonStyle(.plain)
                }
            }
            
            Button(action: { isLoaded = false; speechTimer.reset() }) {
                Image(systemName: "xmark").font(.system(size: 12)).foregroundColor(.gray)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color(hex2: "111118"))
    }
    
    // MARK: - Agenda Panel
    
    private var agendaPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AGENDA")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.gray)
                .padding(.horizontal, 12).padding(.top, 8)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(Array(speechTimer.sections.enumerated()), id: \.element.id) { index, item in
                        agendaRow(item: item, index: index)
                    }
                }.padding(.horizontal, 12)
            }
        }
        .background(Color(hex2: "0D0D14"))
    }
    
    private func agendaRow(item: AgendaItem, index: Int) -> some View {
        HStack(spacing: 8) {
            Group {
                if item.isCompleted {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                } else if item.isActive {
                    Image(systemName: "arrow.right.circle.fill").foregroundColor(.orange)
                } else {
                    Text("\(item.order)").foregroundColor(.gray.opacity(0.5))
                }
            }
            .font(.system(size: 12)).frame(width: 20)
            
            Text(item.title)
                .font(.system(size: 13, weight: item.isActive ? .bold : .regular))
                .foregroundColor(item.isActive ? .white : item.isCompleted ? .gray : .white.opacity(0.7))
                .strikethrough(item.isCompleted)
                .lineLimit(2)
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(item.minutes)m")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(item.isActive ? .orange : .gray)
                if item.isCompleted && item.actualSeconds > 0 {
                    Text(SpeechTimer.formatTime(item.actualSeconds))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(item.actualSeconds > item.minutes * 60 ? .red : .green)
                }
            }
        }
        .padding(.vertical, 6).padding(.horizontal, 8)
        .background(item.isActive ? Color.orange.opacity(0.1) : Color.clear)
        .cornerRadius(6)
        .onTapGesture {
            if speechTimer.state == .running || speechTimer.state == .paused {
                jumpToSection(index)
            }
        }
    }
    
    // MARK: - Center Panel
    
    private var centerPanel: some View {
        VStack(spacing: 16) {
            if let section = speechTimer.currentSection {
                VStack(spacing: 8) {
                    Text("第 \(section.order) 段")
                        .font(.system(size: 14))
                        .foregroundColor(.orange.opacity(0.7))
                    
                    Text(section.title)
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    
                    HStack(spacing: 16) {
                        let remaining = speechTimer.sectionRemainingSeconds
                        let isOver = speechTimer.isSectionOvertime
                        Text(isOver ? "+\(SpeechTimer.formatTime(speechTimer.sectionElapsedSeconds - section.minutes * 60))" : SpeechTimer.formatTime(remaining))
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .foregroundColor(isOver ? .red : remaining < 30 ? .yellow : .green)
                        
                        Text("/ \(section.minutes)m")
                            .font(.system(size: 16, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                    
                    ProgressView(value: speechTimer.sectionProgress)
                        .tint(speechTimer.isSectionOvertime ? .red : speechTimer.sectionProgress > 0.8 ? .yellow : .green)
                        .frame(width: 300)
                }
                .padding(.top, 20)
            } else {
                Text("演講完成")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.green)
                    .padding(.top, 40)
            }
            
            Spacer()
            
            if speechTimer.state == .running || speechTimer.state == .paused {
                HStack(spacing: 20) {
                    Button(action: { speechTimer.previousSection() }) {
                        HStack { Image(systemName: "chevron.left"); Text("上一段") }
                            .font(.system(size: 14))
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(Color.gray.opacity(0.2)).cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(speechTimer.currentSectionIndex == 0)
                    
                    Button(action: { speechTimer.nextSection() }) {
                        HStack { Text("下一段"); Image(systemName: "chevron.right") }
                            .font(.system(size: 16, weight: .semibold))
                            .padding(.horizontal, 24).padding(.vertical, 10)
                            .background(Color.orange.opacity(0.8)).cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 20)
            }
            
            HStack(spacing: 16) {
                keyHint("→", "下一段")
                keyHint("←", "上一段")
                keyHint("Space", "開始/暫停")
                keyHint("R", "重置")
            }
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background(Color(hex2: "0D0D14"))
    }
    
    private func keyHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color.white.opacity(0.1)).cornerRadius(3)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.gray.opacity(0.5))
        }
    }
    
    // MARK: - Right Panel
    
    private var rightPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("TALKING POINTS")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.gray)
                        Spacer()
                        let done = speechConfig.talkingPoints.filter { $0.isCompleted }.count
                        Text("\(done)/\(speechConfig.talkingPoints.count)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                    
                    ForEach(Array(speechConfig.talkingPoints.enumerated()), id: \.element.id) { index, tp in
                        HStack(alignment: .top, spacing: 6) {
                            Button(action: { speechConfig.talkingPoints[index].isCompleted.toggle() }) {
                                Image(systemName: tp.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 12))
                                    .foregroundColor(tp.isCompleted ? .green : .gray.opacity(0.5))
                            }.buttonStyle(.plain)
                            
                            Text(tp.priority.rawValue)
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(priorityColor(tp.priority))
                                .padding(.horizontal, 3).padding(.vertical, 1)
                                .background(priorityColor(tp.priority).opacity(0.15)).cornerRadius(2)
                            
                            Text(tp.content)
                                .font(.system(size: 11, weight: tp.isCompleted ? .regular : .medium))
                                .foregroundColor(tp.isCompleted ? .gray : .white)
                                .strikethrough(tp.isCompleted)
                                .lineLimit(3)
                        }
                        .padding(.vertical, 2)
                    }
                }
                
                if !speechConfig.notes.isEmpty {
                    Divider().background(Color.gray.opacity(0.3))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("NOTES")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.gray)
                        
                        ForEach(speechConfig.notes, id: \.self) { note in
                            HStack(alignment: .top, spacing: 4) {
                                Text("•")
                                    .font(.system(size: 10))
                                    .foregroundColor(.yellow.opacity(0.6))
                                Text(note)
                                    .font(.system(size: 11))
                                    .foregroundColor(.yellow.opacity(0.7))
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
        .background(Color(hex2: "0D0D14"))
    }
    
    // MARK: - Timer Bar
    
    private var timerBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.system(size: 12))
                    .foregroundColor(speechTimer.isOvertime ? .red : .white)
                Text(SpeechTimer.formatTime(speechTimer.totalElapsedSeconds))
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(speechTimer.isOvertime ? .red : .white)
                Text("/ \(speechConfig.totalMinutes)m")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(.gray)
            }
            
            ProgressView(value: speechTimer.progress)
                .tint(speechTimer.isOvertime ? .red : speechTimer.progress > 0.8 ? .yellow : .orange)
            
            let remaining = speechTimer.totalRemainingSeconds
            Text(speechTimer.isOvertime ? "+\(SpeechTimer.formatTime(speechTimer.totalElapsedSeconds - speechConfig.totalMinutes * 60))" : "-\(SpeechTimer.formatTime(remaining))")
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundColor(speechTimer.isOvertime ? .red : remaining < 120 ? .yellow : .green)
            
            Text("\(speechTimer.currentSectionIndex + 1)/\(speechTimer.sections.count)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.orange)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.orange.opacity(0.15)).cornerRadius(4)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(speechTimer.isOvertime ? Color.red.opacity(0.15) : Color(hex2: "111118"))
    }
    
    // MARK: - Helpers
    
    private func priorityColor(_ priority: TPPriority) -> Color {
        switch priority { case .must: return .red; case .should: return .yellow; case .nice: return .gray }
    }
    
    private func toggleTimer() {
        switch speechTimer.state {
        case .idle: speechTimer.start()
        case .running: speechTimer.pause()
        case .paused: speechTimer.start()
        case .finished: speechTimer.reset()
        }
    }
    
    private func jumpToSection(_ index: Int) {
        while speechTimer.currentSectionIndex < index { speechTimer.nextSection() }
        while speechTimer.currentSectionIndex > index { speechTimer.previousSection() }
    }
    
    private func loadFile(url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        speechConfig = SpeechFileParser.parse(content)
        speechTimer.totalMinutes = speechConfig.totalMinutes
        speechTimer.sections = speechConfig.agenda
        isLoaded = true
    }
    
    private func loadDemo() {
        let demo = """
        [SPEECH]
        title=IDTF 開源工業數位雙胞胎架構
        type=Investor Pitch
        total_minutes=20
        
        [AGENDA]
        1|開場白 + 自我介紹|2
        2|工業數位雙胞胎市場痛點|3
        3|IDTF 架構介紹|5
        4|技術 Demo|5
        5|商業模式 + Roadmap|3
        6|Q&A|2
        
        [TP]
        MUST|強調 IDTF 與 AVEVA/Siemens 的差異化：開源 + 跨平台
        MUST|展示 TSMC 相關經驗和關係
        MUST|Seed Round 目標 $2M 和用途說明
        SHOULD|提到 2000+ GitHub Stars 社群認可
        SHOULD|NVIDIA Omniverse / OpenUSD 整合優勢
        NICE|半導體客戶案例（久元電子）
        NICE|未來 v5.0 WhisperKit 路線圖
        
        [NOTES]
        開場要強而有力，不要先說「大家好」
        用故事開始：「我在 AVEVA 做了 20 年...」
        Demo 時放慢速度，讓觀眾看清楚
        Q&A 時先重複問題再回答
        """
        speechConfig = SpeechFileParser.parse(demo)
        speechTimer.totalMinutes = speechConfig.totalMinutes
        speechTimer.sections = speechConfig.agenda
        isLoaded = true
    }
}

extension Color {
    init(hex2: String) {
        let hex = hex2.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0; Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count { case 6: (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF); default: (a, r, g, b) = (255, 0, 0, 0) }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
