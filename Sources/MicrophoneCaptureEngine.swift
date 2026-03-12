// MicrophoneCaptureEngine.swift
// MeetingCopilot v4.3.1 — Microphone Capture Engine
// Fixed: On-Device recognition + AirPods auto-switch + Debug logging

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
    private var didSwitchFromBluetooth: Bool = false
    
    init(configuration: AudioCaptureConfiguration = .default) {
        self.config = configuration
        super.init()
    }
    
    private func setStreamContinuation(_ continuation: AsyncStream<TranscriptSegment>.Continuation) {
        self.streamContinuation = continuation
    }
    
    // MARK: - ★ AirPods / Bluetooth 麥克風偵測與自動切換
    
    nonisolated private func ensureBuiltInMicrophone() {
        var defaultInputID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &propertySize, &defaultInputID
        )
        guard status == noErr else {
            print("🎙️ [MIC-DEBUG] Cannot get default input device")
            return
        }
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
            print("⚠️ [MIC-DEBUG] 藍牙麥克風與 ScreenCaptureKit 衝突，將自動切換到內建麥克風")
            if let builtInID = findBuiltInMicrophone() {
                let builtInName = getDeviceName(deviceID: builtInID)
                var newDeviceID = builtInID
                var setAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioHardwarePropertyDefaultInputDevice,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                let setStatus = AudioObjectSetPropertyData(
                    AudioObjectID(kAudioObjectSystemObject),
                    &setAddress, 0, nil,
                    UInt32(MemoryLayout<AudioDeviceID>.size),
                    &newDeviceID
                )
                if setStatus == noErr {
                    print("✅ [MIC-DEBUG] 已切換麥克風: \"\(currentName)\" → \"\(builtInName)\"")
                    print("✅ [MIC-DEBUG] AirPods 仍可作為耳機使用（輸出不受影響）")
                } else {
                    print("❌ [MIC-DEBUG] 無法切換到內建麥克風 (error: \(setStatus))")
                }
            } else {
                print("❌ [MIC-DEBUG] 找不到內建麥克風！請手動切換")
            }
        } else {
            print("✅ [MIC-DEBUG] 麥克風裝置 OK: \"\(currentName)\" (非藍牙)")
        }
    }
    
    nonisolated private func findBuiltInMicrophone() -> AudioDeviceID? {
        var propertySize: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize)
        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: deviceCount)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize, &devices)
        for deviceID in devices {
            let transport = getTransportType(deviceID: deviceID)
            let hasInput = deviceHasInput(deviceID: deviceID)
            if transport == kAudioDeviceTransportTypeBuiltIn && hasInput {
                let name = getDeviceName(deviceID: deviceID)
                print("🎙️ [MIC-DEBUG] 找到內建麥克風: \"\(name)\" (ID: \(deviceID))")
                return deviceID
            }
        }
        return nil
    }
    
    nonisolated private func getDeviceName(deviceID: AudioDeviceID) -> String {
        var name: CFString = "" as CFString
        var propertySize = UInt32(MemoryLayout<CFString>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &propertySize, &name)
        return name as String
    }
    
    nonisolated private func getTransportType(deviceID: AudioDeviceID) -> UInt32 {
        var transportType: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &propertySize, &transportType)
        return transportType
    }
    
    nonisolated private func deviceHasInput(deviceID: AudioDeviceID) -> Bool {
        var propertySize: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &propertySize)
        let bufferListSize = Int(propertySize)
        guard bufferListSize > 0 else { return false }
        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferList.deallocate() }
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &propertySize, bufferList)
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }
    
    nonisolated private func transportTypeString(_ type: UInt32) -> String {
        switch type {
        case kAudioDeviceTransportTypeBuiltIn: return "BuiltIn"
        case kAudioDeviceTransportTypeBluetooth: return "Bluetooth"
        case kAudioDeviceTransportTypeBluetoothLE: return "BluetoothLE"
        case kAudioDeviceTransportTypeUSB: return "USB"
        case kAudioDeviceTransportTypeAggregate: return "Aggregate"
        case kAudioDeviceTransportTypeVirtual: return "Virtual"
        default: return "Unknown(\(type))"
        }
    }
    
    // MARK: - Start
    
    func start() async throws {
        guard !_state.isActive else { return }
        _state = .preparing
        
        print("🎙️ [MIC-DEBUG] ====== MicrophoneCaptureEngine Starting ======")
        print("🎙️ [MIC-DEBUG] Locale: \(config.speechLocale.identifier)")
        
        ensureBuiltInMicrophone()
        
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        print("🎙️ [MIC-DEBUG] Mic permission: \(micStatus.rawValue) (3=authorized)")
        
        speechRecognizer = SFSpeechRecognizer(locale: config.speechLocale)
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            print("❌ [MIC-DEBUG] SFSpeechRecognizer NOT available for \(config.speechLocale.identifier)")
            throw AudioCaptureError.speechRecognizerUnavailable
        }
        
        useOnDevice = recognizer.supportsOnDeviceRecognition
        print("🎙️ [MIC-DEBUG] on-device recognition = \(useOnDevice ? "✅ YES" : "❌ NO")")
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else {
            throw AudioCaptureError.engineStartFailed("Cannot create Request")
        }
        request.shouldReportPartialResults = config.enablePartialResults
        
        if useOnDevice {
            request.requiresOnDeviceRecognition = true
            print("🎙️ [MIC-DEBUG] request.requiresOnDeviceRecognition = TRUE")
        }
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        print("🎙️ [MIC-DEBUG] inputNode format: \(recordingFormat.sampleRate)Hz / \(recordingFormat.channelCount)ch")
        
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
        print("✅ [MIC-DEBUG] Mic started (mode: \(useOnDevice ? "on-device" : "server"))")
        print("🎙️ [MIC-DEBUG] ====== MicrophoneCaptureEngine Ready ======")
    }
    
    // MARK: - RMS
    
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
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            Task {
                if let result = result {
                    let text = result.bestTranscription.formattedString
                    let isFinal = result.isFinal
                    let confidence = result.bestTranscription.segments.last?.confidence ?? 0
                    let gotSpeechBefore = await self.hasEverReceivedSpeech
                    if !gotSpeechBefore || isFinal {
                        print("🎙️ [MIC-DEBUG] 🗣️ Speech: isFinal=\(isFinal), conf=\(String(format: "%.2f", confidence)), text=\"\(text.suffix(60))\"")
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
    }
    
    // MARK: - Error Handling
    
    private func handleSpeechError(_ error: Error) async {
        let nsError = error as NSError
        let code = nsError.code
        let domain = nsError.domain
        let description = error.localizedDescription
        print("⚠️ [MIC-DEBUG] Speech error: domain=\(domain), code=\(code), desc=\"\(description)\"")
        if description.contains("No speech detected") || code == 1110 {
            if restartCount < 5 { print("💤 [MIC-DEBUG] No speech — 5s wait") }
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await restartSpeechOnly()
            return
        }
        if domain == "kAFAssistantErrorDomain" && code == 216 {
            try? await Task.sleep(nanoseconds: 300_000_000)
            await restartSpeechOnly()
            return
        }
        if code == 301 {
            print("⚠️ [MIC-DEBUG] CANCELED (301)")
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await restartSpeechOnly()
            return
        }
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        await restartSpeechOnly()
    }
    
    func stop() async {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil; recognitionRequest = nil
        streamContinuation?.finish(); streamContinuation = nil
        _state = .idle
        print("⏹️ [MIC-DEBUG] Mic stopped (buffers: \(bufferCount), restarts: \(restartCount), gotSpeech: \(hasEverReceivedSpeech))")
    }
    
    private func restartSpeechOnly() async {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil; recognitionRequest = nil
        guard _state.isActive else { return }
        guard let recognizer = speechRecognizer, recognizer.isAvailable else { return }
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
            print("🔄 [MIC-DEBUG] speech restarted (#\(restartCount))")
        }
    }
    
    private func markSpeechReceived() {
        if !hasEverReceivedSpeech {
            hasEverReceivedSpeech = true
            print("🎉 [MIC-DEBUG] FIRST SPEECH! (mode: \(useOnDevice ? "on-device" : "server"), buffers: \(bufferCount))")
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
            print("🎙️ [MIC-DEBUG] buffer #\(bufferCount): silent=\(String(format: "%.0f", silentPct))%, gotSpeech=\(hasEverReceivedSpeech)")
        }
    }
    
    private func emitSegment(_ segment: TranscriptSegment) {
        streamContinuation?.yield(segment)
    }
}
