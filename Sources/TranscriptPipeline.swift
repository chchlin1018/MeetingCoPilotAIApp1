// ═══════════════════════════════════════════════════════════════════════════
// TranscriptPipeline.swift
// MeetingCopilot v4.3 — 雙串流逐字稿管線（說話者分離）
// ═══════════════════════════════════════════════════════════════════════════
//
//  v4.2 → v4.3 核心變更：單引擎降級 → 雙引擎並行
//
//  運作原理：
//  ─────────────────────────────────────────────────
//  SystemAudioEngine  →  「對方的聲音」  →  .remote
//  (ScreenCaptureKit)    (Teams/Zoom/Meet 系統音訊輸出)
//
//  MicrophoneEngine   →  「我的聲音」    →  .local
//  (AVAudioEngine)       (麥克風輸入)
//  ─────────────────────────────────────────────────
//
//  下游消費規則：
//  - .remote → ResponseOrchestrator（觸發問題偵測 → 三層管線）
//  - .local  → TalkingPointsTracker（偵測「我講了什麼」）
//  - 兩者都顯示在 UI 逐字稿（不同顏色標誊）
//
//  為什麼這樣設計：
//  線上會議中，系統音訊 = 對方的聲音，麥克風 = 我的聲音。
//  這是硬體層級的天然分離，不需要 ML 模型，零延遲、零成本。
//  在遠端會議場景中準確率 ~95%+。
//
//  降級機制：
//  - SystemAudio 啟動失敗 → 僅啟動 Microphone（所有轉錄標記為 .local）
//  - Microphone 啟動失敗 → 僅啟動 SystemAudio（所有轉錄標記為 .remote）
//  - 兩者都失敗 → 拋錯
//
//  Platform: macOS 14.0+
// ═══════════════════════════════════════════════════════════════════════════

import Foundation

// MARK: - 說話者來源

enum SpeakerSource: String, Sendable {
    case remote = "remote"   // 對方的聲音（系統音訊）
    case local  = "local"    // 我的聲音（麥克風）
}

// MARK: - Pipeline Output

struct TranscriptUpdate: Sendable {
    let fullText: String                 // 完整逐字稿（雙方合併）
    let recentText: String               // 最近一段
    let segment: TranscriptSegment       // 原始 segment
    let speaker: SpeakerSource           // ★ 說話者來源
    let detectedQuestion: String?        // 僅 .remote 時才會有值
}

// MARK: - Dual-Stream Transcript Pipeline

