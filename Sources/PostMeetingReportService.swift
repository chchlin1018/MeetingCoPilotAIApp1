// ═══════════════════════════════════════════════════════════════════════════
// PostMeetingReportService.swift
// MeetingCopilot v4.3 — 會後報告生成服務
// ═══════════════════════════════════════════════════════════════════════════
//
//  功能：
//  1. Claude AI 產生會議摘要（3-5 個要點）
//  2. Action Items 自動擷取（從逐字稿偵測）
//  3. Markdown 格式報告生成
//  4. Notion page 建立
//
//  Platform: macOS 14.0+
// ═══════════════════════════════════════════════════════════════════════════

import Foundation

// MARK: - Report Data

struct MeetingReport: Sendable {
    let title: String
    let startTime: Date?
    let endTime: Date
    let duration: String
    let language: String
    let summary: [String]                  // AI 產生的 3-5 個要點
    let actionItems: [ActionItem]          // 自動擷取的行動項目
    let transcript: String
    let talkingPoints: [TalkingPoint]
    let tpStats: TPStats
    let cards: [AICard]
    let stats: SessionStats
}

struct ActionItem: Identifiable, Sendable {
    let id = UUID()
    let content: String
    let owner: String?                     // 負責人（如果偵測到）
    let deadline: String?                  // 截止日（如果偵測到）
    let source: ActionItemSource

    enum ActionItemSource: String, Sendable {
        case transcript = "逐字稿"        // 從逐字稿偵測
        case aiSuggested = "AI 建議"     // Claude 建議
    }
}

// MARK: - Post Meeting Report Service

