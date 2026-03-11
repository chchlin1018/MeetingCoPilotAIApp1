// MicrophoneCaptureEngine.swift
// MeetingCopilot v4.3.1 — Fallback: Microphone Capture Engine
// Fixed: restart bug + debug logging

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
    
    nonisolated var state: AudioCaptureState {
        _state
    }
    
    private var streamContinuation: AsyncStream<TranscriptSegment>.Continuation?
    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let config: AudioCaptureConfiguration
    private var bufferCount: Int = 0
    private var restartCount: Int = 0
    
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
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        print("🎙️ Mic: format = \(recordingFormat.sampleRate)Hz / \(recordingFormat.channelCount)ch")
        
        inputNode.installTap(onBus: 0, bufferSize: config.bufferSize, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.recognitionRequest?.append(buffer)
            
            // ★ 計數（用 Task 避免 actor isolation 問題）
            Task { await self.incrementBufferCount() }
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        startSpeechRecognition(recognizer: recognizer, request: request)
        
        _state = .capturing
        print("✅ Mic: audioEngine started, listening...")
    }
    
    // MARK: - Speech Recognition (可重啟）
    
    private func startSpeechRecognition(recognizer: SFSpeechRecognizer, request: SFSpeechAudioBufferRecognitionRequest) {
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            Task {
                if let result = result {
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
                    print("⚠️ Mic speech error: \(error.localizedDescription)")
                    await self.restartSpeechOnly()
                }
            }
        }
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
        print("⏹️ Mic: stopped (buffers: \(bufferCount), restarts: \(restartCount))")
    }
    
    // MARK: - ★ Restart Speech Only (不重啟 audioEngine)
    //
    // 舊的 bug：restartRecognition() 呼叫 start()，但 start() 有
    // guard !_state.isActive → state 還是 .capturing → 直接 return
    // → 語音辨識就死了！
    //
    // 修復：僅重啟 Speech Recognition，不動 audioEngine（麥克風持續擷取）
    
    private func restartSpeechOnly() async {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        
        try? await Task.sleep(nanoseconds: 300_000_000)
        
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            print("❌ Mic: speech recognizer unavailable for restart")
            return
        }
        
        // ★ 建立新的 recognition request
        let newRequest = SFSpeechAudioBufferRecognitionRequest()
        newRequest.shouldReportPartialResults = config.enablePartialResults
        self.recognitionRequest = newRequest
        
        // ★ 重新安裝 tap（指向新的 request）
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: config.bufferSize, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.recognitionRequest?.append(buffer)
            Task { await self.incrementBufferCount() }
        }
        
        // ★ 啟動新的 recognition task
        startSpeechRecognition(recognizer: recognizer, request: newRequest)
        
        restartCount += 1
        print("🔄 Mic: speech restarted (#\(restartCount), buffers so far: \(bufferCount))")
    }
    
    // MARK: - Helpers
    
    private func incrementBufferCount() {
        bufferCount += 1
        if bufferCount == 1 {
            print("🎙️ Mic: first audio buffer received")
        }
        // 每 500 個 buffer log 一次（約 10 秒）
        if bufferCount % 500 == 0 {
            print("🎙️ Mic: buffer count = \(bufferCount)")
        }
    }
    
    private func emitSegment(_ segment: TranscriptSegment) {
        streamContinuation?.yield(segment)
    }
}
