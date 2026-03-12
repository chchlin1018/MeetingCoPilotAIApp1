// MicrophoneCaptureEngine.swift
// MeetingCopilot v4.3.1 — Microphone Capture Engine
// On-Device recognition + AirPods auto-switch + Debug logging + Diagnostics

import Foundation
import AVFoundation
import Speech
import CoreAudio

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
    private var segmentCount: Int = 0
    private var errorHistory: [String] = []
    private var detectedMicDevice: String = ""
    private var didDetectBluetooth: Bool = false
    
    // ★ 診斷資訊存取器
    var diagnosticInfo: EngineDiagnosticInfo {
        EngineDiagnosticInfo(
            engineType: "Microphone (AVAudioEngine)",
            isActive: _state.isActive,
            bufferCount: bufferCount,
            restartCount: restartCount,
            hasReceivedSpeech: hasEverReceivedSpeech,
            segmentCount: segmentCount,
            useOnDevice: useOnDevice,
            lastRMS: lastRMS,
            silentBufferCount: silentBufferCount,
            detectedAppName: nil,
            errors: errorHistory
        )
    }
    
    var micDeviceName: String { detectedMicDevice }
    var bluetoothDetected: Bool { didDetectBluetooth }
    
    init(configuration: AudioCaptureConfiguration = .default) {
        self.config = configuration
        super.init()
    }
    
    private func setStreamContinuation(_ continuation: AsyncStream<TranscriptSegment>.Continuation) {
        self.streamContinuation = continuation
    }
    
    // MARK: - AirPods / Bluetooth Auto-Switch
    
    nonisolated private func ensureBuiltInMicrophone() -> (device: String, isBluetooth: Bool) {
        var defaultInputID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize, &defaultInputID)
        guard status == noErr else { return ("Unknown", false) }
        
        let currentName = getDeviceName(deviceID: defaultInputID)
        let transportType = getTransportType(deviceID: defaultInputID)
        print("🎙️ [MIC-DEBUG] Current input device: \"\(currentName)\" (transport: \(transportTypeString(transportType)))")
        
        let isBluetooth = (transportType == kAudioDeviceTransportTypeBluetooth ||
                          transportType == kAudioDeviceTransportTypeBluetoothLE ||
                          currentName.lowercased().contains("airpods") ||
                          currentName.lowercased().contains("beats") ||
                          currentName.lowercased().contains("bluetooth"))
        
        if isBluetooth {
            print("⚠️ [MIC-DEBUG] 偵測到藍牙麥克風: \"\(currentName)\"")
            if let builtInID = findBuiltInMicrophone() {
                let builtInName = getDeviceName(deviceID: builtInID)
                var newDeviceID = builtInID
                var setAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioHardwarePropertyDefaultInputDevice,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                let setStatus = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &setAddress, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &newDeviceID)
                if setStatus == noErr {
                    print("✅ [MIC-DEBUG] 已切換: \"\(currentName)\" → \"\(builtInName)\"")
                    return (builtInName, true)
                }
            }
            return (currentName, true)
        }
        print("✅ [MIC-DEBUG] 麥克風 OK: \"\(currentName)\" (非藍牙)")
        return (currentName, false)
    }
    
    nonisolated private func findBuiltInMicrophone() -> AudioDeviceID? {
        var propertySize: UInt32 = 0
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize)
        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: deviceCount)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize, &devices)
        for deviceID in devices {
            if getTransportType(deviceID: deviceID) == kAudioDeviceTransportTypeBuiltIn && deviceHasInput(deviceID: deviceID) {
                return deviceID
            }
        }
        return nil
    }
    
    nonisolated private func getDeviceName(deviceID: AudioDeviceID) -> String {
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceNameCFString, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &name)
        return name as String
    }
    nonisolated private func getTransportType(deviceID: AudioDeviceID) -> UInt32 {
        var type: UInt32 = 0; var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &type); return type
    }
    nonisolated private func deviceHasInput(deviceID: AudioDeviceID) -> Bool {
        var size: UInt32 = 0
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &size)
        guard Int(size) > 0 else { return false }
        let buf = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1); defer { buf.deallocate() }
        AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, buf)
        return UnsafeMutableAudioBufferListPointer(buf).reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }
    nonisolated private func transportTypeString(_ type: UInt32) -> String {
        switch type {
        case kAudioDeviceTransportTypeBuiltIn: return "BuiltIn"
        case kAudioDeviceTransportTypeBluetooth: return "Bluetooth"
        case kAudioDeviceTransportTypeBluetoothLE: return "BluetoothLE"
        case kAudioDeviceTransportTypeUSB: return "USB"
        default: return "Other(\(type))"
        }
    }
    
    // MARK: - Start
    
    func start() async throws {
        guard !_state.isActive else { return }
        _state = .preparing
        print("🎙️ [MIC-DEBUG] ====== MicrophoneCaptureEngine Starting ======")
        
        let micResult = ensureBuiltInMicrophone()
        detectedMicDevice = micResult.device
        didDetectBluetooth = micResult.isBluetooth
        
        speechRecognizer = SFSpeechRecognizer(locale: config.speechLocale)
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw AudioCaptureError.speechRecognizerUnavailable
        }
        useOnDevice = recognizer.supportsOnDeviceRecognition
        print("🎙️ [MIC-DEBUG] on-device = \(useOnDevice ? "✅ YES" : "❌ NO")")
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { throw AudioCaptureError.engineStartFailed("Cannot create Request") }
        request.shouldReportPartialResults = config.enablePartialResults
        if useOnDevice { request.requiresOnDeviceRecognition = true }
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        print("🎙️ [MIC-DEBUG] format: \(recordingFormat.sampleRate)Hz / \(recordingFormat.channelCount)ch")
        
        inputNode.installTap(onBus: 0, bufferSize: config.bufferSize, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.recognitionRequest?.append(buffer)
            let rms = self.calculateRMS(buffer: buffer)
            Task { await self.incrementBufferCount(rms: rms) }
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        startSpeechRecognition(recognizer: recognizer, request: request)
        _state = .capturing
        print("✅ [MIC-DEBUG] Mic started (mode: \(useOnDevice ? "on-device" : "server"))")
    }
    
    nonisolated private func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let ch = buffer.floatChannelData else { return 0 }
        let n = Int(buffer.frameLength); guard n > 0 else { return 0 }
        var s: Float = 0; for i in 0..<n { let v = ch[0][i]; s += v * v }
        return sqrt(s / Float(n))
    }
    
    // MARK: - Speech Recognition
    
    private func startSpeechRecognition(recognizer: SFSpeechRecognizer, request: SFSpeechAudioBufferRecognitionRequest) {
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            Task {
                if let result = result {
                    let text = result.bestTranscription.formattedString
                    let isFinal = result.isFinal
                    let confidence = result.bestTranscription.segments.last?.confidence ?? 0
                    let gotBefore = await self.hasEverReceivedSpeech
                    if !gotBefore || isFinal {
                        print("🎙️ [MIC-DEBUG] Speech: isFinal=\(isFinal), conf=\(String(format: "%.2f", confidence))")
                    }
                    await self.markSpeechReceived()
                    await self.incrementSegmentCount()
                    let seg = TranscriptSegment(text: text, timestamp: Date(), isFinal: isFinal, confidence: confidence, locale: self.config.speechLocale, source: .microphone)
                    await self.emitSegment(seg)
                }
                if let error = error { await self.handleSpeechError(error) }
            }
        }
    }
    
    private func handleSpeechError(_ error: Error) async {
        let ns = error as NSError
        let code = ns.code; let desc = error.localizedDescription
        let entry = "[\(code)] \(desc)"
        if errorHistory.count < 50 { errorHistory.append(entry) }
        print("⚠️ [MIC-DEBUG] Speech error: \(entry)")
        
        if desc.contains("No speech detected") || code == 1110 {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await restartSpeechOnly(); return
        }
        if ns.domain == "kAFAssistantErrorDomain" && code == 216 {
            try? await Task.sleep(nanoseconds: 300_000_000)
            await restartSpeechOnly(); return
        }
        if code == 301 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await restartSpeechOnly(); return
        }
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        await restartSpeechOnly()
    }
    
    func stop() async {
        audioEngine.stop(); audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio(); recognitionTask?.cancel()
        recognitionTask = nil; recognitionRequest = nil
        streamContinuation?.finish(); streamContinuation = nil
        _state = .idle
        print("⏹️ [MIC-DEBUG] Mic stopped (buf:\(bufferCount) rst:\(restartCount) seg:\(segmentCount) speech:\(hasEverReceivedSpeech) onDev:\(useOnDevice))")
    }
    
    private func restartSpeechOnly() async {
        recognitionRequest?.endAudio(); recognitionTask?.cancel()
        recognitionTask = nil; recognitionRequest = nil
        guard _state.isActive else { return }
        guard let recognizer = speechRecognizer, recognizer.isAvailable else { return }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = config.enablePartialResults
        if useOnDevice { req.requiresOnDeviceRecognition = true }
        self.recognitionRequest = req
        let node = audioEngine.inputNode; node.removeTap(onBus: 0)
        let fmt = node.outputFormat(forBus: 0)
        node.installTap(onBus: 0, bufferSize: config.bufferSize, format: fmt) { [weak self] buf, _ in
            guard let self = self else { return }
            self.recognitionRequest?.append(buf)
            let rms = self.calculateRMS(buffer: buf)
            Task { await self.incrementBufferCount(rms: rms) }
        }
        startSpeechRecognition(recognizer: recognizer, request: req)
        restartCount += 1
        if restartCount <= 5 || restartCount % 10 == 0 { print("🔄 [MIC-DEBUG] restart #\(restartCount)") }
    }
    
    private func markSpeechReceived() {
        if !hasEverReceivedSpeech {
            hasEverReceivedSpeech = true
            print("🎉 [MIC-DEBUG] FIRST SPEECH! (mode: \(useOnDevice ? "on-device" : "server"), buf:\(bufferCount))")
        }
    }
    private func incrementSegmentCount() { segmentCount += 1 }
    private func incrementBufferCount(rms: Float) {
        bufferCount += 1; lastRMS = rms
        if rms < 0.001 { silentBufferCount += 1 }
        if bufferCount <= 10 {
            let db = rms > 0 ? 20 * log10(rms) : -120
            print("🎙️ [MIC-DEBUG] buf#\(bufferCount): RMS=\(String(format: "%.6f", rms)) (\(String(format: "%.1f", db))dB) \(rms < 0.001 ? "🔇" : rms < 0.01 ? "🔈" : "🔊")")
        }
        if bufferCount % 500 == 0 {
            let pct = Float(silentBufferCount) / Float(bufferCount) * 100
            print("🎙️ [MIC-DEBUG] buf#\(bufferCount): silent=\(String(format: "%.0f", pct))%")
        }
    }
    private func emitSegment(_ s: TranscriptSegment) { streamContinuation?.yield(s) }
}
