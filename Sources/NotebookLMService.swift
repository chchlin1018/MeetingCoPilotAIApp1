// ═══════════════════════════════════════════════════════════════════════════
// NotebookLMService.swift
// MeetingCopilot v4.1 — NotebookLM 即時查詢服務（三層管線第二層）
// ═══════════════════════════════════════════════════════════════════════════
//
//  ① 本地 Q&A 匹配 < 200ms     ← 預載的精確答案
//  ② NotebookLM RAG 查詢 1-3s   ← ★ 本檔案
//  ③ Claude + context 2-4s      ← 用 ② 的結果當 context 組織回答
//
//  為什麼需要這一層：
//  - 用戶會前在 NotebookLM 上傳 10-20 份 PDF/PPT/URL
//  - 不可能全部塞進 Claude context window
//  - NotebookLM RAG 已建好向量索引，1-3s 找到最相關段落
//  - 把 2-3 個段落餵給 Claude，產生有文件佐證的回答
//
//  V1.0: 透過本地 Node.js bridge（notebooklm-kit）呼叫
//  V2.0: 等 Google Enterprise API GA 後直接 REST call
//
//  Platform: macOS 14.0+
// ═══════════════════════════════════════════════════════════════════════════

import Foundation

// MARK: - NotebookLM 查詢結果

/// NotebookLM 回傳的相關段落
struct NotebookLMResult: Sendable, Identifiable {
    let id = UUID()
    let content: String              // 相關段落文字
    let sourceTitle: String          // 來源文件標題
    let sourceType: SourceType
    let relevanceScore: Float        // 0.0 ~ 1.0
    let pageOrSection: String?

    enum SourceType: String, Sendable, Codable {
        case pdf = "PDF"
        case pptx = "PPTX"
        case docx = "DOCX"
        case url = "URL"
        case gdoc = "Google Doc"
        case gsheet = "Google Sheet"
        case txt = "Text"
    }

    /// 格式化為 Claude context
    var asClaudeContext: String {
        var ctx = "【\(sourceTitle)"
        if let page = pageOrSection { ctx += " - \(page)" }
        ctx += "】\n\(content)"
        return ctx
    }
}

// MARK: - 查詢請求

struct NotebookLMQuery: Sendable {
    let question: String
    let notebookId: String
    let maxResults: Int
    let minRelevance: Float

    /// 會中場景預設：最多 3 段、最低相關度 0.5
    static func forMeeting(question: String, notebookId: String) -> NotebookLMQuery {
        NotebookLMQuery(question: question, notebookId: notebookId,
                        maxResults: 3, minRelevance: 0.5)
    }
}

// MARK: - 設定

struct NotebookLMConfig: Sendable {
    let notebookId: String
    let bridgeURL: String            // Node.js bridge URL
    let timeout: TimeInterval        // 會中最多等 3 秒
    let enabled: Bool

    static let `default` = NotebookLMConfig(
        notebookId: "", bridgeURL: "http://localhost:3210",
        timeout: 3.0, enabled: false
    )

    static func enabled(
        notebookId: String,
        bridgeURL: String = "http://localhost:3210"
    ) -> NotebookLMConfig {
        NotebookLMConfig(notebookId: notebookId, bridgeURL: bridgeURL,
                         timeout: 3.0, enabled: true)
    }
}

// MARK: - NotebookLM Service

