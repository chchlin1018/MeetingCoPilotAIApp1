// MicrophoneCaptureEngine.swift
// MeetingCopilot v4.3.1 — Fallback: Microphone Capture Engine
// Fixed: Use ON-DEVICE recognition + Debug logging for mic issues

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
    private var useOnDevice: Bool = false
    private var lastRMS: Float = 0
    private var silentBufferCount: Int = 0
    
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
        
        print("🎙️ [MIC-DEBUG] ====== MicrophoneCaptureEngine Starting ======")
        print("🎙️ [MIC-DEBUG] Locale: \(config.speechLocale.identifier)")
        
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        print("🎙️ [MIC-DEBUG] Mic permission: \(micStatus.rawValue) (0=notDetermined, 1=restricted, 2=denied, 3=authorized)")
        
        speechRecognizer = SFSpeechRecognizer(locale: config.speechLocale)
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            print("❌ [MIC-DEBUG] SFSpeechRecognizer NOT available for \(config.speechLocale.identifier)")
            throw AudioCaptureError.speechRecognizerUnavailable
        }
        
        useOnDevice = recognizer.supportsOnDeviceRecognition
        print("🎙️ [MIC-DEBUG] recognizer.isAvailable = \(recognizer.isAvailable)")
        print("🎙️ [MIC-DEBUG] recognizer.supportsOnDeviceRecognition = \(useOnDevice)")
        print("🎙️ [MIC-DEBUG] on-device recognition = \(useOnDevice ? "✅ YES" : "❌ NO (will use server)")")
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else {
            throw AudioCaptureError.engineStartFailed("Cannot create Request")
        }
        request.shouldReportPartialResults = config.enablePartialResults
        
        if useOnDevice {
            request.requiresOnDeviceRecognition = true
            print("🎙️ [MIC-DEBUG] request.requiresOnDeviceRecognition = TRUE")
        } else {
            print("⚠️ [MIC-DEBUG] on-device not available, using server (may conflict with remote)")
        }
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        print("🎙️ [MIC-DEBUG] inputNode format: \(recordingFormat.sampleRate)Hz / \(recordingFormat.channelCount)ch / \(recordingFormat.commonFormat.rawValue)")
        print("🎙️ [MIC-DEBUG] inputNode isVoiceProcessingEnabled: \(inputNode.isVoiceProcessingEnabled)")
        
        inputNode.installTap(onBus: 0, bufferSize: config.bufferSize, format: recordingFormat) { [weak self] buffer, time in
            guard let self = self else { return }
            self.recognitionRequest?.append(buffer)
            let rms = self.calculateRMS(buffer: buffer)
            Task { await self.incrementBufferCount(rms: rms) }
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        print("🎙️ [MIC-DEBUG] audioEngine.isRunning = \(audioEngine.isRunning)")
        
        startSpeechRecognition(recognizer: recognizer, request: request)
        
        _state = .capturing
        print("✅ [MIC-DEBUG] Mic: audioEngine started, listening... (mode: \(useOnDevice ? "on-device" : "server"))")
        print("🎙️ [MIC-DEBUG] ====== MicrophoneCaptureEngine Ready ======")
    }
    
    // MARK: - RMS 計算
    
    nonisolated private func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<frames {
            let sample = channelData[0][i]
            sum += sample * sample
        }
        return sqrt(sum / Float(frames))
    }
    
    // MARK: - Speech Recognition
    
    private func startSpeechRecognition(recognizer: SFSpeechRecognizer, request: SFSpeechAudioBufferRecognitionRequest) {
        print("🎙️ [MIC-DEBUG] Starting recognitionTask...")
        
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            Task {
                if let result = result {
                    let text = result.bestTranscription.formattedString
                    let isFinal = result.isFinal
                    let confidence = result.bestTranscription.segments.last?.confidence ?? 0
                    
                    let gotSpeechBefore = await self.hasEverReceivedSpeech
                    if !gotSpeechBefore || isFinal {
                        print("🎙️ [MIC-DEBUG] 🗣️ Speech result: isFinal=\(isFinal), confidence=\(String(format: "%.2f", confidence)), text=\"\(text.suffix(60))\"")
                    }
                    
                    await self.markSpeechReceived()
                    let segment = TranscriptSegment(
                        text: text, timestamp: Date(), isFinal: isFinal,
                        confidence: confidence, locale: self.config.speechLocale, source: .microphone
                    )
                    await self.emitSegment(segment)
                }
                if let error = error {
                    await self.handleSpeechError(error)
                }
            }
        }
        
        if let task = recognitionTask {
            print("🎙️ [MIC-DEBUG] recognitionTask created, state=\(task.state.rawValue) (0=starting, 1=running, 2=finishing, 3=canceling, 4=completed)")
        } else {
            print("❌ [MIC-DEBUG] recognitionTask is NIL! recognizer may have rejected the request")
        }
    }
    
    // MARK: - Smart Error Handling
    
    private func handleSpeechError(_ error: Error) async {
        let nsError = error as NSError
        let code = nsError.code
        let domain = nsError.domain
        let description = error.localizedDescription
        
        print("⚠️ [MIC-DEBUG] Speech error: domain=\(domain), code=\(code), desc=\"\(description)\"")
        print("⚠️ [MIC-DEBUG]   buffers=\(bufferCount), restarts=\(restartCount), gotSpeech=\(hasEverReceivedSpeech), lastRMS=\(String(format: "%.6f", lastRMS))")
        
        if description.contains("No speech detected") || code == 1110 {
            if restartCount < 5 {
                print("💤 [MIC-DEBUG] No speech yet (RMS=\(String(format: "%.6f", lastRMS)), silent=\(silentBufferCount)/\(bufferCount)) — waiting 5s before restart #\(restartCount + 1)")
            }
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await restartSpeechOnly()
            return
        }
        
        if domain == "kAFAssistantErrorDomain" && code == 216 {
            print("⏰ [MIC-DEBUG] 60s timeout, restarting... (buffers=\(bufferCount))")
            try? await Task.sleep(nanoseconds: 300_000_000)
            await restartSpeechOnly()
            return
        }
        
        if code == 301 {
            print("⚠️ [MIC-DEBUG] recognition CANCELED (code 301) — server conflict? restarting in 1s...")
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await restartSpeechOnly()
            return
        }
        
        print("⚠️ [MIC-DEBUG] Unknown speech error [\(code)]: \(description)")
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
        print("⏹️ [MIC-DEBUG] Mic: stopped (buffers: \(bufferCount), restarts: \(restartCount), gotSpeech: \(hasEverReceivedSpeech), onDevice: \(useOnDevice), lastRMS: \(String(format: "%.6f", lastRMS)), silentBuffers: \(silentBufferCount))")
    }
    
    // MARK: - Restart Speech Only
    
    private func restartSpeechOnly() async {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        
        guard _state.isActive else {
            print("🎙️ [MIC-DEBUG] restartSpeechOnly: state not active, skipping")
            return
        }
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            print("❌ [MIC-DEBUG] restartSpeechOnly: recognizer unavailable!")
            return
        }
        
        let newRequest = SFSpeechAudioBufferRecognitionRequest()
        newRequest.shouldReportPartialResults = config.enablePartialResults
        if useOnDevice { newRequest.requiresOnDeviceRecognition = true }
        self.recognitionRequest = newRequest
        
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: config.bufferSize, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.recognitionRequest?.append(buffer)
            let rms = self.calculateRMS(buffer: buffer)
            Task { await self.incrementBufferCount(rms: rms) }
        }
        
        startSpeechRecognition(recognizer: recognizer, request: newRequest)
        
        restartCount += 1
        if restartCount <= 5 || restartCount % 10 == 0 {
            print("🔄 [MIC-DEBUG] speech restarted (#\(restartCount), mode: \(useOnDevice ? "on-device" : "server"), audioRunning: \(audioEngine.isRunning))")
        }
    }
    
    // MARK: - Helpers
    
    private func markSpeechReceived() {
        if !hasEverReceivedSpeech {
            hasEverReceivedSpeech = true
            print("🎉 [MIC-DEBUG] FIRST SPEECH RECOGNIZED! (mode: \(useOnDevice ? "on-device" : "server"), buffers: \(bufferCount), restarts: \(restartCount))")
        }
    }
    
    private func incrementBufferCount(rms: Float) {
        bufferCount += 1
        lastRMS = rms
        if rms < 0.001 { silentBufferCount += 1 }
        
        if bufferCount <= 10 {
            let db = rms > 0 ? 20 * log10(rms) : -120
            print("🎙️ [MIC-DEBUG] buffer #\(bufferCount): RMS=\(String(format: "%.6f", rms)) (\(String(format: "%.1f", db))dB) \(rms < 0.001 ? "🔇 SILENT" : rms < 0.01 ? "🔈 quiet" : "🔊 AUDIO")")
        }
        
        if bufferCount % 500 == 0 {
            let silentPct = bufferCount > 0 ? (Float(silentBufferCount) / Float(bufferCount)) * 100 : 0
            print("🎙️ [MIC-DEBUG] buffer #\(bufferCount): lastRMS=\(String(format: "%.6f", rms)), silent=\(silentBufferCount) (\(String(format: "%.0f", silentPct))%), gotSpeech=\(hasEverReceivedSpeech)")
        }
    }
    
    private func emitSegment(_ segment: TranscriptSegment) {
        streamContinuation?.yield(segment)
    }
}
