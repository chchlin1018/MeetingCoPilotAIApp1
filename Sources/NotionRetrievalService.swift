// ═══════════════════════════════════════════════════════════════════════════
// NotionRetrievalService.swift
// MeetingCopilot v4.3 — Notion API 知識檢索服務（取代 NotebookLM Bridge）
// ═══════════════════════════════════════════════════════════════════════════
//
//  為什麼用 Notion 取代 NotebookLM：
//  - Notion 有官方 REST API，穩定且不會因 DOM 變動而壞掉
//  - 你平時就在用 Notion，會前資料已經在裡面
//  - 不需要 Node.js bridge-server.js，Swift 直接呼叫
//  - 不需要每場會議重新上傳文件
//
//  運作流程：
//  1. 偵測到對方提問
//  2. POST /v1/search 搜尋 Notion 中的相關 page
//  3. GET /v1/blocks/{id}/children 取得 page 內容
//  4. 組成 context 段落 → 餵給 Claude
//
//  多關鍵字展開：
//  - 對方問「成本效益」→ 展開搜尋 ["ROI", "投資", "成本", "payback"]
//  - 合併多次搜尋結果，提高命中率
//
//  Platform: macOS 14.0+
// ═══════════════════════════════════════════════════════════════════════════

import Foundation

// MARK: - Notion 查詢結果

struct NotionRetrievalResult: Sendable, Identifiable {
    let id: UUID = UUID()
    let pageId: String
    let pageTitle: String
    let content: String
    let relevanceScore: Float
    let url: String?

    /// 格式化為 Claude context
    var asClaudeContext: String {
        "【Notion: \(pageTitle)】\n\(content)"
    }
}

// MARK: - Notion Service

