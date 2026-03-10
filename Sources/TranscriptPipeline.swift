// ═══════════════════════════════════════════════════════════════════════════
// TranscriptPipeline.swift
// MeetingCopilot v4.3 — 雙串流逐字稿管線（說話者分離 + Structured Entries）
// ═══════════════════════════════════════════════════════════════════════════
//
//  SystemAudioEngine  →  「對方的聲音」  →  .remote
//  MicrophoneEngine   →  「我的聲音」    →  .local
//
//  Platform: macOS 14.0+
// ═══════════════════════════════════════════════════════════════════════════

import Foundation

// MARK: - 說話者來源

enum SpeakerSource: String, Sendable {
    case remote = "remote"
    case local  = "local"
}

// MARK: - ★ Structured Transcript Entry（UI 分色用）

struct TranscriptEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let speaker: SpeakerSource
    let text: String
    let isFinal: Bool

    var speakerLabel: String {
        switch speaker {
        case .remote: return "對方"
        case .local:  return "我方"
        }
    }
}

// MARK: - Pipeline Output

struct TranscriptUpdate: Sendable {
    let fullText: String
    let recentText: String
    let segment: TranscriptSegment
    let speaker: SpeakerSource
    let detectedQuestion: String?
    let entry: TranscriptEntry            // ★ structured entry
}

// MARK: - Dual-Stream Transcript Pipeline

actor TranscriptPipeline {

    private(set) var captureState: AudioCaptureState = .idle
    private(set) var activeEngineType: AudioCaptureEngineType?
    private(set) var fullTranscript: String = ""
    private(set) var recentTranscript: String = ""
    private(set) var remoteTranscript: String = ""
    private(set) var localTranscript: String = ""
    private(set) var hasDualStream: Bool = false

    // ★ Structured entries（UI 分色用）
    private(set) var transcriptEntries: [TranscriptEntry] = []
    private let maxEntries = 200  // 最多保留 200 條

    private var systemAudioEngine: SystemAudioCaptureEngine?
    private var microphoneEngine: MicrophoneCaptureEngine?
    private let questionDetector = QuestionDetector()
    private var remoteConsumerTask: Task<Void, Never>?
    private var localConsumerTask: Task<Void, Never>?
    private var continuation: AsyncStream<TranscriptUpdate>.Continuation?
    private(set) var updates: AsyncStream<TranscriptUpdate>!

    init() {
        var cont: AsyncStream<TranscriptUpdate>.Continuation!
        self.updates = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    // ═ Start ═

    func start(config: AudioCaptureConfiguration = .default) async throws {
        var systemOK = false
        var micOK = false

        let sysEngine = SystemAudioCaptureEngine(configuration: config)
        do {
            try await sysEngine.start()
            self.systemAudioEngine = sysEngine
            systemOK = true
            print("🎤 DualStream: SystemAudio (remote) started")
        } catch {
            print("⚠️ DualStream: SystemAudio failed — \(error.localizedDescription)")
        }

        let micEngine = MicrophoneCaptureEngine(configuration: config)
        do {
            try await micEngine.start()
            self.microphoneEngine = micEngine
            micOK = true
            print("🎤 DualStream: Microphone (local) started")
        } catch {
            print("⚠️ DualStream: Microphone failed — \(error.localizedDescription)")
        }

        if systemOK && micOK {
            hasDualStream = true
            activeEngineType = .systemAudio
            captureState = .capturing
            startRemoteConsumer()
            startLocalConsumer()
            print("✅ DualStream: DUAL mode — remote + local separation active")
        } else if systemOK {
            hasDualStream = false
            activeEngineType = .systemAudio
            captureState = .capturing
            startRemoteConsumer()
            print("⚠️ DualStream: SystemAudio only — no speaker separation")
        } else if micOK {
            hasDualStream = false
            activeEngineType = .microphone
            captureState = .capturing
            startLocalConsumer()
            print("⚠️ DualStream: Microphone only (fallback) — no speaker separation")
        } else {
            captureState = .error(.engineStartFailed("所有音訊引擎都無法啟動"))
            throw AudioCaptureError.engineStartFailed("所有音訊引擎都無法啟動")
        }
    }

    // ═ Stop ═

    func stop() async {
        remoteConsumerTask?.cancel()
        localConsumerTask?.cancel()
        remoteConsumerTask = nil
        localConsumerTask = nil
        await systemAudioEngine?.stop()
        await microphoneEngine?.stop()
        systemAudioEngine = nil
        microphoneEngine = nil
        captureState = .idle
        activeEngineType = nil
        hasDualStream = false
        continuation?.finish()
    }

    // ═ Consumers ═

    private func startRemoteConsumer() {
        guard let engine = systemAudioEngine else { return }
        remoteConsumerTask = Task { [weak self] in
            for await segment in engine.transcriptStream {
                guard let self = self, !Task.isCancelled else { break }
                await self.processSegment(segment, speaker: .remote)
            }
        }
    }

    private func startLocalConsumer() {
        guard let engine = microphoneEngine else { return }
        localConsumerTask = Task { [weak self] in
            for await segment in engine.transcriptStream {
                guard let self = self, !Task.isCancelled else { break }
                await self.processSegment(segment, speaker: .local)
            }
        }
    }

    // ═ Process Segment ═

    private func processSegment(_ segment: TranscriptSegment, speaker: SpeakerSource) {
        switch speaker {
        case .remote: remoteTranscript = segment.text
        case .local:  localTranscript = segment.text
        }

        // ★ Structured entry
        let entry = TranscriptEntry(
            timestamp: segment.timestamp,
            speaker: speaker,
            text: segment.text,
            isFinal: segment.isFinal
        )

        // 僅在 final 時加入 entries 陣列（避免 partial results 洗版）
        if segment.isFinal && segment.text.count > 3 {
            transcriptEntries.append(entry)
            if transcriptEntries.count > maxEntries {
                transcriptEntries.removeFirst(transcriptEntries.count - maxEntries)
            }
        }

        fullTranscript = buildMergedTranscript()
        recentTranscript = String(fullTranscript.suffix(80))

        guard segment.text.count > 5 else { return }

        let detectedQuestion: String?
        if speaker == .remote {
            let recent60 = String(segment.text.suffix(60))
            detectedQuestion = questionDetector.isQuestion(recent60) ? recent60 : nil
        } else {
            detectedQuestion = nil
        }

        continuation?.yield(TranscriptUpdate(
            fullText: fullTranscript,
            recentText: recentTranscript,
            segment: segment,
            speaker: speaker,
            detectedQuestion: detectedQuestion,
            entry: entry
        ))
    }

    private func buildMergedTranscript() -> String {
        if hasDualStream {
            // 用 structured entries 組合
            return transcriptEntries.map { e in
                "[\(e.speakerLabel)] \(e.text)"
            }.joined(separator: "\n")
        } else {
            return remoteTranscript.isEmpty ? localTranscript : remoteTranscript
        }
    }
}

// MARK: - Question Detector

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
