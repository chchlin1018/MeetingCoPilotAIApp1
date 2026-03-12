# MeetingPrep-SKILL.md

> Version: 2026-03-12 | v4.3.1 | Zoom ✅ Verified

## ❗ Required: Screen Recording Permission (TCC)

ScreenCaptureKit needs screen recording permission to capture meeting audio from Zoom/Teams/Meet.

**Setup: System Settings > Privacy & Security > Screen & System Audio Recording > Enable MeetingCopilot**

Without this permission:
- Console shows: `DualStream: SystemAudio failed — 使用者拒絕應用程式、視窗、顯示器擷取的TCC`
- Only mic (local) works, remote audio capture fails
- The app may need to be restarted after granting permission

To reset if needed:
```bash
tccutil reset ScreenCapture com.RealityMatrix.MeetingCopilot
```

## Zoom Meeting Verified (2026-03-12)

Zoom full English meeting tested successfully:
- Remote English speech recognition (en-US): ✅
- Local mic On-Device English recognition: ✅
- MacBook built-in mic auto-detection: ✅
- 10 Talking Points + 12 Q&A loaded: ✅
- Notion RAG available: ✅
- Screen recording TCC required for dual-stream

## Microphone Compatibility

AirPods Pro bluetooth mic is NOT compatible when ScreenCaptureKit is running.
Program auto-detects bluetooth and switches to built-in mic. AirPods earphone output not affected.

| Device | Voice Capture | Compatible |
|--------|:---:|:---:|
| MacBook Built-in Mic | ✅ | ✅ Recommended |
| AirPods Pro | ❌ | Auto-switched to built-in |
| External USB Mic | ✅ | ✅ Should work |

## Pre-Meeting Checklist

1. System Settings > Privacy & Security > Screen & System Audio Recording > MeetingCopilot ✅
2. System Settings > Sound > Input > MacBook built-in mic (auto-handled)
3. Sources/APIKeys.swift has valid Claude API Key
4. Run System Check (🩺) > all items pass
5. Open Zoom/Teams/Meet and join meeting
6. Click "開始會議" > select app > start

## App Selection (v4.3.1)

MeetingPrepView: scanAndStart() > AppScanner.scanActiveApps()
- 0 apps: auto-detect
- 1 app: auto-start
- 2+ apps: App Picker Sheet

## Dual-Pipeline Recognition

Remote: ScreenCaptureKit > Apple Speech [SERVER]
Local: AVAudioEngine > Apple Speech [ON-DEVICE]

On-Device languages: zh-TW, en-US, en-GB, zh-CN, ja-JP

## Verified Apps

| App | Remote | Local | Status |
|-----|:---:|:---:|--------|
| Zoom | ✅ | ✅ | Verified (English) |
| YouTube (Chrome) | ✅ | ✅ | Verified |
| Google Meet (Chrome) | ✅ | ✅ | Verified |
| Teams | 🔲 | 🔲 | Pending |
| LINE Desktop | ❌ | ❌ | HAL limitation |

## Speech Error Handling

| Error | Wait | Rationale |
|-------|------|-----------|
| No speech detected | 5s | Normal silence |
| 60s timeout (216) | 0.3s | Apple limit |
| Canceled (301) | 1s | Other task conflict |

## Mic Debug Logging

Filter Xcode Console: MIC-DEBUG
- Start: permission, format, on-device, bluetooth detection
- RMS: first 10 buffers with dB + silent/quiet/audio
- Bluetooth auto-switch log
- Errors: domain + code + description + RMS

## Established Meetings

| Meeting | Notion Page ID | NotebookLM ID |
|---------|---------------|---------------|
| BiWeekly-Stanley-11Mar26 | 320f154a-6472-815c-8ad0-c214783dfe22 | ccaeee5e-8971-49e1-801d-2989ded2c61b |
| BiWeekly-Mark-JJ-12Mar26 | 320f154a-6472-813f-bc2c-d98e570ab696 | 51364658-5c30-4b55-8118-5103095ae8d0 |

Updated: 2026-03-12
