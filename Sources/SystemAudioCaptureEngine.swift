// SystemAudioCaptureEngine.swift
// MeetingCopilot v4.3.1 — Primary: ScreenCaptureKit System Audio Capture
// Fixed: Dynamic audio format + App priority detection

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
    
    // MARK: - Public
    
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
        
        try await requestSpeechPermission()
        try setupSpeechRecognizer()
        
        let availableContent = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        )
        
        // ★ Smart App detection with priority
        let targetApp = try findMeetingApp(in: availableContent)
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
        
        speechFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000.0,
            channels: 1,
            interleaved: false
        )
        
        try startSpeechRecognition()
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
    
    // MARK: - ★ Smart App Detection (with priority + active window check)
    
    /// App 偵測優先級：
    /// Tier 1 (最高)：Zoom, Teams, Webex — 專業會議軟體
    /// Tier 2：Google Meet (Chrome) — 瀏覽器會議
    /// Tier 3：Slack, Discord — 團隊協作
    /// Tier 4 (最低)：LINE, WhatsApp, Telegram, FaceTime — 通訊軟體
    private func findMeetingApp(in content: SCShareableContent) throws -> MeetingApp {
        guard config.autoDetectMeetingApp else {
            throw AudioCaptureError.noAudioSourceFound
        }
        
        // ★ Step 1: 掃描所有支援的 App 並檢查是否有活躍視窗
        struct DetectedApp {
            let app: MeetingApp
            let hasActiveWindow: Bool
            let windowArea: CGFloat   // 最大視窗面積
            let priority: Int         // 優先級（0=最高）
        }
        
        var candidates: [DetectedApp] = []
        
        for app in content.applications {
            guard let meetingApp = MeetingApp.from(bundleID: app.bundleIdentifier) else { continue }
            
            // 檢查是否有活躍視窗（在螢幕上且大於 200x200）
            let activeWindows = content.windows.filter { w in
                w.owningApplication?.bundleIdentifier == app.bundleIdentifier
                && w.isOnScreen
                && w.frame.width > 200 && w.frame.height > 200
            }
            
            let hasActive = !activeWindows.isEmpty
            let maxArea = activeWindows.map { $0.frame.width * $0.frame.height }.max() ?? 0
            let priority = meetingApp.detectionPriority
            
            print("  🔍 Scan: \(meetingApp.displayName) | active=\(hasActive) | area=\(Int(maxArea)) | priority=\(priority)")
            
            candidates.append(DetectedApp(
                app: meetingApp,
                hasActiveWindow: hasActive,
                windowArea: maxArea,
                priority: priority
            ))
        }
        
        // ★ Step 2: 檢查瀏覽器是否有 Google Meet
        let browserBundles = [
            "com.google.Chrome", "com.apple.Safari",
            "com.microsoft.edgemac", "org.mozilla.firefox", "com.brave.Browser"
        ]
        
        for app in content.applications {
            if browserBundles.contains(app.bundleIdentifier) {
                for window in content.windows where window.owningApplication?.bundleIdentifier == app.bundleIdentifier {
                    if let title = window.title,
                       (title.contains("Meet") || title.contains("meet.google.com")) {
                        let area = window.frame.width * window.frame.height
                        print("  🔍 Scan: Google Meet in \(app.applicationName) | active=true | area=\(Int(area)) | priority=1")
                        candidates.append(DetectedApp(
                            app: .googleMeet,
                            hasActiveWindow: true,
                            windowArea: area,
                            priority: 1  // Tier 1 — 同等於專業會議軟體
                        ))
                        break
                    }
                }
            }
        }
        
        // ★ Step 3: 排序選擇最佳候選
        // 排序規則：
        //   1. 有活躍視窗的優先
        //   2. 同等活躍狀態下，優先級數字小的優先
        //   3. 同等優先級下，視窗面積大的優先
        let sorted = candidates.sorted { a, b in
            if a.hasActiveWindow != b.hasActiveWindow {
                return a.hasActiveWindow   // 有活躍視窗的排前面
            }
            if a.priority != b.priority {
                return a.priority < b.priority  // 優先級數字小的排前面
            }
            return a.windowArea > b.windowArea  // 視窗大的排前面
        }
        
        // ★ Step 4: 僅選擇有活躍視窗的 App
        if let best = sorted.first(where: { $0.hasActiveWindow }) {
            print("  📱 Selected: \(best.app.displayName) (priority=\(best.priority), area=\(Int(best.windowArea)))")
            return best.app
        }
        
        // 沒有任何有活躍視窗的 App
        if !candidates.isEmpty {
            let names = candidates.map { $0.app.displayName }.joined(separator: ", ")
            print("  ⚠️ Found apps but none have active windows: \(names)")
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
    
    // MARK: - ★ Dynamic Audio Converter
    
    private func ensureConverter(for inputFormat: AVAudioFormat) -> Bool {
        guard let targetFormat = speechFormat else { return false }
        
        if converterInitialized, let last = lastInputFormat,
           last.sampleRate == inputFormat.sampleRate &&
           last.channelCount == inputFormat.channelCount {
            return audioConverter != nil
        }
        
        if !converterInitialized {
            print("🔊 Audio format detected: \(inputFormat.sampleRate)Hz / \(inputFormat.channelCount)ch")
        } else {
            print("⚠️ Audio format CHANGED: \(inputFormat.sampleRate)Hz / \(inputFormat.channelCount)ch")
        }
        
        audioConverter = AVAudioConverter(from: inputFormat, to: targetFormat)
        lastInputFormat = inputFormat
        converterInitialized = true
        
        if audioConverter == nil {
            print("❌ Cannot create audio converter")
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
    
    // MARK: - ★ Process Audio Buffer
    
    private func processAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let formatDescription = sampleBuffer.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return
        }
        
        bufferCount += 1
        
        if appendDirectly(sampleBuffer: sampleBuffer, asbd: asbd.pointee) {
            return
        }
        
        guard let pcmBuffer = convertToPCMBuffer(sampleBuffer: sampleBuffer, asbd: asbd.pointee) else {
            return
        }
        
        let inputFormat = pcmBuffer.format
        
        if abs(inputFormat.sampleRate - 16000.0) < 100 {
            recognitionRequest?.append(pcmBuffer)
            return
        }
        
        guard ensureConverter(for: inputFormat),
              let converter = audioConverter,
              let targetFormat = speechFormat else {
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
        let status = converter.convert(to: convertedBuffer, error: &conversionError) { _, outStatus in
            outStatus.pointee = .haveData
            return pcmBuffer
        }
        
        if status == .haveData {
            recognitionRequest?.append(convertedBuffer)
        } else if status == .error {
            convertFailCount += 1
            if convertFailCount <= 3 {
                print("⚠️ Convert error #\(convertFailCount): \(conversionError?.localizedDescription ?? "unknown")")
            }
            converterInitialized = false
            audioConverter = nil
            recognitionRequest?.append(pcmBuffer)
        }
    }
    
    // MARK: - Direct append
    
    private func appendDirectly(sampleBuffer: CMSampleBuffer, asbd: AudioStreamBasicDescription) -> Bool {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: asbd.mSampleRate,
            channels: AVAudioChannelCount(asbd.mChannelsPerFrame),
            interleaved: false
        ) else { return false }
        
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else { return false }
        
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
        
        recognitionRequest?.append(pcmBuffer)
        
        if bufferCount == 1 {
            print("🔊 First audio buffer: \(asbd.mSampleRate)Hz / \(asbd.mChannelsPerFrame)ch / \(frameCount) frames")
            print("🔊 Strategy: direct append (Apple Speech handles resampling)")
        }
        
        return true
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