actor TranscriptPipeline {

    // 對外狀態
    private(set) var captureState: AudioCaptureState = .idle
    private(set) var activeEngineType: AudioCaptureEngineType?
    private(set) var fullTranscript: String = ""          // 雙方合併逐字稿
    private(set) var recentTranscript: String = ""
    private(set) var remoteTranscript: String = ""         // 僅對方
    private(set) var localTranscript: String = ""           // 僅我方
    private(set) var hasDualStream: Bool = false            // 是否雙串流模式

    // 雙引擎
    private var systemAudioEngine: SystemAudioCaptureEngine?
    private var microphoneEngine: MicrophoneCaptureEngine?

    // 問題偵測
    private let questionDetector = QuestionDetector()

    // Tasks
    private var remoteConsumerTask: Task<Void, Never>?
    private var localConsumerTask: Task<Void, Never>?

    // 輸出串流
    private var continuation: AsyncStream<TranscriptUpdate>.Continuation?
    private(set) var updates: AsyncStream<TranscriptUpdate>!

    init() {
        var cont: AsyncStream<TranscriptUpdate>.Continuation!
        self.updates = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    // ═════════════════════════════════════════════════
    // MARK: Start（雙引擎並行啟動）
    // ═════════════════════════════════════════════════

    func start(config: AudioCaptureConfiguration = .default) async throws {
        var systemOK = false
        var micOK = false

        // ─── 嘗試啟動 SystemAudio（對方的聲音）───
        let sysEngine = SystemAudioCaptureEngine(configuration: config)
        do {
            try await sysEngine.start()
            self.systemAudioEngine = sysEngine
            systemOK = true
            print("🎤 DualStream: SystemAudio (remote) started")
        } catch {
            print("⚠️ DualStream: SystemAudio failed — \(error.localizedDescription)")
        }

        // ─── 嘗試啟動 Microphone（我的聲音）───
        let micEngine = MicrophoneCaptureEngine(configuration: config)
        do {
            try await micEngine.start()
            self.microphoneEngine = micEngine
            micOK = true
            print("🎤 DualStream: Microphone (local) started")
        } catch {
            print("⚠️ DualStream: Microphone failed — \(error.localizedDescription)")
        }

        // ─── 判斷模式 ───
        if systemOK && micOK {
            // ★ 雙串流模式（最佳）
            hasDualStream = true
            activeEngineType = .systemAudio
            captureState = .capturing
            startRemoteConsumer()
            startLocalConsumer()
            print("✅ DualStream: DUAL mode — remote + local separation active")
        } else if systemOK {
            // 僅系統音訊（無法分離，全部標記為 remote）
            hasDualStream = false
            activeEngineType = .systemAudio
            captureState = .capturing
            startRemoteConsumer()
            print("⚠️ DualStream: SystemAudio only — no speaker separation")
        } else if micOK {
            // 僅麥克風（降級，全部標記為 local）
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

    // ═════════════════════════════════════════════════
    // MARK: Stop
    // ═════════════════════════════════════════════════

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

    // ═════════════════════════════════════════════════
    // MARK: Remote Stream Consumer（對方的聲音）
    // ═════════════════════════════════════════════════

    private func startRemoteConsumer() {
        guard let engine = systemAudioEngine else { return }
        remoteConsumerTask = Task { [weak self] in
            for await segment in engine.transcriptStream {
                guard let self = self, !Task.isCancelled else { break }
                await self.processSegment(segment, speaker: .remote)
            }
        }
    }

    // ═════════════════════════════════════════════════
    // MARK: Local Stream Consumer（我的聲音）
    // ═════════════════════════════════════════════════

    private func startLocalConsumer() {
        guard let engine = microphoneEngine else { return }
        localConsumerTask = Task { [weak self] in
            for await segment in engine.transcriptStream {
                guard let self = self, !Task.isCancelled else { break }
                await self.processSegment(segment, speaker: .local)
            }
        }
    }

    // ═════════════════════════════════════════════════
    // MARK: Process Segment（統一處理）
    // ═════════════════════════════════════════════════

    private func processSegment(_ segment: TranscriptSegment, speaker: SpeakerSource) {
        // 更新分離逐字稿
        switch speaker {
        case .remote:
            remoteTranscript = segment.text
        case .local:
            localTranscript = segment.text
        }

        // 合併逐字稿（UI 顯示用）
        fullTranscript = buildMergedTranscript()
        recentTranscript = String(fullTranscript.suffix(80))

        guard segment.text.count > 5 else { return }

        // ★ 問題偵測：僅對 對方的聲音 執行
        let detectedQuestion: String?
        if speaker == .remote {
            let recent60 = String(segment.text.suffix(60))
            detectedQuestion = questionDetector.isQuestion(recent60) ? recent60 : nil
        } else {
            detectedQuestion = nil  // 我的聲音永遠不觸發問題偵測
        }

        // 發射更新
        continuation?.yield(TranscriptUpdate(
            fullText: fullTranscript,
            recentText: recentTranscript,
            segment: segment,
            speaker: speaker,
            detectedQuestion: detectedQuestion
        ))
    }

    /// 合併雙方逐字稿
    private func buildMergedTranscript() -> String {
        if hasDualStream {
            // 雙串流模式：標註說話者
            var merged = ""
            if !remoteTranscript.isEmpty {
                merged += "[對方] \(remoteTranscript)\n"
            }
            if !localTranscript.isEmpty {
                merged += "[我方] \(localTranscript)"
            }
            return merged
        } else {
            // 單引擎模式：直接顯示
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
