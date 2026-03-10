// ═══════════════════════════════════════════════════════════════════════════
// PostMeetingReportService.swift
// MeetingCopilot v4.3 — 會後報告產生器
// ═══════════════════════════════════════════════════════════════════════════
//
//  功能：
//  1. Claude 自動產生會議摘要（3-5 個要點）
//  2. Action Items 自動擷取（從逐字稿偵測「我們會...」「下一步...」）
//  3. Markdown 報告產生
//  4. 匯出到 Notion page
//
//  Platform: macOS 14.0+
// ═══════════════════════════════════════════════════════════════════════════

import Foundation

// MARK: - Action Item

struct ActionItem: Identifiable, Sendable {
    let id = UUID()
    let content: String
    let assignee: String?       // 「我」/「對方」/ nil
    let dueHint: String?        // 「本週」「下週一」/ nil
    let source: Source

    enum Source: String, Sendable {
        case transcript = "transcript"   // 從逐字稿偵測
        case claude = "claude"           // Claude 擷取
    }
}

// MARK: - Meeting Report

struct MeetingReport: Sendable {
    let title: String
    let startTime: Date?
    let endTime: Date
    let duration: TimeInterval?
    let language: String
    let summary: [String]               // 3-5 個要點
    let actionItems: [ActionItem]
    let talkingPoints: [TalkingPoint]
    let tpStats: TPStats
    let stats: SessionStats
    let transcript: String
    let cards: [AICard]
}

// MARK: - Report Format

enum ReportFormat: String, CaseIterable {
    case txt = "TXT"
    case markdown = "Markdown"
}

// MARK: - Post Meeting Report Service

