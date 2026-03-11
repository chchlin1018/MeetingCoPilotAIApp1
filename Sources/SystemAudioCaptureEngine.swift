// SystemAudioCaptureEngine.swift
// MeetingCopilot v4.3.1 — Primary: ScreenCaptureKit System Audio Capture
// Fixed: Dynamic audio format + App priority detection + manual app selection

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
    private var captureStream: SCStream?
    private var streamOutput: AudioStreamOutput?
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let config: AudioCaptureConfiguration
    private var detectedMeetingApp: MeetingApp?
    private var audioConverter: AVAudioConverter?
    private var speechFormat: AVAudioFormat?
    private var lastInputFormat: AVAudioFormat?
    private var converterInitialized = false
    private var bufferCount: Int = 0
    private var convertFailCount: Int = 0
    
    var detectedAppName: String? {
        detectedMeetingApp?.displayName
    }
    
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
        
        try await requestSpeechPermission()
        try setupSpeechRecognizer()
        
        let availableContent = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        )
        
        // ★ 如果有指定 targetApp，直接使用；否則自動偵測
        let targetApp: MeetingApp
        if let specified = config.targetApp {
            targetApp = specified
            print("🎯 Manual selection: \(specified.displayName)")
        } else {
            targetApp = try findMeetingApp(in: availableContent)
        }
        detectedMeetingApp = targetApp
        
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
        
        streamOutput = AudioStreamOutput(
            onAudioBuffer: { [weak self] sampleBuffer in
                Task { [weak self] in await self?.processAudioBuffer(sampleBuffer) }
            },
            onError: { [weak self] error in
                Task { [weak self] in await self?.handleCaptureError(error) }
            }
        )
        
        captureStream = SCStream(filter: filter, configuration: streamConfig, delegate: streamOutput)
        
        guard let captureStream = captureStream, let streamOutput = streamOutput else {
            throw AudioCaptureError.engineStartFailed("Cannot create SCStream")
        }
        
        try captureStream.addStreamOutput(
            streamOutput, type: .audio,
            sampleHandlerQueue: DispatchQueue(label: "com.meetingcopilot.audio.capture", qos: .userInteractive)
        )
        
        speechFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000.0, channels: 1, interleaved: false)
        try startSpeechRecognition()
        try await captureStream.startCapture()
        
        _state = .capturing
        print("🎯 SystemAudioCaptureEngine started: \(targetApp.displayName)")
    }
    
    // MARK: - Stop
    
    func stop() async {
        if let stream = captureStream { try? await stream.stopCapture() }
        captureStream = nil; streamOutput = nil
        recognitionRequest?.endAudio(); recognitionTask?.cancel()
        recognitionTask = nil; recognitionRequest = nil
        audioConverter = nil; speechFormat = nil; lastInputFormat = nil
        converterInitialized = false; bufferCount = 0; convertFailCount = 0
        detectedMeetingApp = nil
        streamContinuation?.finish(); streamContinuation = nil
        _state = .idle
    }
    
    // MARK: - Speech Permission
    
    private func requestSpeechPermission() async throws {
        let status = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { s in cont.resume(returning: s) }
        }
        guard status == .authorized else { throw AudioCaptureError.permissionDenied }
    }
    
    private func setupSpeechRecognizer() throws {
        speechRecognizer = SFSpeechRecognizer(locale: config.speechLocale)
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw AudioCaptureError.speechRecognizerUnavailable
        }
        if recognizer.supportsOnDeviceRecognition {
            print("  On-device recognition available (fallback)")
        }
    }
    
    // MARK: - Smart App Detection
    
    private func findMeetingApp(in content: SCShareableContent) throws -> MeetingApp {
        guard config.autoDetectMeetingApp else {
            throw AudioCaptureError.noAudioSourceFound
        }
        
        struct DetectedApp {
            let app: MeetingApp; let hasActiveWindow: Bool
            let windowArea: CGFloat; let priority: Int
        }
        
        var candidates: [DetectedApp] = []
        
        for app in content.applications {
            guard let meetingApp = MeetingApp.from(bundleID: app.bundleIdentifier) else { continue }
            let activeWindows = content.windows.filter { w in
                w.owningApplication?.bundleIdentifier == app.bundleIdentifier
                && w.isOnScreen && w.frame.width > 200 && w.frame.height > 200
            }
            let hasActive = !activeWindows.isEmpty
            let maxArea = activeWindows.map { $0.frame.width * $0.frame.height }.max() ?? 0
            print("  🔍 Scan: \(meetingApp.displayName) | active=\(hasActive) | area=\(Int(maxArea)) | priority=\(meetingApp.detectionPriority)")
            candidates.append(DetectedApp(app: meetingApp, hasActiveWindow: hasActive, windowArea: maxArea, priority: meetingApp.detectionPriority))
        }
        
        let browserBundles = ["com.google.Chrome", "com.apple.Safari", "com.microsoft.edgemac", "org.mozilla.firefox"]
        for app in content.applications {
            if browserBundles.contains(app.bundleIdentifier) {
                for window in content.windows where window.owningApplication?.bundleIdentifier == app.bundleIdentifier {
                    if let title = window.title, (title.contains("Meet") || title.contains("meet.google.com")) {
                        let area = window.frame.width * window.frame.height
                        print("  🔍 Scan: Google Meet in \(app.applicationName) | active=true | area=\(Int(area)) | priority=1")
                        candidates.append(DetectedApp(app: .googleMeet, hasActiveWindow: true, windowArea: area, priority: 1))
                        break
                    }
                }
            }
        }
        
        let sorted = candidates.sorted { a, b in
            if a.hasActiveWindow != b.hasActiveWindow { return a.hasActiveWindow }
            if a.priority != b.priority { return a.priority < b.priority }
            return a.windowArea > b.windowArea
        }
        
        if let best = sorted.first(where: { $0.hasActiveWindow }) {
            print("  📱 Selected: \(best.app.displayName) (priority=\(best.priority), area=\(Int(best.windowArea)))")
            return best.app
        }
        
        throw AudioCaptureError.noAudioSourceFound
    }
    
    private func findMainWindow(for meetingApp: MeetingApp, in content: SCShareableContent) throws -> SCWindow {
        let appWindows = content.windows.filter { w in
            w.owningApplication?.bundleIdentifier == meetingApp.bundleIdentifier
            && w.isOnScreen && w.frame.width > 200 && w.frame.height > 200
        }
        guard let mainWindow = appWindows.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
            throw AudioCaptureError.noAudioSourceFound
        }
        return mainWindow
    }
    
    // MARK: - Dynamic Audio Converter
    
    private func ensureConverter(for inputFormat: AVAudioFormat) -> Bool {
        guard let targetFormat = speechFormat else { return false }
        if converterInitialized, let last = lastInputFormat,
           last.sampleRate == inputFormat.sampleRate && last.channelCount == inputFormat.channelCount {
            return audioConverter != nil
        }
        if !converterInitialized {
            print("🔊 Audio format detected: \(inputFormat.sampleRate)Hz / \(inputFormat.channelCount)ch")
        }
        audioConverter = AVAudioConverter(from: inputFormat, to: targetFormat)
        lastInputFormat = inputFormat; converterInitialized = true
        if audioConverter == nil { print("❌ Cannot create audio converter"); return false }
        print("✅ Audio converter: \(inputFormat.sampleRate)Hz → \(targetFormat.sampleRate)Hz")
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
                        text: result.bestTranscription.formattedString, timestamp: Date(),
                        isFinal: result.isFinal,
                        confidence: result.bestTranscription.segments.last?.confidence ?? 0,
                        locale: self.config.speechLocale, source: .systemAudio
                    )
                    await self.emitSegment(segment)
                }
                if let error = error {
                    print("⚠️ Speech error: \(error.localizedDescription)")
                    await self.restartSpeechRecognition()
                }
            }
        }
    }
    
    private func restartSpeechRecognition() async {
        recognitionRequest?.endAudio(); recognitionTask?.cancel()
        recognitionTask = nil; recognitionRequest = nil
        try? await Task.sleep(nanoseconds: 300_000_000)
        do {
            try startSpeechRecognition()
            print("🔄 Speech recognition restarted (buffer count: \(bufferCount))")
        } catch {
            await handleCaptureError(.engineStartFailed("Speech restart failed: \(error)"))
        }
    }
    
    // MARK: - Process Audio Buffer
    
    private func processAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let formatDescription = sampleBuffer.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else { return }
        bufferCount += 1
        if appendDirectly(sampleBuffer: sampleBuffer, asbd: asbd.pointee) { return }
        guard let pcmBuffer = convertToPCMBuffer(sampleBuffer: sampleBuffer, asbd: asbd.pointee) else { return }
        let inputFormat = pcmBuffer.format
        if abs(inputFormat.sampleRate - 16000.0) < 100 { recognitionRequest?.append(pcmBuffer); return }
        guard ensureConverter(for: inputFormat), let converter = audioConverter, let targetFormat = speechFormat else {
            recognitionRequest?.append(pcmBuffer); return
        }
        let ratio = inputFormat.sampleRate / targetFormat.sampleRate
        let targetFrameCount = AVAudioFrameCount(Double(pcmBuffer.frameLength) / ratio)
        guard targetFrameCount > 0, let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetFrameCount) else { return }
        var conversionError: NSError?
        let status = converter.convert(to: convertedBuffer, error: &conversionError) { _, outStatus in
            outStatus.pointee = .haveData; return pcmBuffer
        }
        if status == .haveData { recognitionRequest?.append(convertedBuffer) }
        else if status == .error {
            convertFailCount += 1
            if convertFailCount <= 3 { print("⚠️ Convert error #\(convertFailCount)") }
            converterInitialized = false; audioConverter = nil
            recognitionRequest?.append(pcmBuffer)
        }
    }
    
    private func appendDirectly(sampleBuffer: CMSampleBuffer, asbd: AudioStreamBasicDescription) -> Bool {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: asbd.mSampleRate, channels: AVAudioChannelCount(asbd.mChannelsPerFrame), interleaved: false) else { return false }
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0, let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else { return false }
        pcmBuffer.frameLength = AVAudioFrameCount(frameCount)
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return false }
        var lengthAtOffset = 0, totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
        guard status == kCMBlockBufferNoErr, let data = dataPointer else { return false }
        if let channelData = pcmBuffer.floatChannelData {
            memcpy(channelData[0], data, min(frameCount * MemoryLayout<Float>.size, totalLength))
        }
        recognitionRequest?.append(pcmBuffer)
        if bufferCount == 1 {
            print("🔊 First audio buffer: \(asbd.mSampleRate)Hz / \(asbd.mChannelsPerFrame)ch / \(frameCount) frames")
            print("🔊 Strategy: direct append (Apple Speech handles resampling)")
        }
        return true
    }
    
    private func convertToPCMBuffer(sampleBuffer: CMSampleBuffer, asbd: AudioStreamBasicDescription) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: asbd.mSampleRate, channels: AVAudioChannelCount(asbd.mChannelsPerFrame), interleaved: asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0) else { return nil }
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else { return nil }
        pcmBuffer.frameLength = AVAudioFrameCount(frameCount)
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }
        var lengthAtOffset = 0, totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
        guard status == kCMBlockBufferNoErr, let data = dataPointer else { return nil }
        if let channelData = pcmBuffer.floatChannelData {
            memcpy(channelData[0], data, min(frameCount * MemoryLayout<Float>.size, totalLength))
        }
        return pcmBuffer
    }
    
    private func emitSegment(_ segment: TranscriptSegment) { streamContinuation?.yield(segment) }
    private func handleCaptureError(_ error: AudioCaptureError) { _state = .error(error) }
}

// MARK: - SCStream Audio Output Handler

final class AudioStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate {
    private let onAudioBuffer: @Sendable (CMSampleBuffer) -> Void
    private let onError: @Sendable (AudioCaptureError) -> Void
    init(onAudioBuffer: @escaping @Sendable (CMSampleBuffer) -> Void, onError: @escaping @Sendable (AudioCaptureError) -> Void) {
        self.onAudioBuffer = onAudioBuffer; self.onError = onError; super.init()
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid, CMSampleBufferGetNumSamples(sampleBuffer) > 0 else { return }
        onAudioBuffer(sampleBuffer)
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onError(.captureInterrupted(error.localizedDescription))
    }
}
