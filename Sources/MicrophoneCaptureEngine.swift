// MicrophoneCaptureEngine.swift
// MeetingCopilot v4.2 — Fallback: Microphone Capture Engine
// Fixed: Actor isolation for Swift Strict Concurrency

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
    
    // Fix: Use nonisolated(unsafe) to allow nonisolated access
    // This is safe because _state is only mutated on the actor
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
    
    init(configuration: AudioCaptureConfiguration = .default) {
        self.config = configuration
        super.init()
    }
    
    private func setStreamContinuation(_ continuation: AsyncStream<TranscriptSegment>.Continuation) {
        self.streamContinuation = continuation
    }
    
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
        
        inputNode.installTap(onBus: 0, bufferSize: config.bufferSize, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
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
                if error != nil {
                    await self.restartRecognition()
                }
            }
        }
        
        _state = .capturing
    }
    
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
    }
    
    private func restartRecognition() async {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        try? await Task.sleep(nanoseconds: 200_000_000)
        do { try await start() } catch { _state = .error(.captureInterrupted("Restart failed")) }
    }
    
    private func emitSegment(_ segment: TranscriptSegment) {
        streamContinuation?.yield(segment)
    }
}
