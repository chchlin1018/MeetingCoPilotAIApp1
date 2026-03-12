// ═══════════════════════════════════════════════════════════════════════════
// TranscriptPipeline.swift
// MeetingCopilot v4.3.1 — 雙串流 + Audio Health + Diagnostics
// ═══════════════════════════════════════════════════════════════════════════

import Foundation

enum SpeakerSource: String, Sendable { case remote = "remote"; case local = "local" }

struct TranscriptEntry: Identifiable, Sendable {
    let id = UUID(); let timestamp: Date; let speaker: SpeakerSource; let text: String; let isFinal: Bool
    var speakerLabel: String { speaker == .remote ? "對方" : "我方" }
}

struct TranscriptUpdate: Sendable {
    let fullText: String; let recentText: String; let segment: TranscriptSegment
    let speaker: SpeakerSource; let detectedQuestion: String?; let entry: TranscriptEntry
}

struct AudioHealthStatus: Sendable {
    let remoteActive: Bool; let localActive: Bool
    let remoteLastReceived: Date?; let localLastReceived: Date?
    let remoteSegmentCount: Int; let localSegmentCount: Int
    let startupMessage: String?; let detectedAppName: String?
    enum StreamStatus: String, Sendable { case active = "活躍"; case idle = "靜音"; case disconnected = "斷線"; case notStarted = "未啟動" }
    func remoteStatus(now: Date = Date()) -> StreamStatus {
        guard let last = remoteLastReceived else { return remoteActive ? .idle : .notStarted }
        let e = now.timeIntervalSince(last); if e < 10 { return .active }; if e < 30 { return .idle }; return .disconnected
    }
    func localStatus(now: Date = Date()) -> StreamStatus {
        guard let last = localLastReceived else { return localActive ? .idle : .notStarted }
        let e = now.timeIntervalSince(last); if e < 10 { return .active }; if e < 30 { return .idle }; return .disconnected
    }
}

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
    private var remoteLastReceived: Date?; private var localLastReceived: Date?
    private var remoteSegmentCount: Int = 0; private var localSegmentCount: Int = 0
    private var remoteEngineStarted: Bool = false; private var localEngineStarted: Bool = false
    private var _startupMessage: String?; private var _detectedAppName: String?
    private var _screenRecordingOK: Bool = true
    private var _startupErrors: [String] = []
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
        AudioHealthStatus(remoteActive: remoteEngineStarted, localActive: localEngineStarted,
            remoteLastReceived: remoteLastReceived, localLastReceived: localLastReceived,
            remoteSegmentCount: remoteSegmentCount, localSegmentCount: localSegmentCount,
            startupMessage: _startupMessage, detectedAppName: _detectedAppName)
    }

    // ★ 診斷資訊（給 PostMeetingLogger）
    func getEngineDiagnostics() async -> (remote: EngineDiagnosticInfo, local: EngineDiagnosticInfo, screenRecordingOK: Bool, micDevice: String, bluetoothDetected: Bool, errors: [String]) {
        let remoteDiag: EngineDiagnosticInfo
        if let engine = systemAudioEngine {
            remoteDiag = await engine.diagnosticInfo
        } else {
            remoteDiag = EngineDiagnosticInfo.empty
        }
        let localDiag: EngineDiagnosticInfo
        let micDevice: String
        let btDetected: Bool
        if let engine = microphoneEngine {
            localDiag = await engine.diagnosticInfo
            micDevice = await engine.micDeviceName
            btDetected = await engine.bluetoothDetected
        } else {
            localDiag = EngineDiagnosticInfo.empty
            micDevice = "N/A"
            btDetected = false
        }
        return (remoteDiag, localDiag, _screenRecordingOK, micDevice, btDetected, _startupErrors)
    }

    func start(config: AudioCaptureConfiguration = .default) async throws {
        var systemOK = false, micOK = false
        var systemError: Error?, micError: Error?
        let sysEngine = SystemAudioCaptureEngine(configuration: config)
        do {
            try await sysEngine.start()
            self.systemAudioEngine = sysEngine; systemOK = true; remoteEngineStarted = true
            _detectedAppName = await sysEngine.detectedAppName
            _screenRecordingOK = true
            print("🎙️ DualStream: SystemAudio (remote) started — App: \(_detectedAppName ?? "unknown")")
        } catch {
            systemError = error
            _startupErrors.append("SystemAudio: \(error.localizedDescription)")
            if error.localizedDescription.contains("TCC") || error.localizedDescription.contains("拒絕") || error.localizedDescription.contains("擷取") {
                _screenRecordingOK = false
            }
            print("⚠️ DualStream: SystemAudio failed — \(error.localizedDescription)")
        }
        let micEngine = MicrophoneCaptureEngine(configuration: config)
        do {
            try await micEngine.start()
            self.microphoneEngine = micEngine; micOK = true; localEngineStarted = true
            print("🎙️ DualStream: Microphone (local) started")
        } catch {
            micError = error
            _startupErrors.append("Microphone: \(error.localizedDescription)")
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
            captureState = .error(.engineStartFailed("所有音訊引擎都無法啟動"))
            _startupMessage = "❌ 音訊啟動失敗"
            throw AudioCaptureError.engineStartFailed("所有音訊引擎都無法啟動")
        }
    }

    private func describeError(_ error: Error?, fallback: String) -> String {
        guard let e = error as? AudioCaptureError else { return error?.localizedDescription ?? fallback }
        switch e {
        case .noAudioSourceFound: return "找不到會議/通話 App"
        case .permissionDenied: return "權限未授權"
        case .speechRecognizerUnavailable: return "語音辨識不可用"
        case .engineStartFailed(let d): return d
        case .captureInterrupted(let r): return r
        case .configurationFailed(let d): return d
        }
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
        let dq: String?
        if speaker == .remote { let r = String(segment.text.suffix(60)); dq = questionDetector.isQuestion(r) ? r : nil } else { dq = nil }
        continuation?.yield(TranscriptUpdate(fullText: fullTranscript, recentText: recentTranscript, segment: segment, speaker: speaker, detectedQuestion: dq, entry: entry))
    }

    private func buildMergedTranscript() -> String {
        if hasDualStream {
            var m = transcriptEntries.map { "[\($0.speakerLabel)] \($0.text)" }.joined(separator: "\n")
            var p: [String] = []
            if !remoteTranscript.isEmpty { p.append("[對方] \(remoteTranscript)") }
            if !localTranscript.isEmpty { p.append("[我方] \(localTranscript)") }
            if !p.isEmpty { if !m.isEmpty { m += "\n" }; m += p.joined(separator: "\n") }
            return m
        } else { return remoteTranscript.isEmpty ? localTranscript : remoteTranscript }
    }
}

struct QuestionDetector: Sendable {
    private let patterns: [String] = ["嗎","什麼","怎麼","為什麼","如何","哪裡","哪些","哪個","幾","多少","能不能","可不可以","是否","有沒有","呢","吧","請問","想問","請教","好奇","比較","差異","不同","優勢","劣勢","what","how","why","when","where","which","who","can you","could you","would you","tell me","explain","describe","difference","compare","advantage","？","?"]
    func isQuestion(_ text: String) -> Bool { let l = text.lowercased(); return patterns.contains { l.contains($0) } }
}
