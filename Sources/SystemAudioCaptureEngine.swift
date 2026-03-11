// SystemAudioCaptureEngine.swift
// MeetingCopilot v4.3.1 — Primary: ScreenCaptureKit System Audio Capture
// Fixed: Dynamic audio format detection + actor isolation

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
    
    // ★ Dynamic audio format (lazy-initialized from first buffer)
    private var audioConverter: AVAudioConverter?
    private var speechFormat: AVAudioFormat?
    private var lastInputFormat: AVAudioFormat?
    private var converterInitialized = false
    private var bufferCount: Int = 0
    private var convertFailCount: Int = 0
    
    // MARK: - Public: 偵測到的 App
    
    var detectedAppName: String? {
        detectedMeetingApp?.displayName
    }
    
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
        
        // ★ Note: Audio converter is NO LONGER pre-initialized here
        // It will be dynamically created from the first actual audio buffer
        // This avoids format mismatch issues (-10877)
        
        // Step 8: Prepare speech format target (16kHz mono for Apple Speech)
        speechFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000.0,
            channels: 1,
            interleaved: false
        )
        
        // Step 9: Start speech recognition
        try startSpeechRecognition()
        
        // Step 10: Begin capture
        try await captureStream.startCapture()
        
        _state = .capturing
        print("🎯 SystemAudioCaptureEngine started: \(targetApp.displayName)")
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
        lastInputFormat = nil
        converterInitialized = false
        bufferCount = 0
        convertFailCount = 0
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
                    print("  📱 Detected: \(meetingApp.displayName) (\(app.bundleIdentifier))")
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
                            print("  📱 Detected Google Meet in \(app.applicationName)")
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
    
    // MARK: - ★ Dynamic Audio Converter (lazy from first buffer)
    
    private func ensureConverter(for inputFormat: AVAudioFormat) -> Bool {
        guard let targetFormat = speechFormat else { return false }
        
        // Already initialized with same format
        if converterInitialized, let last = lastInputFormat,
           last.sampleRate == inputFormat.sampleRate &&
           last.channelCount == inputFormat.channelCount {
            return audioConverter != nil
        }
        
        // Log format detection
        if !converterInitialized {
            print("🔊 Audio format detected: \(inputFormat.sampleRate)Hz / \(inputFormat.channelCount)ch / \(inputFormat.commonFormat.rawValue)")
            print("🔊 Target format: \(targetFormat.sampleRate)Hz / \(targetFormat.channelCount)ch")
        } else {
            print("⚠️ Audio format CHANGED: \(inputFormat.sampleRate)Hz / \(inputFormat.channelCount)ch")
        }
        
        // Create converter dynamically
        audioConverter = AVAudioConverter(from: inputFormat, to: targetFormat)
        lastInputFormat = inputFormat
        converterInitialized = true
        
        if audioConverter == nil {
            print("❌ Cannot create audio converter from \(inputFormat.sampleRate)Hz to \(targetFormat.sampleRate)Hz")
            return false
        }
        
        print("✅ Audio converter created: \(inputFormat.sampleRate)Hz → \(targetFormat.sampleRate)Hz")
        return true
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
                        print("⚠️ Speech error: \(error.localizedDescription)")
                        await self.restartSpeechRecognition()
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
        try? await Task.sleep(nanoseconds: 300_000_000)
        do {
            try startSpeechRecognition()
            print("🔄 Speech recognition restarted (buffer count: \(bufferCount))")
        } catch {
            await handleCaptureError(
                AudioCaptureError.engineStartFailed("Speech restart failed: \(error)")
            )
        }
    }
    
    // MARK: - ★ Process Audio Buffer (with dynamic format detection)
    
    private func processAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let formatDescription = sampleBuffer.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return
        }
        
        bufferCount += 1
        
        // ★ Method 1: Try direct append from CMSampleBuffer (most reliable)
        if appendDirectly(sampleBuffer: sampleBuffer, asbd: asbd.pointee) {
            return
        }
        
        // ★ Method 2: Convert to PCM buffer then downsample
        guard let pcmBuffer = convertToPCMBuffer(sampleBuffer: sampleBuffer, asbd: asbd.pointee) else {
            return
        }
        
        let inputFormat = pcmBuffer.format
        
        // Same sample rate as target — append directly
        if abs(inputFormat.sampleRate - 16000.0) < 100 {
            recognitionRequest?.append(pcmBuffer)
            return
        }
        
        // Need conversion — ensure converter exists for this format
        guard ensureConverter(for: inputFormat),
              let converter = audioConverter,
              let targetFormat = speechFormat else {
            // Fallback: try appending raw buffer anyway
            recognitionRequest?.append(pcmBuffer)
            return
        }
        
        let ratio = inputFormat.sampleRate / targetFormat.sampleRate
        let targetFrameCount = AVAudioFrameCount(Double(pcmBuffer.frameLength) / ratio)
        guard targetFrameCount > 0,
              let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetFrameCount) else {
            return
        }
        
        var conversionError: NSError?
        var hasData = false
        let status = converter.convert(to: convertedBuffer, error: &conversionError) { _, outStatus in
            outStatus.pointee = .haveData
            hasData = true
            return pcmBuffer
        }
        
        if status == .haveData {
            recognitionRequest?.append(convertedBuffer)
        } else if status == .error {
            convertFailCount += 1
            if convertFailCount <= 3 {
                print("⚠️ Convert error #\(convertFailCount): \(conversionError?.localizedDescription ?? "unknown") — trying direct append")
            }
            // ★ Fallback: reset converter and try raw append
            converterInitialized = false
            audioConverter = nil
            recognitionRequest?.append(pcmBuffer)
        }
    }
    
    // MARK: - ★ Direct append from CMSampleBuffer (bypass converter)
    
    private func appendDirectly(sampleBuffer: CMSampleBuffer, asbd: AudioStreamBasicDescription) -> Bool {
        // If the source is already close to 16kHz, we can skip conversion
        // Apple Speech is somewhat flexible on input rates
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: asbd.mSampleRate,
            channels: AVAudioChannelCount(asbd.mChannelsPerFrame),
            interleaved: false
        ) else { return false }
        
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else { return false }
        
        // For sample rates that Apple Speech can handle natively (16k-48k)
        // Try creating a buffer and appending directly
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return false
        }
        pcmBuffer.frameLength = AVAudioFrameCount(frameCount)
        
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return false }
        var lengthAtOffset: Int = 0
        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            blockBuffer, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset,
            totalLengthOut: &totalLength, dataPointerOut: &dataPointer
        )
        guard status == kCMBlockBufferNoErr, let data = dataPointer else { return false }
        
        if let channelData = pcmBuffer.floatChannelData {
            let byteCount = frameCount * MemoryLayout<Float>.size
            memcpy(channelData[0], data, min(byteCount, totalLength))
        }
        
        // ★ Directly append to speech recognition (Apple Speech handles resampling)
        recognitionRequest?.append(pcmBuffer)
        
        // Log first buffer info
        if bufferCount == 1 {
            print("🔊 First audio buffer: \(asbd.mSampleRate)Hz / \(asbd.mChannelsPerFrame)ch / \(frameCount) frames")
            print("🔊 Strategy: direct append (Apple Speech handles resampling)")
        }
        
        return true
    }
    
    // MARK: - CMSampleBuffer -> AVAudioPCMBuffer (fallback)
    
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
