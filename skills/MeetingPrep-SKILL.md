# MeetingPrep-SKILL.md

> Version: 2026-03-12 | v4.3.1

## Microphone Compatibility

AirPods Pro bluetooth mic is NOT compatible when ScreenCaptureKit is running.
macOS switches AirPods to SCO (low-quality telephony) mode, causing speech recognition to fail.

Recommended: MacBook built-in mic for voice capture, AirPods for hearing only.

| Device | Voice Capture | Compatible |
|--------|:---:|:---:|
| MacBook Built-in Mic | ✅ | ✅ Recommended |
| AirPods Pro | ❌ | ❌ SCO conflict |
| External USB Mic | ✅ | ✅ Should work |

Before System Check: Set System Settings > Sound > Input to MacBook mic.

## App Selection (v4.3.1)

MeetingPrepView: scanAndStart() > AppScanner.scanActiveApps()
- 0 apps: auto-detect
- 1 app: auto-start
- 2+ apps: App Picker Sheet

MeetingAICoordinator API:
- scanAndPrepare(config:) - scan + picker flow
- startMeetingWithApp(_:) - user selected app
- startMeeting(config:) - direct start

## Dual-Pipeline Recognition

Remote: ScreenCaptureKit > Apple Speech [SERVER]
Local: AVAudioEngine > Apple Speech [ON-DEVICE]

macOS allows only ONE server-based SFSpeechRecognitionTask.
Mic uses On-Device, Remote uses Server. Both coexist.

On-Device languages: zh-TW, en-US, en-GB, zh-CN, ja-JP
Prerequisite: Download model via System Settings > Keyboard > Dictation > On-Device.

## Audio Format Strategy

1. Direct Append - feed PCM to Apple Speech directly
2. Dynamic Converter - lazy-create from actual buffer format
3. Raw Append - fallback on converter error

## Speech Error Handling

| Error | Wait | Rationale |
|-------|------|-----------|
| No speech detected | 5s | Normal silence |
| 60s timeout (216) | 0.3s | Apple limit |
| Canceled (301) | 1s | Other task conflict |
| Other | 1s | Log and restart |

## Mic Debug Logging

Filter Xcode Console: MIC-DEBUG
- Start: permission, format, on-device, task state
- RMS: first 10 buffers with dB + silent/quiet/audio
- Every 500 buffers: silence percentage
- Errors: domain + code + description + RMS

Diagnostics:
- All SILENT: wrong mic device
- Has AUDIO but no speech: On-Device model not downloaded
- Code 301: server conflict

## Smart App Detection

| Tier | Apps |
|------|------|
| 0 | Zoom, Teams, Webex |
| 1 | Google Meet (Chrome) |
| 2 | Slack, Discord |
| 3 | LINE, WhatsApp, Telegram, FaceTime |

## Meeting Prep Workflow

Notion (SSOT) > Claude generates TXT > GitHub > NotebookLM > Live meeting
Notion parent: 320f154a-6472-804f-a226-c3694c1bb319

## Established Meetings

| Meeting | Notion Page ID | NotebookLM ID |
|---------|---------------|---------------|
| BiWeekly-Stanley-11Mar26 | 320f154a-6472-815c-8ad0-c214783dfe22 | ccaeee5e-8971-49e1-801d-2989ded2c61b |
| BiWeekly-Mark-JJ-12Mar26 | 320f154a-6472-813f-bc2c-d98e570ab696 | 51364658-5c30-4b55-8118-5103095ae8d0 |

Updated: 2026-03-12
