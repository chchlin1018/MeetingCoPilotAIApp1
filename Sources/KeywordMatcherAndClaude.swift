// KeywordMatcherAndClaude.swift
// MeetingCopilot v4.0 — Local Q&A Matching + Claude API Streaming
//
// Path 1: Pre-loaded Q&A local matching (< 200ms) -> Blue card
// Path 2: Claude Sonnet streaming (1.5-3s) -> Purple card

import Foundation

// MARK: - Q&A Knowledge Base Item

struct QAItem: Identifiable, Codable, Sendable {
    let id: UUID
    let question: String
    let keywords: [String]
    let shortAnswer: String
    let fullAnswer: String
    let detailedAnswer: String?
    let category: String?
    
    init(
        question: String,
        keywords: [String],
        shortAnswer: String,
        fullAnswer: String,
        detailedAnswer: String? = nil,
        category: String? = nil
    ) {
        self.id = UUID()
        self.question = question
        self.keywords = keywords
        self.shortAnswer = shortAnswer
        self.fullAnswer = fullAnswer
        self.detailedAnswer = detailedAnswer
        self.category = category
    }
}

// MARK: - Match Result

struct MatchResult: Sendable {
    let item: QAItem
    let confidence: Float          // 0.0 ~ 1.0
    let matchedKeywords: [String]
    let latencyMs: Double
}

// MARK: - Local Keyword Matcher

actor KeywordMatcher {
    
    private var knowledgeBase: [QAItem] = []
    private var lastTriggeredItemId: UUID?
    private var lastTriggerTime: Date = .distantPast
    private let cooldownInterval: TimeInterval = 20.0
    
    private let questionIndicators: Set<String> = [
        "嗎", "什麼", "怎麼", "為什麼", "如何", "哪", "幾",
        "能不能", "可不可以", "是否", "有沒有", "多少",
        "?", "？", "呢", "吧",
        "what", "how", "why", "when", "where", "which",
        "can", "could", "would", "should", "is", "are", "do", "does"
    ]
    
    func loadKnowledgeBase(_ items: [QAItem]) {
        self.knowledgeBase = items
        print("KeywordMatcher: Loaded \(items.count) Q&A items")
    }
    
    func match(transcript: String) -> MatchResult? {
        let startTime = CFAbsoluteTimeGetCurrent()
        let recentText = String(transcript.suffix(40)).lowercased()
        
        var bestMatch: (item: QAItem, score: Float, keywords: [String])?
        
        for item in knowledgeBase {
            let matchedKeywords = item.keywords.filter { keyword in
                recentText.localizedCaseInsensitiveContains(keyword.lowercased())
            }
            guard !matchedKeywords.isEmpty else { continue }
            
            var score: Float = Float(matchedKeywords.count) / Float(item.keywords.count)
            let hasQuestionContext = questionIndicators.contains { recentText.contains($0) }
            if hasQuestionContext { score = min(1.0, score + 0.3) }
            if matchedKeywords.count >= 2 { score = min(1.0, score + 0.2) }
            guard score >= 0.4 else { continue }
            
            if bestMatch == nil || score > bestMatch!.score {
                bestMatch = (item, score, matchedKeywords)
            }
        }
        
        guard let match = bestMatch else { return nil }
        
        let now = Date()
        if match.item.id == lastTriggeredItemId &&
           now.timeIntervalSince(lastTriggerTime) < cooldownInterval {
            return nil
        }
        
        lastTriggeredItemId = match.item.id
        lastTriggerTime = now
        let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        
        return MatchResult(
            item: match.item,
            confidence: match.score,
            matchedKeywords: match.keywords,
            latencyMs: latency
        )
    }
    
    func resetCooldown() {
        lastTriggeredItemId = nil
        lastTriggerTime = .distantPast
    }
}

// MARK: - AI Card

struct AICard: Identifiable, Sendable {
    let id = UUID()
    let type: AICardType
    let title: String
    let content: String
    let confidence: Float
    let latencyMs: Double
    let timestamp: Date
    
    enum AICardType: String, Sendable {
        case qaMatch     = "qa_match"      // Blue: Local Q&A match
        case aiGenerated = "ai_generated"   // Purple: Claude generated
        case strategy    = "strategy"       // Orange: Strategy suggestion
        case warning     = "warning"        // Yellow: Warning
    }
}

// MARK: - Meeting Context (sent to Claude)

struct MeetingContext: Sendable {
    let goals: [String]
    let preAnalysisCache: String       // NotebookLM pre-analysis
    let relevantQA: [QAItem]
    let recentTranscript: String
    let attendeeInfo: String
    let meetingType: String
}

// MARK: - Claude API Service

actor ClaudeService {
    
    private let apiKey: String
    private let model: String
    private let baseURL = "https://api.anthropic.com/v1/messages"
    
    init(apiKey: String, model: String = "claude-sonnet-4-20250514") {
        self.apiKey = apiKey
        self.model = model
    }
    
    func streamQuery(question: String, context: MeetingContext) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                let startTime = CFAbsoluteTimeGetCurrent()
                let systemPrompt = buildSystemPrompt(context: context)
                let userMessage = buildUserMessage(question: question, context: context)
                
                let requestBody: [String: Any] = [
                    "model": model,
                    "max_tokens": 500,
                    "stream": true,
                    "system": systemPrompt,
                    "messages": [["role": "user", "content": userMessage]]
                ]
                
                guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody),
                      let url = URL(string: baseURL) else {
                    continuation.finish()
                    return
                }
                
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "content-type")
                request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                request.httpBody = jsonData
                
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 else {
                        continuation.finish()
                        return
                    }
                    
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonString = String(line.dropFirst(6))
                        guard jsonString != "[DONE]",
                              let data = jsonString.data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }
                        
                        if let type = event["type"] as? String,
                           type == "content_block_delta",
                           let delta = event["delta"] as? [String: Any],
                           let text = delta["text"] as? String {
                            continuation.yield(text)
                        }
                    }
                } catch {
                    print("Claude API error: \(error)")
                }
                
                let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                print("Claude response complete, latency: \(Int(latency))ms")
                continuation.finish()
            }
        }
    }
    
    private func buildSystemPrompt(context: MeetingContext) -> String {
        """
        You are MeetingCopilot's real-time meeting assistant. Provide instant strategic advice during business meetings.

        Rules:
        1. Keep answers concise (under 100 chars) - this is a teleprompter
        2. Base answers on pre-loaded knowledge and meeting context
        3. Cite specific data or cases when possible
        4. Sound like a senior advisor whispering suggestions
        5. Provide defense strategies for aggressive questions

        Meeting type: \(context.meetingType)

        Goals:
        \(context.goals.enumerated().map { "  \($0 + 1). \($1)" }.joined(separator: "\n"))

        Pre-analysis (from NotebookLM):
        \(context.preAnalysisCache)

        Attendee intel:
        \(context.attendeeInfo)
        """
    }
    
    private func buildUserMessage(question: String, context: MeetingContext) -> String {
        """
        [Recent transcript]
        \(context.recentTranscript)

        [Detected question/topic]
        \(question)

        [Related pre-loaded Q&A]
        \(context.relevantQA.prefix(3).map { "Q: \($0.question)\nA: \($0.shortAnswer)" }.joined(separator: "\n\n"))

        Provide:
        1. Suggested response (concise, under 50 chars)
        2. Supporting data points (if available)
        """
    }
}
