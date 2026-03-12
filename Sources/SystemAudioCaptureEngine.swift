// SystemAudioCaptureEngine.swift
// MeetingCopilot v4.3.1 — Primary: ScreenCaptureKit System Audio Capture
// + Diagnostics for PostMeetingLogger

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
    nonisolated var state: AudioCaptureState { get { _state } }
    
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
    private var restartCount: Int = 0
    private var hasEverReceivedSpeech: Bool = false
    private var segmentCount: Int = 0
    private var errorHistory: [String] = []
    
    var detectedAppName: String? { detectedMeetingApp?.displayName }
    
    // ★ 診斷資訊
    var diagnosticInfo: EngineDiagnosticInfo {
        EngineDiagnosticInfo(
            engineType: "SystemAudio (ScreenCaptureKit)",
            isActive: _state.isActive,
            bufferCount: bufferCount,
            restartCount: restartCount,
            hasReceivedSpeech: hasEverReceivedSpeech,
            segmentCount: segmentCount,
            useOnDevice: false,
            lastRMS: 0,
            silentBufferCount: 0,
            detectedAppName: detectedMeetingApp?.displayName,
            errors: errorHistory
        )
    }
    
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
        try await requestSpeechPermission()
        try setupSpeechRecognizer()
        let availableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let targetApp: MeetingApp
        if let specified = config.targetApp {
            targetApp = specified
            print("🎯 Manual selection: \(specified.displayName)")
        } else {
            targetApp = try findMeetingApp(in: availableContent)
        }
        detectedMeetingApp = targetApp
        let filter = SCContentFilter(desktopIndependentWindow: try findMainWindow(for: targetApp, in: availableContent))
        let streamConfig = SCStreamConfiguration()
        streamConfig.capturesAudio = true; streamConfig.excludesCurrentProcessAudio = true
        streamConfig.width = 1; streamConfig.height = 1
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        streamConfig.showsCursor = false
        streamConfig.sampleRate = Int(config.sampleRate); streamConfig.channelCount = config.channelCount
        streamOutput = AudioStreamOutput(
            onAudioBuffer: { [weak self] sb in Task { [weak self] in await self?.processAudioBuffer(sb) } },
            onError: { [weak self] e in Task { [weak self] in await self?.handleCaptureError(e) } }
        )
        captureStream = SCStream(filter: filter, configuration: streamConfig, delegate: streamOutput)
        guard let cs = captureStream, let so = streamOutput else { throw AudioCaptureError.engineStartFailed("Cannot create SCStream") }
        try cs.addStreamOutput(so, type: .audio, sampleHandlerQueue: DispatchQueue(label: "com.meetingcopilot.audio.capture", qos: .userInteractive))
        speechFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000.0, channels: 1, interleaved: false)
        try startSpeechRecognition()
        try await cs.startCapture()
        _state = .capturing
        print("🎯 SystemAudioCaptureEngine started: \(targetApp.displayName)")
    }
    
    func stop() async {
        if let stream = captureStream { try? await stream.stopCapture() }
        captureStream = nil; streamOutput = nil
        recognitionRequest?.endAudio(); recognitionTask?.cancel()
        recognitionTask = nil; recognitionRequest = nil
        audioConverter = nil; speechFormat = nil; lastInputFormat = nil
        converterInitialized = false
        streamContinuation?.finish(); streamContinuation = nil
        _state = .idle
        print("⏹️ Remote stopped (buf:\(bufferCount) rst:\(restartCount) seg:\(segmentCount) speech:\(hasEverReceivedSpeech))")
    }
    
    private func requestSpeechPermission() async throws {
        let status = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { s in c.resume(returning: s) } }
        guard status == .authorized else { throw AudioCaptureError.permissionDenied }
    }
    private func setupSpeechRecognizer() throws {
        speechRecognizer = SFSpeechRecognizer(locale: config.speechLocale)
        guard let r = speechRecognizer, r.isAvailable else { throw AudioCaptureError.speechRecognizerUnavailable }
        if r.supportsOnDeviceRecognition { print("  On-device recognition available (fallback)") }
    }
    
    private func findMeetingApp(in content: SCShareableContent) throws -> MeetingApp {
        guard config.autoDetectMeetingApp else { throw AudioCaptureError.noAudioSourceFound }
        struct DA { let app: MeetingApp; let hasActive: Bool; let area: CGFloat; let priority: Int }
        var cands: [DA] = []
        for app in content.applications {
            guard let ma = MeetingApp.from(bundleID: app.bundleIdentifier) else { continue }
            let wins = content.windows.filter { w in w.owningApplication?.bundleIdentifier == app.bundleIdentifier && w.isOnScreen && w.frame.width > 200 && w.frame.height > 200 }
            let hasA = !wins.isEmpty; let area = wins.map { $0.frame.width * $0.frame.height }.max() ?? 0
            cands.append(DA(app: ma, hasActive: hasA, area: area, priority: ma.detectionPriority))
        }
        let browsers = ["com.google.Chrome","com.apple.Safari","com.microsoft.edgemac","org.mozilla.firefox"]
        for app in content.applications where browsers.contains(app.bundleIdentifier) {
            for w in content.windows where w.owningApplication?.bundleIdentifier == app.bundleIdentifier {
                if let t = w.title, t.contains("Meet") || t.contains("meet.google.com") {
                    cands.append(DA(app: .googleMeet, hasActive: true, area: w.frame.width * w.frame.height, priority: 1)); break
                }
            }
        }
        let sorted = cands.sorted { a, b in if a.hasActive != b.hasActive { return a.hasActive }; if a.priority != b.priority { return a.priority < b.priority }; return a.area > b.area }
        if let best = sorted.first(where: { $0.hasActive }) { return best.app }
        throw AudioCaptureError.noAudioSourceFound
    }
    private func findMainWindow(for app: MeetingApp, in content: SCShareableContent) throws -> SCWindow {
        let wins = content.windows.filter { w in w.owningApplication?.bundleIdentifier == app.bundleIdentifier && w.isOnScreen && w.frame.width > 200 && w.frame.height > 200 }
        guard let main = wins.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else { throw AudioCaptureError.noAudioSourceFound }
        return main
    }
    
    private func startSpeechRecognition() throws {
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let req = recognitionRequest else { throw AudioCaptureError.engineStartFailed("Cannot create request") }
        req.shouldReportPartialResults = config.enablePartialResults
        recognitionTask = speechRecognizer?.recognitionTask(with: req) { [weak self] result, error in
            guard let self = self else { return }
            Task { [weak self] in
                guard let self = self else { return }
                if let r = result {
                    await self.markSpeechReceived()
                    await self.incrementSegmentCount()
                    let seg = TranscriptSegment(text: r.bestTranscription.formattedString, timestamp: Date(), isFinal: r.isFinal, confidence: r.bestTranscription.segments.last?.confidence ?? 0, locale: self.config.speechLocale, source: .systemAudio)
                    await self.emitSegment(seg)
                }
                if let e = error { await self.handleSpeechError(e) }
            }
        }
    }
    
    private func handleSpeechError(_ error: Error) async {
        let ns = error as NSError; let code = ns.code; let desc = error.localizedDescription
        let entry = "[\(code)] \(desc)"
        if errorHistory.count < 50 { errorHistory.append(entry) }
        if desc.contains("No speech detected") || code == 1110 {
            if restartCount < 3 { print("💤 Remote: no speech (5s wait)") }
            try? await Task.sleep(nanoseconds: 5_000_000_000); await restartSpeechRecognition(); return
        }
        if ns.domain == "kAFAssistantErrorDomain" && code == 216 {
            try? await Task.sleep(nanoseconds: 300_000_000); await restartSpeechRecognition(); return
        }
        print("⚠️ Remote speech error [\(code)]: \(desc)")
        try? await Task.sleep(nanoseconds: 1_000_000_000); await restartSpeechRecognition()
    }
    
    private func restartSpeechRecognition() async {
        recognitionRequest?.endAudio(); recognitionTask?.cancel()
        recognitionTask = nil; recognitionRequest = nil
        guard _state.isActive else { return }
        do { try startSpeechRecognition(); restartCount += 1
            if restartCount <= 5 || restartCount % 10 == 0 { print("🔄 Remote: restart #\(restartCount) (buf:\(bufferCount))") }
        } catch { await handleCaptureError(.engineStartFailed("restart failed")) }
    }
    
    private func markSpeechReceived() { if !hasEverReceivedSpeech { hasEverReceivedSpeech = true; print("🎉 Remote: first speech!") } }
    private func incrementSegmentCount() { segmentCount += 1 }
    
    private func ensureConverter(for fmt: AVAudioFormat) -> Bool {
        guard let tf = speechFormat else { return false }
        if converterInitialized, let l = lastInputFormat, l.sampleRate == fmt.sampleRate && l.channelCount == fmt.channelCount { return audioConverter != nil }
        audioConverter = AVAudioConverter(from: fmt, to: tf); lastInputFormat = fmt; converterInitialized = true
        return audioConverter != nil
    }
    
    private func processAudioBuffer(_ sb: CMSampleBuffer) {
        guard let fd = sb.formatDescription, let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd) else { return }
        bufferCount += 1
        if appendDirectly(sampleBuffer: sb, asbd: asbd.pointee) { return }
        guard let pcm = convertToPCMBuffer(sampleBuffer: sb, asbd: asbd.pointee) else { return }
        if abs(pcm.format.sampleRate - 16000.0) < 100 { recognitionRequest?.append(pcm); return }
        guard ensureConverter(for: pcm.format), let conv = audioConverter, let tf = speechFormat else { recognitionRequest?.append(pcm); return }
        let ratio = pcm.format.sampleRate / tf.sampleRate
        let tc = AVAudioFrameCount(Double(pcm.frameLength) / ratio)
        guard tc > 0, let cb = AVAudioPCMBuffer(pcmFormat: tf, frameCapacity: tc) else { return }
        var ce: NSError?
        let st = conv.convert(to: cb, error: &ce) { _, os in os.pointee = .haveData; return pcm }
        if st == .haveData { recognitionRequest?.append(cb) }
        else if st == .error { convertFailCount += 1; converterInitialized = false; audioConverter = nil; recognitionRequest?.append(pcm) }
    }
    
    private func appendDirectly(sampleBuffer: CMSampleBuffer, asbd: AudioStreamBasicDescription) -> Bool {
        guard let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: asbd.mSampleRate, channels: AVAudioChannelCount(asbd.mChannelsPerFrame), interleaved: false) else { return false }
        let fc = CMSampleBufferGetNumSamples(sampleBuffer)
        guard fc > 0, let pcm = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(fc)) else { return false }
        pcm.frameLength = AVAudioFrameCount(fc)
        guard let bb = CMSampleBufferGetDataBuffer(sampleBuffer) else { return false }
        var lo = 0, tl = 0; var dp: UnsafeMutablePointer<Int8>?
        let s = CMBlockBufferGetDataPointer(bb, atOffset: 0, lengthAtOffsetOut: &lo, totalLengthOut: &tl, dataPointerOut: &dp)
        guard s == kCMBlockBufferNoErr, let d = dp else { return false }
        if let cd = pcm.floatChannelData { memcpy(cd[0], d, min(fc * MemoryLayout<Float>.size, tl)) }
        recognitionRequest?.append(pcm)
        if bufferCount == 1 { print("🔊 First buffer: \(asbd.mSampleRate)Hz / \(asbd.mChannelsPerFrame)ch / \(fc) frames"); print("🔊 Strategy: direct append") }
        return true
    }
    
    private func convertToPCMBuffer(sampleBuffer: CMSampleBuffer, asbd: AudioStreamBasicDescription) -> AVAudioPCMBuffer? {
        guard let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: asbd.mSampleRate, channels: AVAudioChannelCount(asbd.mChannelsPerFrame), interleaved: asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0) else { return nil }
        let fc = CMSampleBufferGetNumSamples(sampleBuffer)
        guard let pcm = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(fc)) else { return nil }
        pcm.frameLength = AVAudioFrameCount(fc)
        guard let bb = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }
        var lo = 0, tl = 0; var dp: UnsafeMutablePointer<Int8>?
        let s = CMBlockBufferGetDataPointer(bb, atOffset: 0, lengthAtOffsetOut: &lo, totalLengthOut: &tl, dataPointerOut: &dp)
        guard s == kCMBlockBufferNoErr, let d = dp else { return nil }
        if let cd = pcm.floatChannelData { memcpy(cd[0], d, min(fc * MemoryLayout<Float>.size, tl)) }
        return pcm
    }
    
    private func emitSegment(_ s: TranscriptSegment) { streamContinuation?.yield(s) }
    private func handleCaptureError(_ e: AudioCaptureError) { _state = .error(e) }
}

final class AudioStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate {
    private let onAudioBuffer: @Sendable (CMSampleBuffer) -> Void
    private let onError: @Sendable (AudioCaptureError) -> Void
    init(onAudioBuffer: @escaping @Sendable (CMSampleBuffer) -> Void, onError: @escaping @Sendable (AudioCaptureError) -> Void) {
        self.onAudioBuffer = onAudioBuffer; self.onError = onError; super.init()
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sb.isValid, CMSampleBufferGetNumSamples(sb) > 0 else { return }
        onAudioBuffer(sb)
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) { onError(.captureInterrupted(error.localizedDescription)) }
}