actor PostMeetingReportService {

    private let claudeAPIKey: String

    init(claudeAPIKey: String) {
        self.claudeAPIKey = claudeAPIKey
    }

    // ═════════════════════════════════════════════════
    // MARK: 1. Claude 會議摘要
    // ═════════════════════════════════════════════════

    func generateSummary(transcript: String, cards: [AICard], tpStats: TPStats) async -> [String] {
        let trimmedTranscript = String(transcript.suffix(6000))
        let cardSummary = cards.prefix(10).map { "[\($0.type.rawValue)] \($0.title): \($0.content.prefix(80))" }.joined(separator: "\n")

        let prompt = """
        你是會議摘要助手。根據以下會議逐字稿和 AI 卡片，產生 3-5 個會議要點摘要。

        規則：
        - 每個要點 1 行，不超過 40 字
        - 包含具體數字/決策/共識
        - 用繁體中文
        - 只輸出要點，每行一個，不要編號、不要標題
        - Talking Points 完成率: \(tpStats.completed)/\(tpStats.total)，MUST: \(tpStats.mustCompleted)/\(tpStats.mustTotal)

        AI 卡片摘要：
        \(cardSummary)

        逐字稿：
        \(trimmedTranscript)
        """

        let result = await callClaude(prompt: prompt, maxTokens: 500)
        let lines = result
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return lines.isEmpty ? ["會議已結束，尚無足夠內容產生摘要"] : Array(lines.prefix(5))
    }

    // ═════════════════════════════════════════════════
    // MARK: 2. Action Items 擷取
    // ═════════════════════════════════════════════════

    func extractActionItems(transcript: String) async -> [ActionItem] {
        // ① 本地快速偵測（零延遲）
        var localItems = extractActionItemsLocally(transcript)

        // ② Claude 深度擷取
        let claudeItems = await extractActionItemsWithClaude(transcript)

        // 合併去重
        for ci in claudeItems {
            let isDuplicate = localItems.contains { existing in
                existing.content.localizedCaseInsensitiveContains(String(ci.content.prefix(15)))
            }
            if !isDuplicate { localItems.append(ci) }
        }

        return localItems
    }

    /// 本地 regex 快速偵測
    private func extractActionItemsLocally(_ transcript: String) -> [ActionItem] {
        let patterns: [(pattern: String, assignee: String?)] = [
            // 中文
            ("我們會.{5,40}", "我方"),
            ("下一步.{5,40}", nil),
            ("我來.{5,40}", "我方"),
            ("麻煩你.{5,40}", "對方"),
            ("請你.{3,40}", "對方"),
            ("會後.{5,40}", nil),
            ("需要準備.{5,40}", nil),
            ("我等等.{5,40}", "我方"),
            ("我傳給你.{3,30}", "我方"),
            // English
            ("I will .{5,40}", "我方"),
            ("I'll .{5,40}", "我方"),
            ("we will .{5,40}", nil),
            ("we'll .{5,40}", nil),
            ("next step.{3,40}", nil),
            ("action item.{3,40}", nil),
            ("follow up.{3,40}", nil),
            ("let me .{5,40}", "我方"),
            ("could you .{5,40}", "對方"),
            ("please send .{5,40}", "對方"),
        ]

        var items: [ActionItem] = []
        let text = transcript.lowercased()

        for (pattern, assignee) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                for match in matches.prefix(3) {
                    if let range = Range(match.range, in: text) {
                        let content = String(text[range])
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .prefix(60)
                        items.append(ActionItem(
                            content: String(content), assignee: assignee,
                            dueHint: nil, source: .transcript
                        ))
                    }
                }
            }
        }

        return Array(items.prefix(10))  // 最多 10 條
    }

    /// Claude 深度擷取
    private func extractActionItemsWithClaude(_ transcript: String) async -> [ActionItem] {
        let trimmed = String(transcript.suffix(4000))
        guard trimmed.count > 50 else { return [] }

        let prompt = """
        從以下會議逐字稿擷取 Action Items。

        規則：
        - 每行一個 Action Item，格式：[負責人] 內容 (時限)
        - 負責人只寫「我方」或「對方」或「待定」
        - 時限只寫「本週」「下週」「無明確時限」
        - 最多 5 條
        - 用繁體中文
        - 只輸出 Action Items，不要其他文字

        逐字稿：
        \(trimmed)
        """

        let result = await callClaude(prompt: prompt, maxTokens: 400)
        return result
            .split(separator: "\n")
            .compactMap { line -> ActionItem? in
                let s = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !s.isEmpty else { return nil }

                // 解析 [負責人] 內容 (時限)
                var assignee: String? = nil
                var dueHint: String? = nil
                var content = s

                if let assigneeMatch = s.range(of: "\\[(.+?)\\]", options: .regularExpression) {
                    let tag = String(s[assigneeMatch]).replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
                    if tag.contains("我方") { assignee = "我方" }
                    else if tag.contains("對方") { assignee = "對方" }
                    content = s.replacingCharacters(in: assigneeMatch, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if let dueMatch = content.range(of: "\\((.+?)\\)", options: .regularExpression) {
                    dueHint = String(content[dueMatch]).replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
                    content = content.replacingCharacters(in: dueMatch, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                // 清除 - 開頭
                if content.hasPrefix("- ") { content = String(content.dropFirst(2)) }

                return ActionItem(content: content, assignee: assignee, dueHint: dueHint, source: .claude)
            }
    }

    // ═════════════════════════════════════════════════
    // MARK: 3. Markdown 報告產生
    // ═════════════════════════════════════════════════

    func generateMarkdown(report: MeetingReport) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        let startStr = report.startTime.map { df.string(from: $0) } ?? "N/A"
        let endStr = df.string(from: report.endTime)
        let durationStr = report.duration.map { "\(Int($0 / 60)) 分鐘" } ?? "N/A"

        var md = """
        # 📝 \(report.title)

        | 項目 | 內容 |
        |------|------|
        | 開始 | \(startStr) |
        | 結束 | \(endStr) |
        | 時長 | \(durationStr) |
        | 語言 | \(report.language) |

        ## 🎯 會議摘要


        """

        for (i, point) in report.summary.enumerated() {
            md += "\(i + 1). \(point)\n"
        }

        // Action Items
        if !report.actionItems.isEmpty {
            md += "\n## ✅ Action Items\n\n"
            for item in report.actionItems {
                let assignee = item.assignee ?? "待定"
                let due = item.dueHint.map { " | → \($0)" } ?? ""
                let src = item.source == .claude ? "🤖" : "📝"
                md += "- [ ] **[\(assignee)]** \(item.content)\(due) \(src)\n"
            }
        }

        // Talking Points
        md += "\n## 📋 Talking Points (\(report.tpStats.completed)/\(report.tpStats.total))\n\n"
        for tp in report.talkingPoints {
            let icon: String
            switch tp.status {
            case .completed: icon = "✅"; case .skipped: icon = "⏭️"
            case .inProgress: icon = "🔄"; case .pending: icon = "⬜"
            }
            md += "- \(icon) **[\(tp.priority.rawValue)]** \(tp.content)\n"
            if let speech = tp.detectedSpeech {
                md += "  - _偵測: \(speech)_\n"
            }
        }

        // 統計
        md += """

        ## 📊 會議統計

        | 指標 | 值 |
        |------|-----|
        | 本地匹配 | \(report.stats.localMatches) |
        | RAG 查詢 | \(report.stats.notebookLMQueries) |
        | Claude 查詢 | \(report.stats.claudeQueries) |
        | 策略分析 | \(report.stats.strategyAnalyses) |
        | 平均延遲 | \(String(format: "%.0f", report.stats.averageClaudeLatencyMs))ms |
        | AI 成本 | $\(String(format: "%.2f", report.stats.estimatedClaudeCost)) |

        """

        // 逐字稿
        md += "\n## 🎤 逐字稿\n\n"
        if report.transcript.isEmpty {
            md += "_（無逐字稿）_\n"
        } else {
            // 對方/我方 分色標記
            let lines = report.transcript.split(separator: "\n")
            for line in lines {
                let s = String(line)
                if s.hasPrefix("[對方]") {
                    md += "> \(s)\n\n"
                } else if s.hasPrefix("[我方]") {
                    md += "**\(s)**\n\n"
                } else {
                    md += "\(s)\n\n"
                }
            }
        }

        // AI 卡片
        if !report.cards.isEmpty {
            md += "## 🧠 AI 卡片 (\(report.cards.count))\n\n"
            for (i, card) in report.cards.enumerated() {
                let emoji: String
                switch card.type {
                case .qaMatch: emoji = "🔵"; case .aiGenerated: emoji = "🟣"
                case .strategy: emoji = "🟠"; case .warning: emoji = "⚠️"
                }
                md += "### \(emoji) #\(i + 1) \(card.title)\n\n"
                md += "> \(String(format: "%.0f", card.latencyMs))ms | \(String(format: "%.0f", card.confidence * 100))%\n\n"
                md += "\(card.content)\n\n"
            }
        }

        md += "---\n\n_Generated by MeetingCopilot v4.3 © Reality Matrix Inc._\n"
        return md
    }

    // ═════════════════════════════════════════════════
    // MARK: 4. 匯出到 Notion Page
    // ═════════════════════════════════════════════════

    func exportToNotion(report: MeetingReport, parentPageId: String? = nil) async -> (success: Bool, url: String?) {
        guard let notionKey = KeychainManager.notionAPIKey else {
            print("❌ Notion API Key 未設定")
            return (false, nil)
        }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        let dateStr = report.startTime.map { df.string(from: $0) } ?? df.string(from: report.endTime)
        let pageTitle = "📝 \(report.title) - \(dateStr)"

        // 組裝 Notion blocks
        var blocks: [[String: Any]] = []

        // 摘要
        blocks.append(notionHeading2("🎯 會議摘要"))
        for point in report.summary {
            blocks.append(notionBullet(point))
        }

        // Action Items
        if !report.actionItems.isEmpty {
            blocks.append(notionHeading2("✅ Action Items"))
            for item in report.actionItems {
                let assignee = item.assignee ?? "待定"
                let due = item.dueHint.map { " → \($0)" } ?? ""
                blocks.append(notionToDo("[\(assignee)] \(item.content)\(due)", checked: false))
            }
        }

        // TP
        blocks.append(notionHeading2("📋 Talking Points (\(report.tpStats.completed)/\(report.tpStats.total))"))
        for tp in report.talkingPoints {
            let icon: String
            switch tp.status {
            case .completed: icon = "✅"; case .skipped: icon = "⏭️"
            case .inProgress: icon = "🔄"; case .pending: icon = "⬜"
            }
            blocks.append(notionBullet("\(icon) [\(tp.priority.rawValue)] \(tp.content)"))
        }

        // 統計
        blocks.append(notionHeading2("📊 統計"))
        blocks.append(notionParagraph(
            "本地: \(report.stats.localMatches) | RAG: \(report.stats.notebookLMQueries) | Claude: \(report.stats.claudeQueries) | 策略: \(report.stats.strategyAnalyses) | 延遲: \(String(format: "%.0f", report.stats.averageClaudeLatencyMs))ms | 成本: $\(String(format: "%.2f", report.stats.estimatedClaudeCost))"
        ))

        // Notion API: Create Page
        var body: [String: Any] = [
            "children": blocks,
            "properties": [
                "title": [
                    ["type": "text", "text": ["content": pageTitle]]
                ]
            ]
        ]

        // 如果有 parent page，創建為子 page。否則創建為獨立 page（需要 Database 或 parent）
        if let parentId = parentPageId, !parentId.isEmpty {
            body["parent"] = ["page_id": parentId]
        } else {
            // 嘗試搜尋「MeetingCopilot」 page 作為 parent
            let parentResult = await findNotionParentPage(apiKey: notionKey)
            if let pid = parentResult {
                body["parent"] = ["page_id": pid]
            } else {
                // 無 parent，創建為頂層 page（需要 workspace-level integration）
                body["parent"] = ["page_id": ""]
                print("⚠️ 找不到 MeetingCopilot parent page，嘗試建立頂層 page")
            }
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            return (false, nil)
        }

        var request = URLRequest(url: URL(string: "https://api.notion.com/v1/pages")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(notionKey)", forHTTPHeaderField: "Authorization")
        request.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let url = json["url"] as? String {
                    print("✅ Notion page 建立成功: \(url)")
                    return (true, url)
                }
                return (true, nil)
            } else {
                let errorMsg = String(data: data, encoding: .utf8) ?? "unknown error"
                print("❌ Notion API 錯誤: \(errorMsg)")
                return (false, nil)
            }
        } catch {
            print("❌ Notion 網路錯誤: \(error.localizedDescription)")
            return (false, nil)
        }
    }

    // 搜尋「MeetingCopilot」或「會議記錄」 page 作為 parent
    private func findNotionParentPage(apiKey: String) async -> String? {
        let searchBody: [String: Any] = [
            "query": "MeetingCopilot",
            "filter": ["property": "object", "value": "page"],
            "page_size": 1
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: searchBody) else { return nil }

        var request = URLRequest(url: URL(string: "https://api.notion.com/v1/search")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let results = json["results"] as? [[String: Any]],
               let first = results.first,
               let id = first["id"] as? String {
                return id
            }
        } catch { }
        return nil
    }

    // ═════════════════════════════════════════════════
    // MARK: Claude API
    // ═════════════════════════════════════════════════

    private func callClaude(prompt: String, maxTokens: Int = 500) async -> String {
        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": maxTokens,
            "messages": [["role": "user", "content": prompt]]
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return "" }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(claudeAPIKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let content = json["content"] as? [[String: Any]],
               let first = content.first,
               let text = first["text"] as? String {
                return text
            }
        } catch {
            print("❌ Claude API 錯誤: \(error.localizedDescription)")
        }
        return ""
    }

    // ═════════════════════════════════════════════════
    // MARK: Notion Block Helpers
    // ═════════════════════════════════════════════════

    private func notionHeading2(_ text: String) -> [String: Any] {
        return [
            "object": "block",
            "type": "heading_2",
            "heading_2": [
                "rich_text": [["type": "text", "text": ["content": text]]]
            ]
        ]
    }

    private func notionBullet(_ text: String) -> [String: Any] {
        return [
            "object": "block",
            "type": "bulleted_list_item",
            "bulleted_list_item": [
                "rich_text": [["type": "text", "text": ["content": text]]]
            ]
        ]
    }

    private func notionToDo(_ text: String, checked: Bool) -> [String: Any] {
        return [
            "object": "block",
            "type": "to_do",
            "to_do": [
                "rich_text": [["type": "text", "text": ["content": text]]],
                "checked": checked
            ]
        ]
    }

    private func notionParagraph(_ text: String) -> [String: Any] {
        return [
            "object": "block",
            "type": "paragraph",
            "paragraph": [
                "rich_text": [["type": "text", "text": ["content": text]]]
            ]
        ]
    }
}
