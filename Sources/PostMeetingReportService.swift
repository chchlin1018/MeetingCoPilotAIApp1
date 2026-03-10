// ═══════════════════════════════════════════════════════════════════════════
// PostMeetingReportService.swift
// MeetingCopilot v4.3 — 會後報告產生器
// ═══════════════════════════════════════════════════════════════════════════
//
//  1. Claude 會議摘要（3-5 個要點）
//  2. Action Items 自動擷取（本地 regex + Claude 深度）
//  3. Markdown / TXT 報告產生
//  4. 匯出到 Notion page
//
//  Platform: macOS 14.0+
// ═══════════════════════════════════════════════════════════════════════════

import Foundation

// MARK: - Action Item

struct ActionItem: Identifiable, Sendable {
    let id = UUID()
    let content: String
    let owner: String?          // 「我方」/「對方」/「待定」
    let deadline: String?       // 「本週」「下週一」/ nil
    let source: Source

    enum Source: String, Sendable {
        case transcript = "transcript"
        case claude = "claude"
    }
}

// MARK: - Meeting Report

struct MeetingReport: Sendable {
    let title: String
    let startTime: Date?
    let endTime: Date
    let duration: String
    let language: String
    let summary: [String]
    let actionItems: [ActionItem]
    let transcript: String
    let talkingPoints: [TalkingPoint]
    let tpStats: TPStats
    let cards: [AICard]
    let stats: SessionStats
}

// MARK: - Post Meeting Report Service

final class PostMeetingReportService: Sendable {

    init() {}

    // ═════════════════════════════════════════════════
    // MARK: 1. Claude 會議摘要
    // ═════════════════════════════════════════════════

    func generateSummary(transcript: String, title: String, tpStats: TPStats) async -> [String] {
        let trimmed = String(transcript.suffix(6000))
        guard trimmed.count > 30 else { return ["會議內容不足，無法產生摘要"] }

        let prompt = """
        你是會議摘要助手。會議主題：「\(title)」
        根據逐字稿產生 3-5 個會議要點：
        - 每個要點 1 行，不超過 40 字
        - 包含具體數字/決策/共識
        - 用繁體中文
        - 只輸出要點，每行一個，不要編號
        - TP: \(tpStats.completed)/\(tpStats.total)，MUST: \(tpStats.mustCompleted)/\(tpStats.mustTotal)

        逐字稿：
        \(trimmed)
        """

        let result = await callClaude(prompt: prompt, maxTokens: 500)
        let lines = result
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { line -> String in
                // 清除開頭編號
                var s = line
                if let range = s.range(of: "^\\d+[.\\)\\uff0e]\\s*", options: .regularExpression) {
                    s = String(s[range.upperBound...])
                }
                if s.hasPrefix("- ") { s = String(s.dropFirst(2)) }
                return s
            }
            .filter { !$0.isEmpty }
        return lines.isEmpty ? ["會議已結束"] : Array(lines.prefix(5))
    }

    // ═════════════════════════════════════════════════
    // MARK: 2. Action Items
    // ═════════════════════════════════════════════════

    func extractActionItems(from transcript: String) async -> [ActionItem] {
        var local = extractLocally(transcript)
        let claude = await extractWithClaude(transcript)
        for ci in claude {
            let dup = local.contains { $0.content.localizedCaseInsensitiveContains(String(ci.content.prefix(15))) }
            if !dup { local.append(ci) }
        }
        return local
    }

