// ═══════════════════════════════════════════════════════════════════════════
// TranscriptPipeline.swift
// MeetingCopilot v4.3.1 — 雙串流 + Audio Health + App Detection
// ═══════════════════════════════════════════════════════════════════════════

import Foundation

// MARK: - 說話者來源

enum SpeakerSource: String, Sendable {
    case remote = "remote"
    case local  = "local"
}

// MARK: - Structured Transcript Entry

struct TranscriptEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let speaker: SpeakerSource
    let text: String
    let isFinal: Bool
    var speakerLabel: String {
        switch speaker { case .remote: return "對方"; case .local: return "我方" }
    }
}

// MARK: - Pipeline Output

struct TranscriptUpdate: Sendable {
    let fullText: String
    let recentText: String
    let segment: TranscriptSegment
    let speaker: SpeakerSource
    let detectedQuestion: String?
    let entry: TranscriptEntry
}

// MARK: - ★ Audio Health Status

struct AudioHealthStatus: Sendable {
    let remoteActive: Bool
    let localActive: Bool
    let remoteLastReceived: Date?
    let localLastReceived: Date?
    let remoteSegmentCount: Int
    let localSegmentCount: Int
    let startupMessage: String?
    let detectedAppName: String?

    enum StreamStatus: String, Sendable {
        case active = "活躍"
        case idle = "靜音"
        case disconnected = "斷線"
        case notStarted = "未啟動"
    }

    func remoteStatus(now: Date = Date()) -> StreamStatus {
        guard let last = remoteLastReceived else { return remoteActive ? .idle : .notStarted }
        let elapsed = now.timeIntervalSince(last)
        if elapsed < 10 { return .active }
        if elapsed < 30 { return .idle }
        return .disconnected
    }

    func localStatus(now: Date = Date()) -> StreamStatus {
        guard let last = localLastReceived else { return localActive ? .idle : .notStarted }
        let elapsed = now.timeIntervalSince(last)
        if elapsed < 10 { return .active }
        if elapsed < 30 { return .idle }
        return .disconnected
    }
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
    private(set) var transcriptEntries: [TranscriptEntry] = []
    private let maxEntries = 200

    private var remoteLastReceived: Date?
    private var localLastReceived: Date?
    private var remoteSegmentCount: Int = 0
    private var localSegmentCount: Int = 0
    private var remoteEngineStarted: Bool = false
    private var localEngineStarted: Bool = false
    private var _startupMessage: String?
    private var _detectedAppName: String?

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

    var audioHealth: AudioHealthStatus {
        AudioHealthStatus(
            remoteActive: remoteEngineStarted, localActive: localEngineStarted,
            remoteLastReceived: remoteLastReceived, localLastReceived: localLastReceived,
            remoteSegmentCount: remoteSegmentCount, localSegmentCount: localSegmentCount,
            startupMessage: _startupMessage, detectedAppName: _detectedAppName
        )
    }

    func start(config: AudioCaptureConfiguration = .default) async throws {
        var systemOK = false, micOK = false
        var systemError: Error?, micError: Error?

        let sysEngine = SystemAudioCaptureEngine(configuration: config)
        do {
            try await sysEngine.start()
            self.systemAudioEngine = sysEngine
            systemOK = true; remoteEngineStarted = true
            _detectedAppName = await sysEngine.detectedAppName
            print("🎙️ DualStream: SystemAudio (remote) started — App: \(_detectedAppName ?? "unknown")")
        } catch {
            systemError = error
            print("⚠️ DualStream: SystemAudio failed — \(error.localizedDescription)")
        }

        let micEngine = MicrophoneCaptureEngine(configuration: config)
        do {
            try await micEngine.start()
            self.microphoneEngine = micEngine
            micOK = true; localEngineStarted = true
            print("🎙️ DualStream: Microphone (local) started")
        } catch {
            micError = error
            print("⚠️ DualStream: Microphone failed — \(error.localizedDescription)")
        }

        let appLabel = _detectedAppName ?? "系統音訊"

        if systemOK && micOK {
            hasDualStream = true; activeEngineType = .systemAudio; captureState = .capturing
            _startupMessage = "✅ 雙串流啟動成功：\(appLabel)（對方）+ 麥克風（我方）"
            startRemoteConsumer(); startLocalConsumer()
        } else if systemOK {
            hasDualStream = false; activeEngineType = .systemAudio; captureState = .capturing
            _startupMessage = "⚠️ 僅 \(appLabel) 音訊啟動，\(describeError(micError, fallback: "麥克風權限未授權"))"
            startRemoteConsumer()
        } else if micOK {
            hasDualStream = false; activeEngineType = .microphone; captureState = .capturing
            _startupMessage = "⚠️ 僅麥克風啟動，\(describeError(systemError, fallback: "系統音訊無法啟動"))"
            startLocalConsumer()
        } else {
            let sysDesc = describeError(systemError, fallback: "系統音訊無法啟動")
            let micDesc = describeError(micError, fallback: "麥克風無法啟動")
            captureState = .error(.engineStartFailed("所有音訊引擎都無法啟動"))
            _startupMessage = "❌ 音訊啟動失敗！\(sysDesc)；\(micDesc)"
            throw AudioCaptureError.engineStartFailed("所有音訊引擎都無法啟動")
        }
    }

