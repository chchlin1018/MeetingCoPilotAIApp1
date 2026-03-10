// ═══════════════════════════════════════════════════════════════════════════
// TranscriptPipeline.swift
// MeetingCopilot v4.2 — 逐字稿管線（從 Coordinator 拆出）
// ═══════════════════════════════════════════════════════════════════════════
//
//  單一職責：
//  1. 選擇並啟動音訊引擎（主引擎 → 降級）
//  2. 消費 transcriptStream
//  3. 問題偵測
//  4. 發射 TranscriptUpdate 給下游
//
//  不負責：AI 回應、卡片生成、TP 追蹤
//
//  Platform: macOS 14.0+
// ═══════════════════════════════════════════════════════════════════════════

import Foundation

// MARK: - Pipeline Output

struct TranscriptUpdate: Sendable {
    let fullText: String
    let recentText: String
    let segment: TranscriptSegment
    let detectedQuestion: String?
}

// MARK: - Transcript Pipeline

actor TranscriptPipeline {

    private(set) var captureState: AudioCaptureState = .idle
    private(set) var activeEngineType: AudioCaptureEngineType?
    private(set) var fullTranscript: String = ""
    private(set) var recentTranscript: String = ""

    private var audioEngine: (any AudioCaptureEngine)?
    private let questionDetector = QuestionDetector()
    private var consumerTask: Task<Void, Never>?

    private var continuation: AsyncStream<TranscriptUpdate>.Continuation?
    private(set) var updates: AsyncStream<TranscriptUpdate>!

    init() {
        var cont: AsyncStream<TranscriptUpdate>.Continuation!
        self.updates = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    func start(config: AudioCaptureConfiguration = .default) async throws {
        let systemEngine = SystemAudioCaptureEngine(configuration: config)
        do {
            try await systemEngine.start()
            self.audioEngine = systemEngine
            self.activeEngineType = .systemAudio
            self.captureState = .capturing
        } catch {
            let micEngine = MicrophoneCaptureEngine(configuration: config)
            do {
                try await micEngine.start()
                self.audioEngine = micEngine
                self.activeEngineType = .microphone
                self.captureState = .capturing
            } catch {
                self.captureState = .error(.engineStartFailed("所有引擎都無法啟動"))
                throw AudioCaptureError.engineStartFailed("所有引擎都無法啟動")
            }
        }
        startConsuming()
    }

    func stop() async {
        consumerTask?.cancel()
        consumerTask = nil
        await audioEngine?.stop()
        audioEngine = nil
        captureState = .idle
        activeEngineType = nil
        continuation?.finish()
    }

    private func startConsuming() {
        guard let engine = audioEngine else { return }
        consumerTask = Task { [weak self] in
            for await segment in engine.transcriptStream {
                guard let self = self, !Task.isCancelled else { break }
                await self.processSegment(segment)
            }
        }
    }

    private func processSegment(_ segment: TranscriptSegment) {
        fullTranscript = segment.text
        recentTranscript = segment.recentText
        guard segment.text.count > 5 else { return }
        let recent60 = String(segment.text.suffix(60))
        let question: String? = questionDetector.isQuestion(recent60) ? recent60 : nil
        continuation?.yield(TranscriptUpdate(
            fullText: segment.text, recentText: segment.recentText,
            segment: segment, detectedQuestion: question
        ))
    }
}

struct QuestionDetector: Sendable {
    private let patterns: [String] = [
        "嗎", "什麼", "怎麼", "為什麼", "如何", "哪裡", "哪些", "哪個",
        "幾", "多少", "能不能", "可不可以", "是否", "有沒有",
        "呢", "吧", "請問", "想問", "請教", "好奇",
        "比較", "差異", "不同", "優勢", "劣勢",
        "what", "how", "why", "when", "where", "which", "who",
        "can you", "could you", "would you",
        "tell me", "explain", "describe",
        "difference", "compare", "advantage", "？", "?"
    ]
    func isQuestion(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return patterns.contains { lowered.contains($0) }
    }
}