actor NotionRetrievalService {

    private let apiKey: String
    private let apiVersion = "2022-06-28"
    private let baseURL = "https://api.notion.com/v1"
    private let timeout: TimeInterval = 5.0

    // 查詢快取（60 秒內不重複查詢）
    private var queryCache: [String: CachedResult] = [:]
    private let cacheTTL: TimeInterval = 60.0
    private struct CachedResult {
        let results: [NotionRetrievalResult]
        let timestamp: Date
    }

    // 關鍵字展開對照表（補強 Notion 關鍵字搜尋的不足）
    private let keywordExpansion: [String: [String]] = [
        "成本": ["ROI", "投資", "payback", "回收", "預算"],
        "ROI": ["成本", "效益", "投資報酬", "payback"],
        "競品": ["AVEVA", "差異", "比較", "competitor"],
        "AVEVA": ["競品", "Schneider", "差異"],
        "資安": ["ISO", "合規", "security", "隱私"],
        "時程": ["timeline", "導入", "implementation", "上線"],
        "架構": ["OpenUSD", "IDTF", "architecture", "整合"],
        "team": ["團隊", "經驗", "背景", "founder"],
    ]

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    var isAvailable: Bool {
        !apiKey.isEmpty
    }

    // ═════════════════════════════════════════════════
    // MARK: 核心查詢
    // ═════════════════════════════════════════════════

    /// 搜尋 Notion 並取得相關內容
    func query(question: String, maxResults: Int = 3) async -> [NotionRetrievalResult] {
        guard isAvailable else { return [] }

        // 快取檢查
        let cacheKey = question.prefix(50).lowercased().description
        if let cached = queryCache[cacheKey],
           Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            print("📝 Notion cache hit: \(cacheKey)")
            return cached.results
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        // ★ 多關鍵字展開搜尋
        let searchTerms = expandKeywords(from: question)
        var allPages: [(id: String, title: String, url: String?)] = []

        for term in searchTerms.prefix(3) {  // 最多搜 3 個關鍵字
            let pages = await searchPages(query: term, maxResults: 3)
            for page in pages {
                if !allPages.contains(where: { $0.id == page.id }) {
                    allPages.append(page)
                }
            }
        }

        // 取得每個 page 的內容
        var results: [NotionRetrievalResult] = []
        for page in allPages.prefix(maxResults) {
            let content = await getPageContent(pageId: page.id)
            guard !content.isEmpty else { continue }

            // 簡單相關度計算：檢查原始問題中的關鍵字在內容中出現的比例
            let score = calculateRelevance(question: question, content: content, title: page.title)
            results.append(NotionRetrievalResult(
                pageId: page.id, pageTitle: page.title,
                content: String(content.prefix(800)),  // 截斷避免過長
                relevanceScore: score, url: page.url
            ))
        }

        // 依相關度排序
        results.sort { $0.relevanceScore > $1.relevanceScore }
        results = Array(results.prefix(maxResults))

        let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        print("📝 Notion: \(results.count) results from \(allPages.count) pages, \(String(format: "%.0f", latency))ms")

        // 存快取
        queryCache[cacheKey] = CachedResult(results: results, timestamp: Date())
        cleanExpiredCache()

        return results
    }

    // ═════════════════════════════════════════════════
    // MARK: Notion API - Search
    // ═════════════════════════════════════════════════

    private func searchPages(query: String, maxResults: Int) async -> [(id: String, title: String, url: String?)] {
        guard let url = URL(string: "\(baseURL)/search") else { return [] }

        let body: [String: Any] = [
            "query": query,
            "filter": ["property": "object", "value": "page"],
            "page_size": maxResults,
            "sort": ["direction": "descending", "timestamp": "last_edited_time"]
        ]

        guard let data = try? await notionRequest(url: url, method: "POST", body: body),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return []
        }

        return results.compactMap { page -> (id: String, title: String, url: String?)? in
            guard let id = page["id"] as? String else { return nil }
            let title = extractTitle(from: page)
            let pageUrl = page["url"] as? String
            return (id: id, title: title, url: pageUrl)
        }
    }

    // ═════════════════════════════════════════════════
    // MARK: Notion API - Get Page Content
    // ═════════════════════════════════════════════════

    private func getPageContent(pageId: String) async -> String {
        let cleanId = pageId.replacingOccurrences(of: "-", with: "")
        guard let url = URL(string: "\(baseURL)/blocks/\(cleanId)/children?page_size=50") else { return "" }

        guard let data = try? await notionRequest(url: url, method: "GET"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let blocks = json["results"] as? [[String: Any]] else {
            return ""
        }

        return blocks.compactMap { extractBlockText($0) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    // ═════════════════════════════════════════════════
    // MARK: HTTP Request
    // ═════════════════════════════════════════════════

    private func notionRequest(url: URL, method: String, body: [String: Any]? = nil) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiVersion, forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout

        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("⚠️ Notion API error: HTTP \(code)")
            throw NotionError.apiFailed(code)
        }

        return data
    }

    // ═════════════════════════════════════════════════
    // MARK: JSON Parsing Helpers
    // ═════════════════════════════════════════════════

    /// 從 page object 取出標題
    private func extractTitle(from page: [String: Any]) -> String {
        guard let properties = page["properties"] as? [String: Any] else {
            return "Untitled"
        }
        // Notion page title 可能在不同的 property 中
        for (_, value) in properties {
            guard let prop = value as? [String: Any],
                  let type = prop["type"] as? String,
                  type == "title",
                  let titleArray = prop["title"] as? [[String: Any]] else { continue }
            return titleArray.compactMap { $0["plain_text"] as? String }.joined()
        }
        return "Untitled"
    }

    /// 從 block object 取出文字內容
    private func extractBlockText(_ block: [String: Any]) -> String {
        guard let type = block["type"] as? String,
              let content = block[type] as? [String: Any] else { return "" }

        // 常見 block 類型
        let textTypes = ["rich_text", "text"]
        for textKey in textTypes {
            if let richText = content[textKey] as? [[String: Any]] {
                let text = richText.compactMap { $0["plain_text"] as? String }.joined()
                if !text.isEmpty {
                    // 加上 block 類型標註
                    switch type {
                    case "heading_1", "heading_2", "heading_3":
                        return "## \(text)"
                    case "bulleted_list_item", "numbered_list_item":
                        return "• \(text)"
                    case "to_do":
                        let checked = (content["checked"] as? Bool) ?? false
                        return "\(checked ? "☑" : "☐") \(text)"
                    default:
                        return text
                    }
                }
            }
        }

        // table, code block 等
        if type == "code", let richText = content["rich_text"] as? [[String: Any]] {
            return richText.compactMap { $0["plain_text"] as? String }.joined()
        }

        return ""
    }

    // ═════════════════════════════════════════════════
    // MARK: 多關鍵字展開
    // ═════════════════════════════════════════════════

    private func expandKeywords(from question: String) -> [String] {
        let q = question.lowercased()
        var terms: [String] = [question]  // 原始問題永遠第一個

        // 從展開表找額外搜尋詞
        for (key, expansions) in keywordExpansion {
            if q.contains(key.lowercased()) {
                for exp in expansions {
                    if !terms.contains(where: { $0.lowercased() == exp.lowercased() }) {
                        terms.append(exp)
                    }
                }
            }
        }

        return terms
    }

    // ═════════════════════════════════════════════════
    // MARK: 相關度計算
    // ═════════════════════════════════════════════════

    private func calculateRelevance(question: String, content: String, title: String) -> Float {
        let q = question.lowercased()
        let c = (content + " " + title).lowercased()

        // 取得問題中的關鍵字（過濾停用詞）
        let stopWords: Set<String> = ["的", "了", "在", "是", "我", "有", "和", "就",
            "the", "is", "a", "an", "and", "or", "of", "to", "in", "for",
            "嗎", "什麼", "怎麼", "如何", "請問", "what", "how", "why", "can", "you"]

        let words = q.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .map(String.init)
            .filter { $0.count > 1 && !stopWords.contains($0) }

        guard !words.isEmpty else { return 0.5 }

        let hits = words.filter { c.contains($0) }.count
        let score = Float(hits) / Float(words.count)

        return min(0.95, score * 0.7 + 0.3)  // base 0.3 + keyword match
    }

    // ═════════════════════════════════════════════════
    // MARK: 格式化為 Claude Context
    // ═════════════════════════════════════════════════

    static func formatAsClaudeContext(_ results: [NotionRetrievalResult]) -> String {
        guard !results.isEmpty else { return "" }
        var ctx = "【Notion 即時查詢 — 相關文件段落】\n\n"
        for (i, r) in results.enumerated() {
            ctx += "[\(i + 1)] \(r.asClaudeContext)\n"
            ctx += "    (相關度: \(String(format: "%.0f", r.relevanceScore * 100))%)\n\n"
        }
        ctx += "【請基於以上 Notion 文件段落回答，不要編造文件中沒有的數據】"
        return ctx
    }

    // MARK: Cache

    private func cleanExpiredCache() {
        let now = Date()
        queryCache = queryCache.filter { now.timeIntervalSince($0.value.timestamp) < cacheTTL }
    }

    func clearCache() { queryCache.removeAll() }
}

// MARK: - Error

enum NotionError: Error, LocalizedError, Sendable {
    case notConfigured
    case apiFailed(Int)
    case timeout

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Notion API Key 未設定"
        case .apiFailed(let code): return "Notion API 失敗: HTTP \(code)"
        case .timeout: return "Notion 查詢逾時"
        }
    }
}