actor NotebookLMService {

    private let config: NotebookLMConfig

    // 查詢快取（同一問題 60 秒內不重複查詢）
    private var queryCache: [String: CachedResult] = [:]
    private let cacheTTL: TimeInterval = 60.0

    private struct CachedResult {
        let results: [NotebookLMResult]
        let timestamp: Date
    }

    init(config: NotebookLMConfig = .default) {
        self.config = config
    }

    var isAvailable: Bool {
        config.enabled && !config.notebookId.isEmpty
    }

    // MARK: 核心查詢

    /// 即時查詢 NotebookLM，超時 3 秒自動放棄
    func query(_ query: NotebookLMQuery) async -> [NotebookLMResult] {
        guard isAvailable else { return [] }

        // 快取檢查
        let cacheKey = query.question.prefix(50).lowercased().description
        if let cached = queryCache[cacheKey],
           Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            print("📋 NotebookLM cache hit: \(cacheKey)")
            return cached.results
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            let results = try await withTimeout(seconds: config.timeout) {
                try await self.executeQuery(query)
            }
            let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            print("📚 NotebookLM: \(results.count) results, "
                + "\(String(format: "%.0f", latency))ms")

            queryCache[cacheKey] = CachedResult(results: results, timestamp: Date())
            cleanExpiredCache()
            return results
        } catch {
            let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            print("⚠️ NotebookLM failed (\(String(format: "%.0f", latency))ms): \(error)")
            return []
        }
    }

    // MARK: 格式化為 Claude Context

    /// 將查詢結果格式化為 Claude 可用的 context
    static func formatAsClaudeContext(_ results: [NotebookLMResult]) -> String {
        guard !results.isEmpty else { return "" }

        var context = "【NotebookLM 即時查詢 — 文件中最相關的段落】\n\n"
        for (i, result) in results.enumerated() {
            context += "[\(i + 1)] \(result.asClaudeContext)\n"
            context += "    (相關度: \(String(format: "%.0f", result.relevanceScore * 100))%)\n\n"
        }
        context += "【請基於以上文件段落回答，不要編造文件中沒有的數據】"
        return context
    }

    // MARK: 執行查詢（Node.js Bridge）

    /// POST http://localhost:3210/query
    /// Body: { notebookId, question, maxResults }
    /// Response: { results: [{ content, source, sourceType, relevance, page }] }
    private func executeQuery(_ query: NotebookLMQuery) async throws -> [NotebookLMResult] {

        let url = URL(string: "\(config.bridgeURL)/query")!

        let requestBody: [String: Any] = [
            "notebookId": query.notebookId.isEmpty ? config.notebookId : query.notebookId,
            "question": query.question,
            "maxResults": query.maxResults
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw NotebookLMError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = config.timeout

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NotebookLMError.queryFailed(
                "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resultsArray = json["results"] as? [[String: Any]] else {
            throw NotebookLMError.invalidResponse
        }

        return resultsArray.compactMap { dict -> NotebookLMResult? in
            guard let content = dict["content"] as? String,
                  let source = dict["source"] as? String else { return nil }

            let relevance = (dict["relevance"] as? NSNumber)?.floatValue ?? 0.7
            let sourceType = NotebookLMResult.SourceType(
                rawValue: dict["sourceType"] as? String ?? "PDF") ?? .pdf
            let page = dict["page"] as? String

            guard relevance >= query.minRelevance else { return nil }

            return NotebookLMResult(
                content: content, sourceTitle: source,
                sourceType: sourceType, relevanceScore: relevance,
                pageOrSection: page
            )
        }
    }

    // MARK: Timeout

    private func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw NotebookLMError.timeout
            }
            guard let result = try await group.next() else {
                throw NotebookLMError.timeout
            }
            group.cancelAll()
            return result
        }
    }

    private func cleanExpiredCache() {
        let now = Date()
        queryCache = queryCache.filter {
            now.timeIntervalSince($0.value.timestamp) < cacheTTL
        }
    }

    func clearCache() { queryCache.removeAll() }
}

// MARK: - 錯誤

enum NotebookLMError: Error, LocalizedError, Sendable {
    case notConfigured
    case bridgeNotRunning
    case invalidRequest
    case invalidResponse
    case queryFailed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .notConfigured:      return "NotebookLM 未設定 Notebook ID"
        case .bridgeNotRunning:   return "NotebookLM Bridge 未啟動 (npm run bridge)"
        case .invalidRequest:     return "查詢請求格式錯誤"
        case .invalidResponse:    return "NotebookLM 回應格式錯誤"
        case .queryFailed(let d): return "查詢失敗：\(d)"
        case .timeout:            return "NotebookLM 查詢超時（> 3 秒）"
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// MARK: - Node.js Bridge 範例
// ═══════════════════════════════════════════════════════════════════════════
//
// bridge-server.js:
//
//   const express = require('express');
//   const { NotebookLM } = require('notebooklm-kit');
//   const app = express();
//   app.use(express.json());
//
//   const nlm = new NotebookLM({ /* auth */ });
//
//   app.post('/query', async (req, res) => {
//     const { notebookId, question, maxResults } = req.body;
//     const notebook = await nlm.getNotebook(notebookId);
//     const results = await notebook.query(question, { maxResults });
//     res.json({ results: results.map(r => ({
//       content: r.text, source: r.source.title,
//       sourceType: r.source.type, relevance: r.score,
//       page: r.source.page || null
//     })) });
//   });
//
//   app.listen(3210);
//
// ═══════════════════════════════════════════════════════════════════════════