    private func extractLocally(_ text: String) -> [ActionItem] {
        let patterns: [(String, String?)] = [
            ("我們會.{5,40}", "我方"), ("下一步.{5,40}", nil), ("我來.{5,40}", "我方"),
            ("麻煩你.{5,40}", "對方"), ("請你.{3,40}", "對方"), ("會後.{5,40}", nil),
            ("需要準備.{5,40}", nil), ("我傳給你.{3,30}", "我方"),
            ("I will .{5,40}", "我方"), ("I'll .{5,40}", "我方"),
            ("we will .{5,40}", nil), ("we'll .{5,40}", nil),
            ("next step.{3,40}", nil), ("follow up.{3,40}", nil),
            ("let me .{5,40}", "我方"), ("could you .{5,40}", "對方"),
        ]
        var items: [ActionItem] = []
        let lower = text.lowercased()
        for (p, owner) in patterns {
            guard let regex = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) else { continue }
            let matches = regex.matches(in: lower, range: NSRange(lower.startIndex..., in: lower))
            for m in matches.prefix(2) {
                if let range = Range(m.range, in: lower) {
                    let content = String(lower[range]).trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)
                    items.append(ActionItem(content: String(content), owner: owner, deadline: nil, source: .transcript))
                }
            }
        }
        return Array(items.prefix(8))
    }

    private func extractWithClaude(_ transcript: String) async -> [ActionItem] {
        let trimmed = String(transcript.suffix(4000))
        guard trimmed.count > 50 else { return [] }

        let prompt = """
        從以下會議逐字稿擷取 Action Items。
        每行格式：[負責人] 內容 (時限)
        負責人只寫「我方」或「對方」或「待定」
        時限只寫「本週」「下週」「無明確時限」
        最多 5 條，繁體中文，只輸出 Action Items

        逐字稿：
        \(trimmed)
        """

        return await callClaude(prompt: prompt, maxTokens: 400)
            .split(separator: "\n")
            .compactMap { line -> ActionItem? in
                let s = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !s.isEmpty else { return nil }
                var owner: String? = nil
                var deadline: String? = nil
                var content = s
                if s.hasPrefix("- ") { content = String(s.dropFirst(2)) }
                if let r = content.range(of: "\\[(.+?)\\]", options: .regularExpression) {
                    let tag = String(content[r]).replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
                    if tag.contains("我") { owner = "我方" } else if tag.contains("對") { owner = "對方" } else { owner = "待定" }
                    content = content.replacingCharacters(in: r, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if let r = content.range(of: "\\((.+?)\\)", options: .regularExpression) {
                    deadline = String(content[r]).replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
                    content = content.replacingCharacters(in: r, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return ActionItem(content: content, owner: owner, deadline: deadline, source: .claude)
            }
    }

    // ═════════════════════════════════════════════════
    // MARK: 3. Markdown 報告
    // ═════════════════════════════════════════════════

    func buildMarkdown(report: MeetingReport) -> String {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm"
        let startStr = report.startTime.map { df.string(from: $0) } ?? "N/A"
        let endStr = df.string(from: report.endTime)

        var md = """
        # 📝 \(report.title)

        | 項目 | 內容 |
        |------|------|
        | 開始 | \(startStr) |
        | 結束 | \(endStr) |
        | 時長 | \(report.duration) |
        | 語言 | \(report.language) |

        ## 🎯 會議摘要


        """
        for (i, p) in report.summary.enumerated() { md += "\(i + 1). \(p)\n" }

        if !report.actionItems.isEmpty {
            md += "\n## ✅ Action Items\n\n"
            for item in report.actionItems {
                let o = item.owner ?? "待定"
                let d = item.deadline.map { " | → \($0)" } ?? ""
                let src = item.source == .claude ? "🤖" : "📝"
                md += "- [ ] **[\(o)]** \(item.content)\(d) \(src)\n"
            }
        }

        md += "\n## 📋 Talking Points (\(report.tpStats.completed)/\(report.tpStats.total))\n\n"
        for tp in report.talkingPoints {
            let icon: String
            switch tp.status { case .completed: icon = "✅"; case .skipped: icon = "⏭️"; case .inProgress: icon = "🔄"; case .pending: icon = "⬜" }
            md += "- \(icon) **[\(tp.priority.rawValue)]** \(tp.content)\n"
            if let speech = tp.detectedSpeech { md += "  - _偵測: \(speech)_\n" }
        }

        md += """

        ## 📊 統計

        | 指標 | 值 |
        |------|-----|
        | 本地匹配 | \(report.stats.localMatches) |
        | RAG | \(report.stats.notebookLMQueries) |
        | Claude | \(report.stats.claudeQueries) |
        | 策略 | \(report.stats.strategyAnalyses) |
        | 延遲 | \(String(format: "%.0f", report.stats.averageClaudeLatencyMs))ms |
        | 成本 | $\(String(format: "%.2f", report.stats.estimatedClaudeCost)) |


        """

        md += "## 🎤 逐字稿\n\n"
        if report.transcript.isEmpty { md += "_（無逐字稿）_\n" }
        else {
            for line in report.transcript.split(separator: "\n") {
                let s = String(line)
                if s.hasPrefix("[對方]") { md += "> \(s)\n\n" }
                else if s.hasPrefix("[我方]") { md += "**\(s)**\n\n" }
                else { md += "\(s)\n\n" }
            }
        }

        if !report.cards.isEmpty {
            md += "## 🧠 AI 卡片 (\(report.cards.count))\n\n"
            for (i, card) in report.cards.enumerated() {
                let e: String
                switch card.type { case .qaMatch: e = "🔵"; case .aiGenerated: e = "🟣"; case .strategy: e = "🟠"; case .warning: e = "⚠️" }
                md += "### \(e) #\(i + 1) \(card.title)\n\n> \(String(format: "%.0f", card.latencyMs))ms | \(String(format: "%.0f", card.confidence * 100))%\n\n\(card.content)\n\n"
            }
        }

        md += "---\n\n_Generated by MeetingCopilot v4.3 © Reality Matrix Inc._\n"
        return md
    }

    // ═════════════════════════════════════════════════
    // MARK: 3b. TXT 報告
    // ═════════════════════════════════════════════════

    func buildTXT(report: MeetingReport) -> String {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let startStr = report.startTime.map { df.string(from: $0) } ?? "N/A"
        let endStr = df.string(from: report.endTime)

        var lines: [String] = []
        lines.append("══════════════════════════════════════════════════")
        lines.append("  MeetingCopilot 會議報告")
        lines.append("══════════════════════════════════════════════════")
        lines.append("")
        lines.append("會議名稱: \(report.title)")
        lines.append("開始時間: \(startStr)")
        lines.append("結束時間: \(endStr)")
        lines.append("會議時長: \(report.duration)")
        lines.append("語音辨識: \(report.language)")

        lines.append("")
        lines.append("── 會議摘要 ──────────────────────────────────────────")
        for (i, p) in report.summary.enumerated() { lines.append("  \(i + 1). \(p)") }

        if !report.actionItems.isEmpty {
            lines.append("")
            lines.append("── Action Items ──────────────────────────────────────")
            for item in report.actionItems {
                let o = item.owner ?? "待定"
                let d = item.deadline.map { " → \($0)" } ?? ""
                lines.append("  ☐ [\(o)] \(item.content)\(d)")
            }
        }

        lines.append("")
        lines.append("── Talking Points (\(report.tpStats.completed)/\(report.tpStats.total)) ──")
        for tp in report.talkingPoints {
            let icon: String
            switch tp.status { case .completed: icon = "✅"; case .skipped: icon = "⏭️"; case .inProgress: icon = "🔄"; case .pending: icon = "⬜" }
            lines.append("  \(icon) [\(tp.priority.rawValue)] \(tp.content)")
            if let speech = tp.detectedSpeech { lines.append("     偵測: \(speech)") }
        }

        lines.append("")
        lines.append("── 統計 ──────────────────────────────────────────────")
        lines.append("本地: \(report.stats.localMatches) | RAG: \(report.stats.notebookLMQueries) | Claude: \(report.stats.claudeQueries) | 策略: \(report.stats.strategyAnalyses)")
        lines.append("延遲: \(String(format: "%.0f", report.stats.averageClaudeLatencyMs))ms | 成本: $\(String(format: "%.2f", report.stats.estimatedClaudeCost))")

        lines.append("")
        lines.append("── 逐字稿 ────────────────────────────────────────────")
        lines.append(report.transcript.isEmpty ? "（無逐字稿）" : report.transcript)

        if !report.cards.isEmpty {
            lines.append("")
            lines.append("── AI 卡片 (\(report.cards.count)) ─────────────────────────────────")
            for (i, card) in report.cards.enumerated() {
                let e: String
                switch card.type { case .qaMatch: e = "🔵"; case .aiGenerated: e = "🟣"; case .strategy: e = "🟠"; case .warning: e = "⚠️" }
                lines.append("")
                lines.append("\(e) #\(i + 1) \(card.title)")
                lines.append("   \(String(format: "%.0f", card.latencyMs))ms | \(String(format: "%.0f", card.confidence * 100))%")
                lines.append("   \(card.content)")
            }
        }

        lines.append("")
        lines.append("══════════════════════════════════════════════════")
        lines.append("  Generated by MeetingCopilot v4.3")
        lines.append("  © Reality Matrix Inc.")
        lines.append("══════════════════════════════════════════════════")
        return lines.joined(separator: "\n")
    }

    // ═════════════════════════════════════════════════
    // MARK: 4. Notion 匯出
    // ═════════════════════════════════════════════════

    func exportToNotion(report: MeetingReport) async -> (success: Bool, url: String?) {
        guard let notionKey = KeychainManager.notionAPIKey else {
            print("❌ Notion API Key 未設定")
            return (false, nil)
        }

        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm"
        let dateStr = report.startTime.map { df.string(from: $0) } ?? df.string(from: report.endTime)
        let pageTitle = "📝 \(report.title) - \(dateStr)"

        var blocks: [[String: Any]] = []

        blocks.append(heading2("🎯 會議摘要"))
        for p in report.summary { blocks.append(bullet(p)) }

        if !report.actionItems.isEmpty {
            blocks.append(heading2("✅ Action Items"))
            for item in report.actionItems {
                let o = item.owner ?? "待定"
                let d = item.deadline.map { " → \($0)" } ?? ""
                blocks.append(toDo("[\(o)] \(item.content)\(d)", checked: false))
            }
        }

        blocks.append(heading2("📋 Talking Points (\(report.tpStats.completed)/\(report.tpStats.total))"))
        for tp in report.talkingPoints {
            let icon: String
            switch tp.status { case .completed: icon = "✅"; case .skipped: icon = "⏭️"; case .inProgress: icon = "🔄"; case .pending: icon = "⬜" }
            blocks.append(bullet("\(icon) [\(tp.priority.rawValue)] \(tp.content)"))
        }

        blocks.append(heading2("📊 統計"))
        blocks.append(paragraph("本地: \(report.stats.localMatches) | RAG: \(report.stats.notebookLMQueries) | Claude: \(report.stats.claudeQueries) | 策略: \(report.stats.strategyAnalyses) | 延遲: \(String(format: "%.0f", report.stats.averageClaudeLatencyMs))ms | 成本: $\(String(format: "%.2f", report.stats.estimatedClaudeCost))"))

        // 搜尋 parent page
        let parentId = await findParentPage(apiKey: notionKey)

        var body: [String: Any] = [
            "children": blocks,
            "properties": ["title": [["type": "text", "text": ["content": pageTitle]]]]
        ]
        if let pid = parentId {
            body["parent"] = ["page_id": pid]
        } else {
            print("⚠️ 找不到 parent page，無法建立 Notion page")
            return (false, nil)
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return (false, nil) }

        var request = URLRequest(url: URL(string: "https://api.notion.com/v1/pages")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(notionKey)", forHTTPHeaderField: "Authorization")
        request.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let url = json["url"] as? String {
                    print("✅ Notion page: \(url)")
                    return (true, url)
                }
                return (true, nil)
            } else {
                let err = String(data: data, encoding: .utf8) ?? ""
                print("❌ Notion API: \(err.prefix(200))")
                return (false, nil)
            }
        } catch {
            print("❌ Notion: \(error.localizedDescription)")
            return (false, nil)
        }
    }

    private func findParentPage(apiKey: String) async -> String? {
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
               let first = results.first, let id = first["id"] as? String { return id }
        } catch { }
        return nil
    }

    // ═ Claude API ═

    private func callClaude(prompt: String, maxTokens: Int = 500) async -> String {
        guard let apiKey = KeychainManager.claudeAPIKey else { return "" }
        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514", "max_tokens": maxTokens,
            "messages": [["role": "user", "content": prompt]]
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return "" }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let content = json["content"] as? [[String: Any]],
               let first = content.first, let text = first["text"] as? String { return text }
        } catch { print("❌ Claude: \(error.localizedDescription)") }
        return ""
    }

    // ═ Notion Block Helpers ═

    private func heading2(_ text: String) -> [String: Any] {
        ["object": "block", "type": "heading_2",
         "heading_2": ["rich_text": [["type": "text", "text": ["content": text]]]]]
    }
    private func bullet(_ text: String) -> [String: Any] {
        ["object": "block", "type": "bulleted_list_item",
         "bulleted_list_item": ["rich_text": [["type": "text", "text": ["content": text]]]]]
    }
    private func toDo(_ text: String, checked: Bool) -> [String: Any] {
        ["object": "block", "type": "to_do",
         "to_do": ["rich_text": [["type": "text", "text": ["content": text]]], "checked": checked]]
    }
    private func paragraph(_ text: String) -> [String: Any] {
        ["object": "block", "type": "paragraph",
         "paragraph": ["rich_text": [["type": "text", "text": ["content": text]]]]]
    }
}
