// MicrophoneCaptureEngine.swift
// MeetingCopilot v4.3.1 — Fallback: Microphone Capture Engine
// Fixed: restart loop + speech error handling

import Foundation
import AVFoundation
import Speech

actor MicrophoneCaptureEngine: NSObject, AudioCaptureEngine {
    
    nonisolated let engineType: AudioCaptureEngineType = .microphone
    
    nonisolated var transcriptStream: AsyncStream<TranscriptSegment> {
        AsyncStream { continuation in
            Task { await self.setStreamContinuation(continuation) }
        }
    }
    
    nonisolated(unsafe) private var _state: AudioCaptureState = .idle
    
    nonisolated var state: AudioCaptureState { _state }
    
    private var streamContinuation: AsyncStream<TranscriptSegment>.Continuation?
    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let config: AudioCaptureConfiguration
    private var bufferCount: Int = 0
    private var restartCount: Int = 0
    private var hasEverReceivedSpeech: Bool = false
    
    init(configuration: AudioCaptureConfiguration = .default) {
        self.config = configuration
        super.init()
    }
    
    private func setStreamContinuation(_ continuation: AsyncStream<TranscriptSegment>.Continuation) {
        self.streamContinuation = continuation
    }
    
    // MARK: - Start
    
    func start() async throws {
        guard !_state.isActive else { return }
        _state = .preparing
        
        speechRecognizer = SFSpeechRecognizer(locale: config.speechLocale)
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw AudioCaptureError.speechRecognizerUnavailable
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else {
            throw AudioCaptureError.engineStartFailed("Cannot create Request")
        }
        request.shouldReportPartialResults = config.enablePartialResults
        // ★ 允許更長的靜音等待時間
        request.requiresOnDeviceRecognition = false
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        print("🎙️ Mic: format = \(recordingFormat.sampleRate)Hz / \(recordingFormat.channelCount)ch")
        
        inputNode.installTap(onBus: 0, bufferSize: config.bufferSize, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.recognitionRequest?.append(buffer)
            Task { await self.incrementBufferCount() }
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        startSpeechRecognition(recognizer: recognizer, request: request)
        
        _state = .capturing
        print("✅ Mic: audioEngine started, listening...")
    }
    
    // MARK: - Speech Recognition
    
    private func startSpeechRecognition(recognizer: SFSpeechRecognizer, request: SFSpeechAudioBufferRecognitionRequest) {
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            Task {
                if let result = result {
                    await self.markSpeechReceived()
                    let segment = TranscriptSegment(
                        text: result.bestTranscription.formattedString,
                        timestamp: Date(),
                        isFinal: result.isFinal,
                        confidence: result.bestTranscription.segments.last?.confidence ?? 0,
                        locale: self.config.speechLocale,
                        source: .microphone
                    )
                    await self.emitSegment(segment)
                }
                if let error = error {
                    await self.handleSpeechError(error)
                }
            }
        }
    }
    
    // MARK: - ★ Smart Error Handling
    
    private func handleSpeechError(_ error: Error) async {
        let nsError = error as NSError
        let code = nsError.code
        let description = error.localizedDescription
        
        // ★ "No speech detected" (code 1110) — 正常現象，不是錯誤
        // 用較長延遲重啟，避免快速循環
        if description.contains("No speech detected") || code == 1110 {
            if restartCount < 3 {
                print("💤 Mic: no speech yet (waiting 5s before restart #\(restartCount + 1))")
            }
            // ★ 等 5 秒再重啟（而不是 0.3 秒）
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await restartSpeechOnly()
            return
        }
        
        // ★ 60 秒 timeout (code 216) — 正常超時，快速重啟
        if nsError.domain == "kAFAssistantErrorDomain" && code == 216 {
            print("⏰ Mic: 60s timeout, restarting...")
            try? await Task.sleep(nanoseconds: 300_000_000)
            await restartSpeechOnly()
            return
        }
        
        // ★ 其他錯誤 — 記錄後重啟
        print("⚠️ Mic speech error [\(code)]: \(description)")
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        await restartSpeechOnly()
    }
    
    // MARK: - Stop
    
    func stop() async {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        streamContinuation?.finish()
        streamContinuation = nil
        _state = .idle
        print("⏹️ Mic: stopped (buffers: \(bufferCount), restarts: \(restartCount), gotSpeech: \(hasEverReceivedSpeech))")
    }
    
    // MARK: - Restart Speech Only
    
    private func restartSpeechOnly() async {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        
        guard _state.isActive else { return }  // 已停止則不重啟
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            print("❌ Mic: speech recognizer unavailable")
            return
        }
        
        let newRequest = SFSpeechAudioBufferRecognitionRequest()
        newRequest.shouldReportPartialResults = config.enablePartialResults
        self.recognitionRequest = newRequest
        
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: config.bufferSize, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.recognitionRequest?.append(buffer)
            Task { await self.incrementBufferCount() }
        }
        
        startSpeechRecognition(recognizer: recognizer, request: newRequest)
        
        restartCount += 1
        if restartCount <= 5 || restartCount % 10 == 0 {
            print("🔄 Mic: speech restarted (#\(restartCount))")
        }
    }
    
    // MARK: - Helpers
    
    private func markSpeechReceived() {
        if !hasEverReceivedSpeech {
            hasEverReceivedSpeech = true
            print("🎉 Mic: first speech recognized!")
        }
    }
    
    private func incrementBufferCount() {
        bufferCount += 1
        if bufferCount == 1 {
            print("🎙️ Mic: first audio buffer received")
        }
        if bufferCount % 1000 == 0 {
            print("🎙️ Mic: buffer count = \(bufferCount)")
        }
    }
    
    private func emitSegment(_ segment: TranscriptSegment) {
        streamContinuation?.yield(segment)
    }
}