actor PostMeetingReportService {

    // ═════════════════════════════════════════════════
    // MARK: 1. Claude AI 會議摘要
    // ═════════════════════════════════════════════════

    func generateSummary(transcript: String, title: String, tpStats: TPStats) async -> [String] {
        guard let apiKey = KeychainManager.claudeAPIKey,
              !transcript.isEmpty else { return [] }

        let truncated = String(transcript.suffix(4000))  // 避免超過 token 限制

        let prompt = """
        你是會議摘要助手。請基於以下會議逐字稿，產生 3-5 個重要摘要要點。

        要求：
        - 每個要點一行，簡潔有力，不超過 30 字
        - 用「•」開頭
        - 包含具體數字或決策（如果有）
        - 使用與逐字稿相同的語言（中文或英文）
        - 只輸出要點，不要其他文字

        會議名稱：\(title)
        TP 完成: \(tpStats.completed)/\(tpStats.total)

        逐字稿：
        \(truncated)
        """

        do {
            let url = URL(string: "https://api.anthropic.com/v1/messages")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 15

            let body: [String: Any] = [
                "model": "claude-sonnet-4-20250514",
                "max_tokens": 500,
                "messages": [["role": "user", "content": prompt]]
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = json["content"] as? [[String: Any]],
                  let text = content.first?["text"] as? String else { return [] }

            // 解析要點（每行一個）
            return text.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .map { $0.hasPrefix("•") ? String($0.dropFirst().trimmingCharacters(in: .whitespaces)) : String($0) }
        } catch {
            print("⚠️ Summary generation failed: \(error)")
            return []
        }
    }

    // ═════════════════════════════════════════════════
    // MARK: 2. Action Items 自動擷取
    // ═════════════════════════════════════════════════

    func extractActionItems(from transcript: String) -> [ActionItem] {
        let patterns: [(pattern: String, isRegex: Bool)] = [
            // 中文模式
            ("我們會", false), ("我來", false), ("下一步", false),
            ("待辦", false), ("跟進", false), ("確認一下", false),
            ("會後整理", false), ("會後發", false), ("會後傳", false),
            ("請你", false), ("麻煩你", false), ("幫我", false),
            ("需要準備", false), ("安排一下", false),
            ("下週", false), ("明天", false), ("這週內", false),
            // 英文模式
            ("we will", false), ("we'll", false), ("I will", false), ("I'll", false),
            ("action item", false), ("follow up", false), ("next step", false),
            ("to-do", false), ("deadline", false), ("by friday", false),
            ("by next week", false), ("send me", false), ("please prepare", false),
            ("let's schedule", false), ("need to", false),
        ]

        let lines = transcript.split(separator: "\n").map(String.init)
        var items: [ActionItem] = []
        var seen = Set<String>()  // 避免重複

        for line in lines {
            let lower = line.lowercased()
            for (pattern, _) in patterns {
                if lower.contains(pattern.lowercased()) {
                    // 擷取包含關鍵字的句子
                    let cleaned = cleanActionItemText(line)
                    let key = String(cleaned.prefix(30)).lowercased()
                    guard !cleaned.isEmpty, cleaned.count > 5, !seen.contains(key) else { continue }
                    seen.insert(key)

                    let owner = extractOwner(from: cleaned)
                    let deadline = extractDeadline(from: cleaned)

                    items.append(ActionItem(
                        content: cleaned,
                        owner: owner,
                        deadline: deadline,
                        source: .transcript
                    ))
                    break  // 一行只擷取一次
                }
            }
        }

        return Array(items.prefix(10))  // 最多 10 個
    }

    private func cleanActionItemText(_ text: String) -> String {
        var cleaned = text
        // 移除說話者標籤
        if cleaned.hasPrefix("[對方] ") { cleaned = String(cleaned.dropFirst(5)) }
        if cleaned.hasPrefix("[我方] ") { cleaned = String(cleaned.dropFirst(5)) }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractOwner(from text: String) -> String? {
        let ownerPatterns = ["請你", "麻煩你", "我來", "我們", "I will", "I'll", "we will", "we'll"]
        let lower = text.lowercased()
        for p in ownerPatterns {
            if lower.contains(p.lowercased()) {
                if p.contains("你") { return "對方" }
                if p.contains("我") { return "我方" }
                if p.lowercased().contains("i ") { return "我方" }
                if p.lowercased().contains("we") { return "我們" }
            }
        }
        return nil
    }

    private func extractDeadline(from text: String) -> String? {
        let deadlinePatterns: [(String, String)] = [
            ("明天", "明天"), ("下週", "下週"), ("這週內", "這週內"),
            ("週五前", "週五前"), ("月底前", "月底前"),
            ("tomorrow", "tomorrow"), ("next week", "next week"),
            ("by friday", "by Friday"), ("end of month", "end of month"),
            ("asap", "ASAP"),
        ]
        let lower = text.lowercased()
        for (pattern, display) in deadlinePatterns {
            if lower.contains(pattern) { return display }
        }
        return nil
    }

    // ═════════════════════════════════════════════════
    // MARK: 3. Markdown 報告生成
    // ═════════════════════════════════════════════════

    func buildMarkdown(report: MeetingReport) -> String {
        let startStr = report.startTime.map { formatDateTime($0) } ?? "N/A"
        let endStr = formatDateTime(report.endTime)

        var md = """
        # \(report.title) — 會議記錄

        | 項目 | 內容 |
        |------|------|
        | 開始時間 | \(startStr) |
        | 結束時間 | \(endStr) |
        | 會議時長 | \(report.duration) |
        | 語音辨識 | \(report.language) |

        """

        // AI 摘要
        if !report.summary.isEmpty {
            md += "\n## 📝 AI 會議摘要\n\n"
            for point in report.summary {
                md += "- \(point)\n"
            }
        }

        // Action Items
        if !report.actionItems.isEmpty {
            md += "\n## ✅ Action Items\n\n"
            md += "| # | 內容 | 負責人 | 截止日 | 來源 |\n"
            md += "|---|------|--------|--------|------|\n"
            for (i, item) in report.actionItems.enumerated() {
                md += "| \(i + 1) | \(item.content.prefix(50)) | \(item.owner ?? "-") | \(item.deadline ?? "-") | \(item.source.rawValue) |\n"
            }
        }

        // TP 狀態
        md += "\n## 📋 Talking Points (\(report.tpStats.completed)/\(report.tpStats.total))\n\n"
        for tp in report.talkingPoints {
            let icon: String
            switch tp.status {
            case .completed: icon = "✅"
            case .skipped: icon = "⏭️"
            case .inProgress: icon = "🔄"
            case .pending: icon = "⬜"
            }
            md += "- \(icon) **[\(tp.priority.rawValue)]** \(tp.content)"
            if let speech = tp.detectedSpeech {
                md += " _(偵測: \(speech.prefix(30)))_"
            }
            md += "\n"
        }

        // 統計
        md += """

        ## 📊 統計

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
            md += "```\n\(report.transcript)\n```\n"
        }

        // AI 卡片
        if !report.cards.isEmpty {
            md += "\n## 🤖 AI 卡片 (\(report.cards.count) 張)\n\n"
            for (i, card) in report.cards.enumerated() {
                let emoji: String
                switch card.type {
                case .qaMatch: emoji = "🔵"
                case .aiGenerated: emoji = "🟣"
                case .strategy: emoji = "🟠"
                case .warning: emoji = "⚠️"
                }
                md += "### \(emoji) #\(i + 1) \(card.title)\n\n"
                md += "> \(String(format: "%.0f", card.latencyMs))ms | \(String(format: "%.0f", card.confidence * 100))%\n\n"
                md += "\(card.content)\n\n"
            }
        }

        md += "\n---\n_Generated by MeetingCopilot v4.3 — Reality Matrix Inc._\n"
        return md
    }

    // ═════════════════════════════════════════════════
    // MARK: 4. TXT 報告生成（已有功能強化版）
    // ═════════════════════════════════════════════════

    func buildTXT(report: MeetingReport) -> String {
        let startStr = report.startTime.map { formatDateTime($0) } ?? "N/A"
        let endStr = formatDateTime(report.endTime)

        var lines: [String] = []
        lines.append("══════════════════════════════════════════════════")
        lines.append("  MeetingCopilot 會議記錄")
        lines.append("══════════════════════════════════════════════════")
        lines.append("")
        lines.append("會議名稱: \(report.title)")
        lines.append("開始時間: \(startStr)")
        lines.append("結束時間: \(endStr)")
        lines.append("會議時長: \(report.duration)")
        lines.append("語音辨識: \(report.language)")

        // AI 摘要
        if !report.summary.isEmpty {
            lines.append("")
            lines.append("── AI 會議摘要 ────────────────────────────────────")
            for (i, point) in report.summary.enumerated() {
                lines.append("  \(i + 1). \(point)")
            }
        }

        // Action Items
        if !report.actionItems.isEmpty {
            lines.append("")
            lines.append("── Action Items (行動項目) ──────────────────────────")
            for (i, item) in report.actionItems.enumerated() {
                var line = "  \(i + 1). \(item.content)"
                if let owner = item.owner { line += " [負責: \(owner)]" }
                if let deadline = item.deadline { line += " [截止: \(deadline)]" }
                lines.append(line)
            }
        }

        // 統計 + TP + 逐字稿 + 卡片（同原有格式）
        lines.append("")
        lines.append("── 統計 ────────────────────────────────────────────")
        lines.append("本地匹配: \(report.stats.localMatches)")
        lines.append("RAG 查詢: \(report.stats.notebookLMQueries)")
        lines.append("Claude 查詢: \(report.stats.claudeQueries)")
        lines.append("策略分析: \(report.stats.strategyAnalyses)")
        lines.append("AI 成本: $\(String(format: "%.2f", report.stats.estimatedClaudeCost))")
        lines.append("")

        lines.append("── Talking Points (\(report.tpStats.completed)/\(report.tpStats.total)) ──")
        for tp in report.talkingPoints {
            let icon: String
            switch tp.status {
            case .completed: icon = "✅"; case .skipped: icon = "⏭️"
            case .inProgress: icon = "🔄"; case .pending: icon = "⬜"
            }
            lines.append("  \(icon) [\(tp.priority.rawValue)] \(tp.content)")
        }
        lines.append("")

        lines.append("── 逐字稿 ──────────────────────────────────────────")
        lines.append(report.transcript.isEmpty ? "（無逐字稿）" : report.transcript)
        lines.append("")

        if !report.cards.isEmpty {
            lines.append("── AI 卡片 (\(report.cards.count) 張) ───────────────────────")
            for (i, card) in report.cards.enumerated() {
                let e: String
                switch card.type {
                case .qaMatch: e = "🔵"; case .aiGenerated: e = "🟣"
                case .strategy: e = "🟠"; case .warning: e = "⚠️"
                }
                lines.append("\(e) #\(i + 1) \(card.title)")
                lines.append("   \(card.content)")
                lines.append("")
            }
        }

        lines.append("══════════════════════════════════════════════════")
        lines.append("  Generated by MeetingCopilot v4.3")
        lines.append("  \u00a9 Reality Matrix Inc.")
        lines.append("══════════════════════════════════════════════════")
        return lines.joined(separator: "\n")
    }

    // ═════════════════════════════════════════════════
    // MARK: 5. 匯出到 Notion Page
    // ═════════════════════════════════════════════════

    func exportToNotion(report: MeetingReport) async -> (success: Bool, url: String?) {
        guard let apiKey = KeychainManager.notionAPIKey else {
            print("⚠️ Notion API Key 未設定")
            return (false, nil)
        }

        let startStr = report.startTime.map { formatDateTime($0) } ?? "N/A"

        // 組裝 Notion blocks
        var children: [[String: Any]] = []

        // 標題資訊
        children.append(paragraphBlock("📅 \(startStr) | 時長: \(report.duration) | 語言: \(report.language)"))
        children.append(dividerBlock())

        // AI 摘要
        if !report.summary.isEmpty {
            children.append(heading2Block("📝 AI 會議摘要"))
            for point in report.summary {
                children.append(bulletBlock(point))
            }
        }

        // Action Items
        if !report.actionItems.isEmpty {
            children.append(heading2Block("✅ Action Items"))
            for item in report.actionItems {
                var text = item.content
                if let owner = item.owner { text += " [負責: \(owner)]" }
                if let deadline = item.deadline { text += " [截止: \(deadline)]" }
                children.append(todoBlock(text))
            }
        }

        // TP 狀態
        children.append(heading2Block("📋 Talking Points (\(report.tpStats.completed)/\(report.tpStats.total))"))
        for tp in report.talkingPoints {
            let icon: String
            switch tp.status {
            case .completed: icon = "✅"; case .skipped: icon = "⏭️"
            case .inProgress: icon = "🔄"; case .pending: icon = "⬜"
            }
            children.append(bulletBlock("\(icon) [\(tp.priority.rawValue)] \(tp.content)"))
        }

        // 統計
        children.append(heading2Block("📊 統計"))
        children.append(paragraphBlock("本地匹配: \(report.stats.localMatches) | RAG: \(report.stats.notebookLMQueries) | Claude: \(report.stats.claudeQueries) | 策略: \(report.stats.strategyAnalyses) | 成本: $\(String(format: "%.2f", report.stats.estimatedClaudeCost))"))

        // 逐字稿（截取前 2000 字避免太長）
        if !report.transcript.isEmpty {
            children.append(heading2Block("🎤 逐字稿"))
            children.append(codeBlock(String(report.transcript.prefix(2000))))
        }

        // 建立 Notion page
        do {
            let url = URL(string: "https://api.notion.com/v1/pages")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 15

            let body: [String: Any] = [
                "parent": ["type": "page_id", "page_id": ""],  // Notion workspace root
                "properties": [
                    "title": [
                        "title": [
                            ["type": "text", "text": ["content": "🎤 \(report.title) — \(startStr)"]]
                        ]
                    ]
                ],
                "children": children
            ]

            // 注意：如果沒有指定 parent page_id，Notion API 需要使用 database 或已知 page_id
            // 這裡用空 parent 會失敗，實際使用時需要設定目標 database/page
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return (false, nil)
            }

            if (200...299).contains(httpResponse.statusCode),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let pageUrl = json["url"] as? String {
                print("✅ Notion page created: \(pageUrl)")
                return (true, pageUrl)
            } else {
                // 嘗試 API v2：在 workspace root 建立
                print("⚠️ Notion API returned \(httpResponse.statusCode). 可能需要指定 parent page_id.")
                return (false, nil)
            }
        } catch {
            print("❌ Notion export failed: \(error)")
            return (false, nil)
        }
    }

    // MARK: Notion Block Helpers

    private func heading2Block(_ text: String) -> [String: Any] {
        ["object": "block", "type": "heading_2",
         "heading_2": ["rich_text": [["type": "text", "text": ["content": text]]]]]
    }
    private func paragraphBlock(_ text: String) -> [String: Any] {
        ["object": "block", "type": "paragraph",
         "paragraph": ["rich_text": [["type": "text", "text": ["content": text]]]]]
    }
    private func bulletBlock(_ text: String) -> [String: Any] {
        ["object": "block", "type": "bulleted_list_item",
         "bulleted_list_item": ["rich_text": [["type": "text", "text": ["content": text]]]]]
    }
    private func todoBlock(_ text: String) -> [String: Any] {
        ["object": "block", "type": "to_do",
         "to_do": ["rich_text": [["type": "text", "text": ["content": text]]], "checked": false]]
    }
    private func codeBlock(_ text: String) -> [String: Any] {
        ["object": "block", "type": "code",
         "code": ["rich_text": [["type": "text", "text": ["content": String(text.prefix(2000))]]], "language": "plain text"]]
    }
    private func dividerBlock() -> [String: Any] {
        ["object": "block", "type": "divider", "divider": [String: Any]()]
    }

    // MARK: Helpers

    private func formatDateTime(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; return f.string(from: date)
    }
}
