// SystemAudioCaptureEngine.swift
// MeetingCopilot v4.2 — Primary: ScreenCaptureKit System Audio Capture
// Fixed: Actor isolation for Swift Strict Concurrency

import Foundation
import ScreenCaptureKit
import AVFoundation
import Speech

actor SystemAudioCaptureEngine: NSObject, AudioCaptureEngine {
    
    nonisolated let engineType: AudioCaptureEngineType = .systemAudio
    
    nonisolated var transcriptStream: AsyncStream<TranscriptSegment> {
        AsyncStream { continuation in
            Task { await self.setStreamContinuation(continuation) }
        }
    }
    
    // Fix: nonisolated(unsafe) for Swift Strict Concurrency
    // Safe because _state is only mutated within the actor
    nonisolated(unsafe) private var _state: AudioCaptureState = .idle
    
    nonisolated var state: AudioCaptureState {
        get { _state }
    }
    
    // MARK: - Internal State
    
    private var streamContinuation: AsyncStream<TranscriptSegment>.Continuation?
    
    // ScreenCaptureKit
    private var captureStream: SCStream?
    private var streamOutput: AudioStreamOutput?
    
    // Speech Recognition
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    private let config: AudioCaptureConfiguration
    private var detectedMeetingApp: MeetingApp?
    private var audioConverter: AVAudioConverter?
    private var speechFormat: AVAudioFormat?
    
    // MARK: - Init
    
    init(configuration: AudioCaptureConfiguration = .default) {
        self.config = configuration
        super.init()
    }
    
    private func setStreamContinuation(_ continuation: AsyncStream<TranscriptSegment>.Continuation) {
        self.streamContinuation = continuation
    }
    
    // MARK: - Start Capture
    
    func start() async throws {
        guard !_state.isActive else { return }
        _state = .preparing
        
        // Step 1: Speech permission
        try await requestSpeechPermission()
        
        // Step 2: Init speech recognizer
        try setupSpeechRecognizer()
        
        // Step 3: Get shareable content
        let availableContent = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        )
        
        // Step 4: Find meeting app
        let targetApp = try findMeetingApp(in: availableContent)
        detectedMeetingApp = targetApp
        
        // Step 5: Configure ScreenCaptureKit for audio-only
        let filter = SCContentFilter(
            desktopIndependentWindow: try findMainWindow(for: targetApp, in: availableContent)
        )
        
        let streamConfig = SCStreamConfiguration()
        streamConfig.capturesAudio = true
        streamConfig.excludesCurrentProcessAudio = true
        streamConfig.width = 1
        streamConfig.height = 1
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        streamConfig.showsCursor = false
        streamConfig.sampleRate = Int(config.sampleRate)
        streamConfig.channelCount = config.channelCount
        
        // Step 6: Stream output handler
        streamOutput = AudioStreamOutput(
            onAudioBuffer: { [weak self] sampleBuffer in
                Task { [weak self] in
                    await self?.processAudioBuffer(sampleBuffer)
                }
            },
            onError: { [weak self] error in
                Task { [weak self] in
                    await self?.handleCaptureError(error)
                }
            }
        )
        
        // Step 7: Start SCStream
        captureStream = SCStream(filter: filter, configuration: streamConfig, delegate: streamOutput)
        
        guard let captureStream = captureStream, let streamOutput = streamOutput else {
            throw AudioCaptureError.engineStartFailed("Cannot create SCStream")
        }
        
        try captureStream.addStreamOutput(
            streamOutput,
            type: .audio,
            sampleHandlerQueue: DispatchQueue(
                label: "com.meetingcopilot.audio.capture",
                qos: .userInteractive
            )
        )
        
        // Step 8: Audio format converter (48kHz -> 16kHz)
        try setupAudioConverter()
        
        // Step 9: Start speech recognition
        try startSpeechRecognition()
        
        // Step 10: Begin capture
        try await captureStream.startCapture()
        
        _state = .capturing
        print("SystemAudioCaptureEngine started: \(targetApp.displayName)")
    }
    
    // MARK: - Stop
    
    func stop() async {
        if let stream = captureStream {
            try? await stream.stopCapture()
        }
        captureStream = nil
        streamOutput = nil
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioConverter = nil
        speechFormat = nil
        detectedMeetingApp = nil
        streamContinuation?.finish()
        streamContinuation = nil
        _state = .idle
    }
    
    // MARK: - Speech Permission
    
    private func requestSpeechPermission() async throws {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard status == .authorized else {
            throw AudioCaptureError.permissionDenied
        }
    }
    
    // MARK: - Speech Recognizer Setup
    
    private func setupSpeechRecognizer() throws {
        speechRecognizer = SFSpeechRecognizer(locale: config.speechLocale)
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw AudioCaptureError.speechRecognizerUnavailable
        }
        if recognizer.supportsOnDeviceRecognition {
            print("  On-device recognition available (fallback)")
        }
    }
    
    // MARK: - Detect Meeting App
    
    private func findMeetingApp(in content: SCShareableContent) throws -> MeetingApp {
        if config.autoDetectMeetingApp {
            for app in content.applications {
                if let meetingApp = MeetingApp.from(bundleID: app.bundleIdentifier) {
                    print("  Detected: \(meetingApp.displayName)")
                    return meetingApp
                }
            }
            
            let browserBundles = [
                "com.google.Chrome", "com.apple.Safari",
                "com.microsoft.edgemac", "org.mozilla.firefox", "com.brave.Browser"
            ]
            
            for app in content.applications {
                if browserBundles.contains(app.bundleIdentifier) {
                    for window in content.windows where window.owningApplication?.bundleIdentifier == app.bundleIdentifier {
                        if let title = window.title,
                           (title.contains("Meet") || title.contains("meet.google.com")) {
                            print("  Detected Google Meet in \(app.applicationName)")
                            return .googleMeet
                        }
                    }
                }
            }
        }
        throw AudioCaptureError.noAudioSourceFound
    }
    
    // MARK: - Find Main Window
    
    private func findMainWindow(for meetingApp: MeetingApp, in content: SCShareableContent) throws -> SCWindow {
        let appWindows = content.windows.filter { window in
            window.owningApplication?.bundleIdentifier == meetingApp.bundleIdentifier
            && window.isOnScreen
            && (window.frame.width > 200 && window.frame.height > 200)
        }
        guard let mainWindow = appWindows.max(by: {
            $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height
        }) else {
            throw AudioCaptureError.noAudioSourceFound
        }
        return mainWindow
    }
    
    // MARK: - Audio Converter (48kHz -> 16kHz)
    
    private func setupAudioConverter() throws {
        let captureFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: config.sampleRate,
            channels: AVAudioChannelCount(config.channelCount),
            interleaved: false
        )
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000.0,
            channels: 1,
            interleaved: false
        )
        guard let captureFormat = captureFormat, let targetFormat = targetFormat else {
            throw AudioCaptureError.configurationFailed("Cannot create audio format")
        }
        audioConverter = AVAudioConverter(from: captureFormat, to: targetFormat)
        speechFormat = targetFormat
        guard audioConverter != nil else {
            throw AudioCaptureError.configurationFailed("Cannot create audio converter")
        }
    }
    
    // MARK: - Speech Recognition
    
    private func startSpeechRecognition() throws {
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else {
            throw AudioCaptureError.engineStartFailed("Cannot create recognition request")
        }
        request.shouldReportPartialResults = config.enablePartialResults
        
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            Task { [weak self] in
                guard let self = self else { return }
                if let result = result {
                    let segment = TranscriptSegment(
                        text: result.bestTranscription.formattedString,
                        timestamp: Date(),
                        isFinal: result.isFinal,
                        confidence: result.bestTranscription.segments.last?.confidence ?? 0,
                        locale: self.config.speechLocale,
                        source: .systemAudio
                    )
                    await self.emitSegment(segment)
                }
                if let error = error {
                    let nsError = error as NSError
                    if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 {
                        await self.restartSpeechRecognition()
                    } else {
                        await self.handleCaptureError(
                            AudioCaptureError.captureInterrupted(error.localizedDescription)
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Auto-restart (60s timeout handling)
    
    private func restartSpeechRecognition() async {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        try? await Task.sleep(nanoseconds: 200_000_000)
        do {
            try startSpeechRecognition()
        } catch {
            await handleCaptureError(
                AudioCaptureError.engineStartFailed("Speech restart failed: \(error)")
            )
        }
    }
    
    // MARK: - Process Audio Buffer from ScreenCaptureKit
    
    private func processAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let formatDescription = sampleBuffer.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return
        }
        guard let pcmBuffer = convertToPCMBuffer(sampleBuffer: sampleBuffer, asbd: asbd.pointee) else {
            return
        }
        
        if let converter = audioConverter, let targetFormat = speechFormat {
            let ratio = config.sampleRate / 16000.0
            let targetFrameCount = AVAudioFrameCount(Double(pcmBuffer.frameLength) / ratio)
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetFrameCount) else { return }
            var conversionError: NSError?
            let status = converter.convert(to: convertedBuffer, error: &conversionError) { _, outStatus in
                outStatus.pointee = .haveData
                return pcmBuffer
            }
            if status == .haveData {
                recognitionRequest?.append(convertedBuffer)
            }
        } else {
            recognitionRequest?.append(pcmBuffer)
        }
    }
    
    // MARK: - CMSampleBuffer -> AVAudioPCMBuffer
    
    private func convertToPCMBuffer(sampleBuffer: CMSampleBuffer, asbd: AudioStreamBasicDescription) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: asbd.mSampleRate,
            channels: AVAudioChannelCount(asbd.mChannelsPerFrame),
            interleaved: asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        ) else { return nil }
        
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else { return nil }
        pcmBuffer.frameLength = AVAudioFrameCount(frameCount)
        
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }
        var lengthAtOffset: Int = 0
        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            blockBuffer, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset,
            totalLengthOut: &totalLength, dataPointerOut: &dataPointer
        )
        guard status == kCMBlockBufferNoErr, let data = dataPointer else { return nil }
        
        if let channelData = pcmBuffer.floatChannelData {
            let byteCount = frameCount * MemoryLayout<Float>.size
            memcpy(channelData[0], data, min(byteCount, totalLength))
        }
        return pcmBuffer
    }
    
    private func emitSegment(_ segment: TranscriptSegment) {
        streamContinuation?.yield(segment)
    }
    
    private func handleCaptureError(_ error: AudioCaptureError) {
        _state = .error(error)
    }
}

// MARK: - SCStream Audio Output Handler

final class AudioStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate {
    
    private let onAudioBuffer: @Sendable (CMSampleBuffer) -> Void
    private let onError: @Sendable (AudioCaptureError) -> Void
    
    init(
        onAudioBuffer: @escaping @Sendable (CMSampleBuffer) -> Void,
        onError: @escaping @Sendable (AudioCaptureError) -> Void
    ) {
        self.onAudioBuffer = onAudioBuffer
        self.onError = onError
        super.init()
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard sampleBuffer.isValid, CMSampleBufferGetNumSamples(sampleBuffer) > 0 else { return }
        onAudioBuffer(sampleBuffer)
    }
    
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onError(.captureInterrupted(error.localizedDescription))
    }
}