    private func describeError(_ error: Error?, fallback: String) -> String {
        guard let error = error else { return fallback }
        if let captureError = error as? AudioCaptureError {
            switch captureError {
            case .noAudioSourceFound: return "找不到會議/通話 App（請先開啟 Teams/Zoom/LINE/WhatsApp/FaceTime 並加入通話）"
            case .permissionDenied: return "權限未授權（需在系統設定 → 螢幕與系統錄音 開啟）"
            case .speechRecognizerUnavailable: return "語音辨識不可用（請檢查網路或語言設定）"
            case .engineStartFailed(let d): return "引擎啟動失敗：\(d)"
            case .captureInterrupted(let r): return "擷取中斷：\(r)"
            case .configurationFailed(let d): return "設定錯誤：\(d)"
            }
        }
        return "\(error.localizedDescription)"
    }

    func stop() async {
        remoteConsumerTask?.cancel(); localConsumerTask?.cancel()
        remoteConsumerTask = nil; localConsumerTask = nil
        await systemAudioEngine?.stop(); await microphoneEngine?.stop()
        systemAudioEngine = nil; microphoneEngine = nil
        captureState = .idle; activeEngineType = nil; hasDualStream = false
        remoteEngineStarted = false; localEngineStarted = false
        _startupMessage = nil; _detectedAppName = nil
        continuation?.finish()
    }

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

    private func processSegment(_ segment: TranscriptSegment, speaker: SpeakerSource) {
        switch speaker {
        case .remote: remoteTranscript = segment.text; remoteLastReceived = Date(); remoteSegmentCount += 1
        case .local: localTranscript = segment.text; localLastReceived = Date(); localSegmentCount += 1
        }
        let entry = TranscriptEntry(timestamp: segment.timestamp, speaker: speaker, text: segment.text, isFinal: segment.isFinal)
        if segment.isFinal && segment.text.count > 3 {
            transcriptEntries.append(entry)
            if transcriptEntries.count > maxEntries { transcriptEntries.removeFirst(transcriptEntries.count - maxEntries) }
        }
        fullTranscript = buildMergedTranscript()
        if segment.text.count > 3 {
            let label = hasDualStream ? "[\(speaker == .remote ? "對方" : "我方")] " : ""
            recentTranscript = "\(label)\(String(segment.text.suffix(80)))"
        }
        guard segment.text.count > 5 else { return }
        let detectedQuestion: String?
        if speaker == .remote {
            let recent60 = String(segment.text.suffix(60))
            detectedQuestion = questionDetector.isQuestion(recent60) ? recent60 : nil
        } else { detectedQuestion = nil }
        continuation?.yield(TranscriptUpdate(
            fullText: fullTranscript, recentText: recentTranscript,
            segment: segment, speaker: speaker,
            detectedQuestion: detectedQuestion, entry: entry
        ))
    }

    private func buildMergedTranscript() -> String {
        if hasDualStream {
            var merged = transcriptEntries.map { "[\($0.speakerLabel)] \($0.text)" }.joined(separator: "\n")
            var partials: [String] = []
            if !remoteTranscript.isEmpty { partials.append("[對方] \(remoteTranscript)") }
            if !localTranscript.isEmpty { partials.append("[我方] \(localTranscript)") }
            if !partials.isEmpty {
                if !merged.isEmpty { merged += "\n" }
                merged += partials.joined(separator: "\n")
            }
            return merged
        } else { return remoteTranscript.isEmpty ? localTranscript : remoteTranscript }
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
