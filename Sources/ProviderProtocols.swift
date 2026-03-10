// ═══════════════════════════════════════════════════════════════════════════
// ProviderProtocols.swift
// MeetingCopilot v4.2 — 抽象 Provider 介面
// ═══════════════════════════════════════════════════════════════════════════
//
//  三個核心 Protocol，讓三層管線的每一層可替換底層實作：
//  - Claude → OpenAI / Gemini / local model
//  - NotebookLM → vector DB / enterprise KB
//  - Apple Speech → Whisper / Azure / Deepgram
//
//  Platform: macOS 14.0+
// ═══════════════════════════════════════════════════════════════════════════

import Foundation

// MARK: - Knowledge Retrieval Provider（第一、二層共用）

protocol KnowledgeRetrievalProvider: Sendable {
    var providerName: String { get }
    var isAvailable: Bool { get async }
    func retrieve(question: String, maxResults: Int) async -> [RetrievalResult]
}

struct RetrievalResult: Sendable, Identifiable {
    let id = UUID()
    let content: String
    let source: String
    let sourceType: String
    let relevanceScore: Float
    let pageOrSection: String?
    let providerName: String

    var asContext: String {
        var ctx = "【\(source)"
        if let page = pageOrSection { ctx += " - \(page)" }
        ctx += "】\n\(content)"
        return ctx
    }
}

// MARK: - Generative Response Provider（第三層）

protocol GenerativeResponseProvider: Sendable {
    var providerName: String { get }
    func streamQuery(question: String, context: GenerativeContext) async -> AsyncStream<String>
}

struct GenerativeContext: Sendable {
    let meetingGoals: [String]
    let preAnalysis: String
    let retrievalResults: String
    let recentTranscript: String
    let attendeeInfo: String
    let meetingType: String
}

// MARK: - Transcript Provider（音訊層）

protocol TranscriptProviderProtocol: Sendable {
    var providerName: String { get }
    var isActive: Bool { get async }
    func start() async throws
    func stop() async
    var transcriptStream: AsyncStream<TranscriptSegment> { get async }
}

// MARK: - Helper

extension Array where Element == RetrievalResult {
    func formatAsLLMContext() -> String {
        guard !isEmpty else { return "" }
        var ctx = "【相關文件段落（\(first!.providerName)）】\n\n"
        for (i, r) in enumerated() {
            ctx += "[\(i + 1)] \(r.asContext)\n"
            ctx += "    (相關度: \(String(format: "%.0f", r.relevanceScore * 100))%)\n\n"
        }
        ctx += "【請基於以上段落回答，不要編造文件中沒有的數據】"
        return ctx
    }
}
